import os
import json
import argparse
import tempfile
import yaml
import re
import PyPDF2
import jsonschema
from dotenv import load_dotenv
from llama_cloud import LlamaCloud

# Canonical field names for extracted variable entries
CANONICAL_FIELDS = {
    # Maps possible LLM-returned field names -> our canonical name
    "Variable": "variable_key",
    "variable_key": "variable_key",
    "Format": "format_specifier",
    "format_specifier": "format_specifier",
    "Values": "variable_key_value",
    "variable_key_value": "variable_key_value",
    "Description": "variable_description",
    "variable_description": "variable_description",
    "FixedWidth": "fixed_width_specification",
    "fixed_width_specification": "fixed_width_specification",
    "Year": "Year",
}

def normalize_variable_entry(entry):
    """Normalize an extracted variable dict to use canonical field names."""
    normalized = {}
    for key, value in entry.items():
        canonical = CANONICAL_FIELDS.get(key, key)
        normalized[canonical] = value
    return normalized

def load_output_schema():
    """Load the unified validation schema for extracted JSON output."""
    schema_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extracted_schema.json")
    if os.path.exists(schema_path):
        with open(schema_path, "r") as f:
            return json.load(f)
    return None

def parse_arguments():
    """Parse command line arguments for the extraction script."""
    parser = argparse.ArgumentParser(description="Extract codebook data from PDFs using LlamaCloud.")
    parser.add_argument("--tasks", type=str, required=True, help="Path to the tasks YAML file")
    parser.add_argument("--all-pages", action="store_true", default=False, help="Extract all pages instead of defaulting to the first 3 pages")
    parser.add_argument("--skip-confirmation", action="store_true", default=False, help="Skip user confirmation before running the API")
    parser.add_argument("--skip-parse", action="store_true", default=False, help="Skip the parsing step and use existing markdown files")
    parser.add_argument("--skip-extract", action="store_true", default=False, help="Skip the extraction step and only save the markdown")
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

# Pricing constants (credits per page)
PARSE_COSTS = {
    "fast": 1,
    "cost_effective": 3,
    "agentic": 10,
    "agentic_plus": 45
}
# Extract costs for previously parsed files (extract-only rate)
EXTRACT_COSTS = {
    "cost_effective": 5,
    "agentic": 15
}
# # Approximate cost: $1.25 per 1,000 credits
# USD_PER_CREDIT = 1.25 / 1000

# Directory for intermediate markdown files
MARKDOWN_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "markdown")
os.makedirs(MARKDOWN_DIR, exist_ok=True)

def confirm_execution(pending_files, skip_confirmation, extract_all_pages, skip_parse, skip_extract):
    """Ask the user for confirmation to incur API costs and provide an estimate."""
    if skip_confirmation:
        return True
        
    total_pages_to_process = 0
    parse_tier = "fast"      # Hardcoded in process_pdf_extraction
    extract_tier = "agentic" # Default used by client.extract.run
    
    cost_per_page = 0
    if not skip_parse:
        cost_per_page += PARSE_COSTS.get(parse_tier, 0)
    if not skip_extract:
        cost_per_page += EXTRACT_COSTS.get(extract_tier, 0)
    
    print(f"\nFiles queued for extraction ({len(pending_files)} total):")
    for f in pending_files:
        try:
            with open(f, "rb") as f_in:
                reader = PyPDF2.PdfReader(f_in)
                total_pages = len(reader.pages)
                if extract_all_pages:
                    extract_num = total_pages
                    print(f" - {f} (All {total_pages} pages)")
                else:
                    extract_num = min(3, total_pages)
                    print(f" - {f} (First {extract_num} of {total_pages} pages)")
                total_pages_to_process += extract_num
        except Exception as e:
            print(f" - {f} (Error reading page count: {e})")
    
    estimated_credits = total_pages_to_process * cost_per_page
    
    print(f"\n--- Cost Estimate ---")
    print(f"Total pages to process: {total_pages_to_process}")
    print(f"Estimated credits:     {estimated_credits:,} ({cost_per_page} credits/page)")
    print(f"----------------------")
        
    confirmation = input(f"\nWARNING: You are about to use the LlamaCloud API. \nDo you want to proceed? (y/n): ")
    if confirmation.strip().lower() not in ['y', 'yes']:
        print("Extraction cancelled by user.")
        return False
    return True

def initialize_clients():
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
        client = LlamaCloud(api_key=api_key)
        return client
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

def process_pdf_extraction(client, file_to_extract, original_pdf_path, output_path, json_schema, year, skip_parse=False, skip_extract=False):
    """
    Batch-based Parse-then-Extract pipeline:
      1. (Optional) Parse PDF to Markdown using LlamaCloud.
      2. Split Markdown into individual variables using Regex.
      3. Group variables into batches of 20 to avoid LLM context fatigue.
      4. Iteratively run extraction for each batch and aggregate results.
    """
    markdown_text = None
    
    # Markdown file path in the dedicated subdirectory
    md_filename = os.path.basename(original_pdf_path).replace(".pdf", ".md")
    md_file_path = os.path.join(MARKDOWN_DIR, md_filename)

    try:
        # Step 1: Check for existing Markdown or Parse new
        if os.path.exists(md_file_path) and not skip_parse:
            print(f"  Using existing Markdown file found in {MARKDOWN_DIR}...")
            with open(md_file_path, "r", encoding="utf-8") as f:
                markdown_text = f.read()
        elif skip_parse:
            if not os.path.exists(md_file_path):
                print(f"  Error: --skip-parse was set but {md_file_path} not found.")
                return
            print(f"  Loading existing Markdown from {md_file_path}...")
            with open(md_file_path, "r", encoding="utf-8") as f:
                markdown_text = f.read()
        else:
            # Parse PDF → Markdown using the new llama-cloud SDK
            print(f"Parsing {file_to_extract} with LlamaCloud Parse...")
            with open(file_to_extract, "rb") as f:
                file_obj_parse = client.files.create(file=f, purpose="parse")
            parse_result = client.parsing.parse(
                file_id=file_obj_parse.id,
                tier="fast",
                version="latest",
                expand=["markdown_full"],  # returns the full document as a single string
            )
            markdown_text = parse_result.markdown_full
            print(f"  Parsed into a single Markdown document ({len(markdown_text):,} chars).")
            
            # Save the result to the markdown directory for future use
            with open(md_file_path, "w", encoding="utf-8") as f:
                f.write(markdown_text)
            print(f"  Markdown cached to {md_file_path}")

        if skip_extract:
            print(f"  Extraction skipped per request.")
            return

        # Step 1b: Regex Chunking & Batching
        print("Chunking Markdown into individual variables...")
        # Split by the variable anchor pattern: Word/Alphanumeric + space + (Number)
        # e.g., "SC01Q01 (5) School location" or "COUNTRY (1) Country ID"
        chunks = re.split(r'(?m)^([A-Z0-9_]+ \(\d+\)\s+)', markdown_text)
        
        variables = []
        start_idx = 1 if len(chunks) > 1 else 0
        for i in range(start_idx, len(chunks), 2):
            var_name = chunks[i]
            var_content = chunks[i+1] if i+1 < len(chunks) else ""
            variables.append(var_name + var_content)
            
        batch_size = 20
        batches = ["\n\n".join(variables[i:i + batch_size]) for i in range(0, len(variables), batch_size)]
        print(f"  Split into {len(variables)} variables across {len(batches)} batches.")

        all_extracted_variables = []

        # Step 2-4: Iterative Extraction
        for idx, batch_content in enumerate(batches):
            print(f"Processing batch {idx+1}/{len(batches)}...")
            temp_md_path = None
            try:
                # Save batch to a temp file for upload
                with tempfile.NamedTemporaryFile(suffix=".md", delete=False, mode="w", encoding="utf-8") as temp_md:
                    temp_md.write(batch_content)
                    temp_md_path = temp_md.name

                # Upload to LlamaCloud
                with open(temp_md_path, "rb") as f:
                    file_obj = client.files.create(file=f, purpose="extract")

                # Run LlamaExtract
                result = client.extract.run(
                    file_input=file_obj.id,
                    configuration={
                        "data_schema": json_schema
                    },
                )

                batch_data = result.extract_result
                if hasattr(batch_data, "model_dump"):
                    batch_data = batch_data.model_dump()
                elif hasattr(batch_data, "dict"):
                    batch_data = batch_data.dict()
                
                # Extract variables list from response (handle varying root keys)
                batch_vars = []
                if isinstance(batch_data, dict):
                    # Try known root keys: Variables, codebook_entries, or any list
                    for key in ["Variables", "codebook_entries"]:
                        if key in batch_data and isinstance(batch_data[key], list):
                            batch_vars = batch_data[key]
                            break
                    if not batch_vars:
                        for val in batch_data.values():
                            if isinstance(val, list):
                                batch_vars = val
                                break
                elif isinstance(batch_data, list):
                    batch_vars = batch_data
                
                # Normalize field names in each entry to canonical form
                batch_vars = [normalize_variable_entry(v) for v in batch_vars]
                
                print(f"  Extracted {len(batch_vars)} variables from batch {idx+1}.")
                all_extracted_variables.extend(batch_vars)

            finally:
                if temp_md_path and os.path.exists(temp_md_path):
                    os.remove(temp_md_path)

        # Final aggregation using canonical structure (matching llamaconfig.json)
        output_data = {"codebook_entries": all_extracted_variables}
        
        # Post-process: Ensure Year is integer and matches task year
        for var in output_data["codebook_entries"]:
            var["Year"] = int(year)

        # Validate output against the unified schema before saving
        output_schema = load_output_schema()
        if output_schema:
            try:
                jsonschema.validate(instance=output_data, schema=output_schema)
                print("Schema validation passed.")
            except jsonschema.exceptions.ValidationError as e:
                print(f"WARNING: Output failed schema validation: {e.message}")
                print("The file will still be saved for inspection, but may need manual fixes.")

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, indent=2)
            
        print(f"Extraction complete! Aggregated {len(all_extracted_variables)} variables into {output_path}")

    except Exception as e:
        print(f"Error during processing: {e}")

def main():
    """Main orchestration function."""
    args = parse_arguments()
    load_dotenv()
    
    tasks = load_tasks_manifest(args.tasks)
    pending_files = filter_pending_tasks(tasks)
    
    if len(pending_files) == 0:
        print("\nAll requested files have already been processed or are missing. Exiting.")
        return
        
    if not confirm_execution(pending_files, args.skip_confirmation, args.all_pages, args.skip_parse, args.skip_extract):
        return
        
    client = initialize_clients()
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
                process_pdf_extraction(client, file_to_extract, pdf_path, output_path, json_schema, year, args.skip_parse, args.skip_extract)
            finally:
                if temp_pdf_path and os.path.exists(temp_pdf_path):
                    os.remove(temp_pdf_path)

if __name__ == "__main__":
    main()
