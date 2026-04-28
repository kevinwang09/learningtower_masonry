import os
import json
import argparse
import tempfile
import yaml
import PyPDF2
from dotenv import load_dotenv
from llama_cloud import LlamaCloud

def parse_arguments():
    """Parse command line arguments for the extraction script."""
    parser = argparse.ArgumentParser(description="Extract codebook data from PDFs using LlamaCloud.")
    parser.add_argument("--tasks", type=str, required=True, help="Path to the tasks YAML file")
    parser.add_argument("--all-pages", action="store_true", default=False, help="Extract all pages instead of defaulting to the first 3 pages")
    parser.add_argument("--skip-confirmation", action="store_true", default=False, help="Skip user confirmation before running the API")
    return parser.parse_args()

def load_tasks_manifest(filepath):
    """Load and validate the tasks YAML manifest."""
    with open(filepath, "r") as f:
        task_manifest = yaml.safe_load(f)

    if not task_manifest:
        raise ValueError("The YAML tasks file is empty or invalid.")

    if "tasks" in task_manifest:
        return task_manifest["tasks"]
    elif "year" in task_manifest:
        return [task_manifest]
    else:
        raise ValueError("The YAML configuration must specify a 'tasks' list or a 'year'.")

def filter_pending_tasks(tasks):
    """
    Filter out files that have already been processed.
    Returns the list of files left to process, modifying the tasks in-place
    by adding a 'pending_files' list.
    """
    all_pending_files = []
    for task in tasks:
        pdfs = []
        if "school_file" in task:
            pdfs.append(task["school_file"])
        if "student_file" in task:
            pdfs.append(task["student_file"])
        if not pdfs and "files" in task:
            pdfs = task["files"]
            
        pending_pdfs = []
        for pdf_path in pdfs:
            if not os.path.exists(pdf_path):
                print(f"Warning: Input file {pdf_path} does not exist. Skipping.")
                continue
            
            output_path = pdf_path.replace(".pdf", "_extracted.json")
            if os.path.exists(output_path):
                print(f"Output file {output_path} already exists. Skipping extraction for {pdf_path}.")
            else:
                pending_pdfs.append(pdf_path)
                all_pending_files.append(pdf_path)
                
        task["pending_files"] = pending_pdfs
        
    return all_pending_files

def confirm_execution(pending_files, skip_confirmation):
    """Ask the user for confirmation to incur API costs."""
    if skip_confirmation:
        return True
        
    print(f"\nFiles queued for extraction ({len(pending_files)} total):")
    for f in pending_files:
        print(f" - {f}")
        
    confirmation = input(f"\nWARNING: You are about to use the LlamaCloud API for {len(pending_files)} files. This will incur API costs. \nDo you want to proceed? (y/n): ")
    if confirmation.strip().lower() not in ['y', 'yes']:
        print("Extraction cancelled by user.")
        return False
    return True

def initialize_llama_cloud_client():
    """Check for API key and initialize the LlamaCloud client."""
    api_key = os.environ.get("LLAMA_CLOUD_API_KEY")
    if not api_key:
        print("\nERROR: Missing LlamaCloud API Key.")
        print("To use LlamaCloud, you need to provide your API key.")
        print("You can add it by doing one of the following:")
        print("  1. Create a '.env' file in this directory and add the line: LLAMA_CLOUD_API_KEY=your_api_key_here")
        print("  2. Run this command with the variable exported: LLAMA_CLOUD_API_KEY=your_api_key_here python extract_codebook.py")
        print("\nYou can get an API key by signing up at https://cloud.llamaindex.ai/")
        return None

    print("Initializing LlamaCloud client...")
    try:
        return LlamaCloud(api_key=api_key)
    except Exception as e:
        print(f"Failed to initialize LlamaCloud client: {e}")
        return None

def prepare_pdf_for_extraction(pdf_path, extract_all_pages):
    """
    If not extracting all pages, subsets the PDF to the first 3 pages and saves it to a temp file.
    Returns the path to extract from and the temp file path (to be cleaned up later).
    """
    if extract_all_pages:
        print(f"\nProcessing {pdf_path} (All pages)...")
        return pdf_path, None

    print(f"\nProcessing {pdf_path} (First 3 pages)...")
    with open(pdf_path, "rb") as f_in:
        reader = PyPDF2.PdfReader(f_in)
        writer = PyPDF2.PdfWriter()
        total_pages = len(reader.pages)
        pages_to_extract = min(3, total_pages)
        for i in range(pages_to_extract):
            writer.add_page(reader.pages[i])
            
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as temp_pdf:
            writer.write(temp_pdf)
            return temp_pdf.name, temp_pdf.name

def process_pdf_extraction(client, file_to_extract, output_path, json_schema, year):
    """Uploads the PDF, runs the extraction API, and saves the output to a JSON file."""
    print("Extracting data using LlamaCloud API. This may take a while...")
    try:
        print("Uploading file...")
        with open(file_to_extract, "rb") as f:
            file_obj = client.files.create(file=f, purpose="extract")
        
        print("Running extraction...")
        result = client.extract.run(
            file_input=file_obj.id,
            configuration={
                "data_schema": json_schema
            },
        )
        
        output_data = result.extract_result
        if hasattr(output_data, "model_dump"):
            output_data = output_data.model_dump()
        elif hasattr(output_data, "dict"):
            output_data = output_data.dict()
            
        # Force the Year to match the task year as an integer
        output_data["Year"] = int(year)
        
        with open(output_path, "w") as f:
            json.dump(output_data, f, indent=2)
            
        print(f"Extraction complete! Saved to {output_path}")
        
    except Exception as e:
        print(f"Error extracting from {file_to_extract}: {e}")

def main():
    """Main orchestration function."""
    args = parse_arguments()
    load_dotenv()
    
    tasks = load_tasks_manifest(args.tasks)
    pending_files = filter_pending_tasks(tasks)
    
    if len(pending_files) == 0:
        print("\nAll requested files have already been processed or are missing. Exiting.")
        return
        
    if not confirm_execution(pending_files, args.skip_confirmation):
        return
        
    client = initialize_llama_cloud_client()
    if not client:
        return

    for task in tasks:
        year = task.get("year")
        if not year:
            print("Skipping task without a 'year' key.")
            continue
            
        pdfs_to_process = task.get("pending_files", [])
        if not pdfs_to_process:
            continue
            
        schema_file = task.get("schema_file", f"llamaextract_{year}.json")
        if not os.path.exists(schema_file):
            print(f"Year-specific schema JSON file '{schema_file}' not found for year {year}. Skipping.")
            continue

        with open(schema_file, "r") as f:
            config = json.load(f)

        json_schema = config.get("data_schema", {})
        if not json_schema:
            print(f"No 'data_schema' found in the schema file {schema_file}.")
            continue

        for pdf_path in pdfs_to_process:
            output_path = pdf_path.replace(".pdf", "_extracted.json")
            
            file_to_extract, temp_pdf_path = prepare_pdf_for_extraction(pdf_path, args.all_pages)
            
            try:
                process_pdf_extraction(client, file_to_extract, output_path, json_schema, year)
            finally:
                if temp_pdf_path and os.path.exists(temp_pdf_path):
                    os.remove(temp_pdf_path)

if __name__ == "__main__":
    main()
