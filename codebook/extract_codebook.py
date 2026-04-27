import os
import json
import argparse
import tempfile
import yaml
import PyPDF2
from dotenv import load_dotenv
from llama_cloud import LlamaCloud

def extract_codebook():
    """
    Reads a PDF codebook and extracts it into a structured JSON file 
    based on the provided JSON schema config using LlamaExtract.
    """
    parser = argparse.ArgumentParser(description="Extract codebook data from PDFs using LlamaExtract.")
    parser.add_argument("--tasks", type=str, required=True, help="Path to the tasks YAML file")
    parser.add_argument("--all-pages", action="store_true", default=False, help="Extract all pages instead of defaulting to the first 3 pages")
    parser.add_argument("--skip-confirmation", action="store_true", default=False, help="Skip user confirmation before running the API")
    args = parser.parse_args()

    load_dotenv()

    # Load the YAML task manifest
    with open(args.tasks, "r") as f:
        task_manifest = yaml.safe_load(f)

    if not task_manifest:
        raise ValueError("The YAML tasks file is empty or invalid.")

    # Support a list of tasks or a single task configuration
    if "tasks" in task_manifest:
        tasks = task_manifest["tasks"]
    elif "year" in task_manifest:
        tasks = [task_manifest]
    else:
        raise ValueError("The YAML configuration must specify a 'tasks' list or a 'year'.")

    if not args.skip_confirmation:
        confirmation = input("\nWARNING: You are about to use the LlamaExtract API. This will incur API costs. \nDo you want to proceed? (y/n): ")
        if confirmation.strip().lower() not in ['y', 'yes']:
            print("Extraction cancelled by user.")
            return

    # Check for the API key and provide helpful instructions if it's missing
    api_key = os.environ.get("LLAMA_CLOUD_API_KEY")
    if not api_key:
        print("\nERROR: Missing LlamaCloud API Key.")
        print("To use LlamaExtract, you need to provide your API key.")
        print("You can add it by doing one of the following:")
        print("  1. Create a '.env' file in this directory and add the line: LLAMA_CLOUD_API_KEY=your_api_key_here")
        print("  2. Run this command with the variable exported: LLAMA_CLOUD_API_KEY=your_api_key_here python extract_codebook.py")
        print("\nYou can get an API key by signing up at https://cloud.llamaindex.ai/")
        return

    print("Initializing LlamaCloud client...")
    try:
        client = LlamaCloud(api_key=api_key)
    except Exception as e:
        print(f"Failed to initialize LlamaCloud client: {e}")
        return

    for task in tasks:
        year = task.get("year")
        if not year:
            print("Skipping task without a 'year' key.")
            continue
            
        schema_file = task.get("schema_file", f"llamaextract_{year}.json")
        if not os.path.exists(schema_file):
            raise FileExistsError(f"Year-specific schema JSON file '{schema_file}' not found for year {year}. Skipping.")

        pdfs_to_process = []
        if "school_file" in task:
            pdfs_to_process.append(task["school_file"])
        if "student_file" in task:
            pdfs_to_process.append(task["student_file"])
            
        if not pdfs_to_process:
            if "files" in task:
                pdfs_to_process = task["files"]
            else:
                print(f"No school_file or student_file specified for year {year}. Skipping.")
                continue

        # Load schema
        with open(schema_file, "r") as f:
            config = json.load(f)

        json_schema = config.get("data_schema", {})
        if not json_schema:
            raise ValueError(f"No 'data_schema' found in the schema file {schema_file}.")

        for pdf_path in pdfs_to_process:
            if not os.path.exists(pdf_path):
                raise FileExistsError(f"File {pdf_path} does not exist. Skipping.")
                
            output_path = pdf_path.replace(".pdf", "_extracted.json")
            
            # Skip processing if output file already exists
            if os.path.exists(output_path):
                print(f"Output file {output_path} already exists. Skipping extraction for {pdf_path}.")
                continue
                
            temp_pdf_path = None
            if not args.all_pages:
                print(f"\nProcessing {pdf_path} (First 3 pages)...")
                # Subset the PDF to the first 3 pages
                with open(pdf_path, "rb") as f_in:
                    reader = PyPDF2.PdfReader(f_in)
                    writer = PyPDF2.PdfWriter()
                    total_pages = len(reader.pages)
                    pages_to_extract = min(3, total_pages)
                    for i in range(pages_to_extract):
                        writer.add_page(reader.pages[i])
                        
                    # Use a temporary file to store the subset
                    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as temp_pdf:
                        writer.write(temp_pdf)
                        temp_pdf_path = temp_pdf.name
                file_to_extract = temp_pdf_path
            else:
                print(f"\nProcessing {pdf_path} (All pages)...")
                file_to_extract = pdf_path
            
            print("Extracting data using LlamaCloud API. This may take a while...")
            try:
                # Upload the file
                print("Uploading file...")
                with open(file_to_extract, "rb") as f:
                    file_obj = client.files.create(file=f, purpose="extract")
                
                # Extract structured data
                print("Running extraction...")
                result = client.extract.run(
                    file_input=file_obj.id,
                    configuration={
                        "data_schema": json_schema,
                        "tier": "agentic",
                        "extraction_target": "per_doc",
                        "parse_tier": "agentic",
                        "cite_sources": True,
                        "confidence_scores": True
                    },
                )
                
                # output_data could be a dict or a Pydantic model depending on SDK version
                output_data = result.extract_result
                if hasattr(output_data, "model_dump"):
                    output_data = output_data.model_dump()
                elif hasattr(output_data, "dict"):
                    output_data = output_data.dict()
                
                with open(output_path, "w") as f:
                    json.dump(output_data, f, indent=2)
                    
                print(f"Extraction complete! Saved to {output_path}")
                
            except Exception as e:
                print(f"Error extracting from {pdf_path}: {e}")
            finally:
                if temp_pdf_path and os.path.exists(temp_pdf_path):
                    os.remove(temp_pdf_path)

if __name__ == "__main__":
    extract_codebook()
