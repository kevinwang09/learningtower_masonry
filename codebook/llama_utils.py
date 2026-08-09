"""
Shared utilities for the PISA codebook extraction pipeline.

Contains:
- LlamaCloud client initialization
- Task manifest loading and filtering
- Variable entry normalization (canonical field names)
- Schema loading
- Cost estimation constants
- Markdown cache directory management
"""
import os
import json
import yaml
import PyPDF2
from dotenv import load_dotenv
from llama_cloud import LlamaCloud, AsyncLlamaCloud

# ---------------------------------------------------------------------------
# Canonical field names for extracted variable entries
# Maps possible LLM-returned field names -> our canonical name
# (matches the schema defined in llamaconfig.json)
# ---------------------------------------------------------------------------
CANONICAL_FIELDS = {
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

# ---------------------------------------------------------------------------
# Pricing constants (credits per page)
# ---------------------------------------------------------------------------
PARSE_COSTS = {
    "fast": 1,
    "cost_effective": 3,
    "agentic": 10,
    "agentic_plus": 45,
}

EXTRACT_COSTS = {
    "cost_effective": 5,
    "agentic": 15,
}

# Default tiers used across the pipeline
DEFAULT_PARSE_TIER = "fast"
DEFAULT_EXTRACT_TIER = "cost_effective"

# Directory for intermediate markdown files
CODEBOOK_DIR = os.path.dirname(os.path.abspath(__file__))
MARKDOWN_DIR = os.path.join(CODEBOOK_DIR, "markdown")
os.makedirs(MARKDOWN_DIR, exist_ok=True)


# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

def normalize_variable_entry(entry):
    """Normalize an extracted variable dict to use canonical field names."""
    normalized = {}
    for key, value in entry.items():
        canonical = CANONICAL_FIELDS.get(key, key)
        normalized[canonical] = value
    return normalized


def load_output_schema():
    """Load the unified validation schema for extracted JSON output."""
    schema_path = os.path.join(CODEBOOK_DIR, "extracted_pdf_schema.json")
    if os.path.exists(schema_path):
        with open(schema_path, "r") as f:
            return json.load(f)
    return None


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


def collect_pdf_files(tasks):
    """
    Collect all PDF file paths referenced in the task manifest.
    Returns a list of (task, pdf_path) tuples.
    """
    results = []
    for task in tasks:
        for file_type in ["school_file", "student_file"]:
            pdf_path = task.get(file_type)
            if isinstance(pdf_path, str) and pdf_path.lower().endswith(".pdf"):
                results.append((task, pdf_path))
        # Fallback for legacy "files" key
        for pdf_path in task.get("files", []):
            if isinstance(pdf_path, str) and pdf_path.lower().endswith(".pdf"):
                results.append((task, pdf_path))
    return results


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
            val = task["school_file"]
            if isinstance(val, str) and val.lower().endswith(".pdf"):
                pdfs.append(val)
        if "student_file" in task:
            val = task["student_file"]
            if isinstance(val, str) and val.lower().endswith(".pdf"):
                pdfs.append(val)
        if not pdfs and "files" in task:
            for val in task["files"]:
                if isinstance(val, str) and val.lower().endswith(".pdf"):
                    pdfs.append(val)

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


def get_markdown_path(pdf_path):
    """Return the cached Markdown file path for a given PDF."""
    md_filename = os.path.basename(pdf_path).replace(".pdf", ".md")
    return os.path.join(MARKDOWN_DIR, md_filename)


def initialize_client():
    """Check for API key and initialize the LlamaCloud client."""
    load_dotenv()

    api_key = os.environ.get("LLAMA_CLOUD_API_KEY")
    if not api_key:
        print("\nERROR: Missing LlamaCloud API Key.")
        print("To use LlamaCloud, you need to provide your API key.")
        print("You can add it by doing one of the following:")
        print("  1. Create a '.env' file in this directory and add the line: LLAMA_CLOUD_API_KEY=your_api_key_here")
        print("  2. Run this command with the variable exported: LLAMA_CLOUD_API_KEY=your_api_key_here python <script>.py")
        print("\nYou can get an API key by signing up at https://cloud.llamaindex.ai/")
        return None

    print("Initializing LlamaCloud client...")
    try:
        client = LlamaCloud(api_key=api_key)
        return client
    except Exception as e:
        print(f"Failed to initialize LlamaCloud client: {e}")
        return None


def initialize_async_client():
    """Check for API key and initialize the AsyncLlamaCloud client."""
    load_dotenv()

    api_key = os.environ.get("LLAMA_CLOUD_API_KEY")
    if not api_key:
        # Error message already handled in initialize_client
        return None

    try:
        client = AsyncLlamaCloud(api_key=api_key)
        return client
    except Exception as e:
        print(f"Failed to initialize AsyncLlamaCloud client: {e}")
        return None


def load_extraction_config(task, year):
    """Load the full extraction configuration from the task's schema_file."""
    schema_file = task.get("schema_file", f"llamaextract_{year}.json")
    if not os.path.exists(schema_file):
        print(f"Schema file '{schema_file}' not found for year {year}. Skipping.")
        return None

    with open(schema_file, "r") as f:
        config = json.load(f)

    if "data_schema" not in config:
        print(f"No 'data_schema' found in {schema_file}.")
        return None
    return config


def estimate_cost_for_files(file_list, all_pages, parse=True, extract=True):
    """
    Print cost estimate for a list of PDF files.
    Returns total estimated credits.
    """
    parse_tier = DEFAULT_PARSE_TIER
    extract_tier = DEFAULT_EXTRACT_TIER

    cost_per_page = 0
    if parse:
        cost_per_page += PARSE_COSTS.get(parse_tier, 0)
    if extract:
        cost_per_page += EXTRACT_COSTS.get(extract_tier, 0)

    total_pages = 0
    print(f"\nFiles queued ({len(file_list)} total):")
    for f_path in file_list:
        try:
            with open(f_path, "rb") as f_in:
                reader = PyPDF2.PdfReader(f_in)
                n_pages = len(reader.pages)
                if all_pages:
                    extract_num = n_pages
                    print(f" - {f_path} (All {n_pages} pages)")
                else:
                    extract_num = min(3, n_pages)
                    print(f" - {f_path} (First {extract_num} of {n_pages} pages)")
                total_pages += extract_num
        except Exception as e:
            print(f" - {f_path} (Error reading page count: {e})")

    estimated_credits = total_pages * cost_per_page

    print(f"\n--- Cost Estimate ---")
    print(f"Total raw pages:       {total_pages}")
    print(f"Base estimated credits: {estimated_credits:,} ({cost_per_page} credits/page)")
    print(f"WARNING: Actual cost will be significantly higher due to sliding window overlap and per-chunk API minimums.")
    print(f"----------------------")

    return estimated_credits
