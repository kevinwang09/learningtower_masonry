# PISA Codebook Extraction and Validation Pipeline

This directory contains the automated pipeline for extracting structured variable metadata from raw PISA PDF codebooks, converting them to JSON format, and validating them against our curated CSV schemas.

## Why LlamaIndex and LlamaParse?

Legacy PISA PDF codebooks are notoriously difficult to process due to complex table structures, nested hierarchies, and formatting drift across the years (2000-2022). Traditional PDF extraction libraries struggle to reliably extract relationships between variables, definitions, and their mapped categorical values.

We use **LlamaIndex** (specifically LlamaCloud and LlamaParse) because:

* **Advanced Document Understanding:** LlamaParse is specifically designed to understand complex document layouts, including nested tables, and output clean Markdown that preserves structural intent.
* **Structured Data Extraction:** The LlamaCloud Extract API allows us to define a strict JSON schema and confidently extract variable definitions, keys, and values directly from the text context using LLMs.

**Why parse to Markdown before extraction?**
While LlamaCloud can extract directly from PDFs, parsing to Markdown first gives us two critical advantages:

1. **Context Management:** PISA codebooks can be hundreds of pages long, exceeding LLM context windows. By parsing to Markdown first, we can programmatically identify variables (via "Seed Anchors") and create sliding, overlapping windows of text. This ensures we can process documents of infinite length without losing the context around any single variable.
2. **Cost and Iteration Speed:** Parsing a PDF to Markdown is relatively cheap. By saving the parsed Markdown to disk, we can iterate on our LLM extraction logic and fix issues without needing to constantly re-parse the heavy PDF file, saving both time and API credits.

## Pipeline Overview

The pipeline consists of three main components that work together to guarantee data fidelity:

1. **Manifest Configuration (`extraction_tasks.yaml`)**
2. **LLM-based Extraction (`extract_codebook.py` & Markdown)**
3. **Automated Validation (`validate_curation.py` & CSV Schemas)**

---

### 1. The Configuration Manifest (`extraction_tasks.yaml`)

This YAML file serves as the central orchestration manifest for the entire pipeline. It defines which PISA years to process and maps them to their respective school and student PDF codebooks, alongside the required LlamaCloud configuration.

### 2. The Extraction Process (`extract_codebook.py` & `extract_tabular_codebook.py`)

Depending on the format of the source codebook for a given year, we use one of two extraction methods:

**A. PDF Codebooks (e.g., 2000-2012) via `extract_codebook.py`:**
Because legacy PDF codebooks have varying and complex formats (and often exceed LLM context windows), we use an advanced chunking and extraction strategy:
* **Markdown Preprocessing:** Raw PDFs are first parsed into Markdown files (stored in `codebook/markdown/`). *Note: This step is typically handled by `parse_codebook.py`.*
* **Anchor-Based Sliding Window:** The script scans the markdown for "Seed Anchors" (e.g., uppercase variable names). It creates overlapping text windows based on these anchors to ensure no context is lost at the boundaries.
* **LlamaCloud Extract API:** These chunks are sent to LlamaCloud to extract structured data based on `extracted_pdf_schema.json`.
* **Deduplication & Sorting:** Overlapping results are deduplicated in Python and sorted chronologically to match the original document flow.

**B. Tabular Codebooks (e.g., 2015-2022) via `extract_tabular_codebook.py`:**
For more recent years, PISA releases codebooks in `.xlsx` format.
* **Pandas Parsing:** The script uses `pandas` to read specific sheets defined in the YAML manifest.
* **Heuristic Processing:** It processes each row sequentially, tracking the current "active" variable, inferring metadata, and extracting categorical discrete values into a dictionary.
* **NA Values:** It cleanly separates valid categorical mappings from `na_values` using predefined indicators.

Both methods generate a standardized JSON file format (e.g., `2015school_extracted.json`).

### 3. Architecture of the Codebook JSON

Regardless of whether the source was a PDF or an Excel spreadsheet, the output JSON strictly adheres to a standard schema architecture (defined in `extracted_pdf_schema.json` and `tabular_schema.json`).

The architecture of a generated codebook is a JSON object containing:
- `Year`: The integer year of the codebook.
- `cookbook_type`: Either `"school"` or `"student"`.
- `codebook_entries`: A list of objects, where each object represents a single variable in the codebook.

**Variable Architecture:**
Each variable entry in `codebook_entries` contains:
- `variable_key` (String): The uppercase ID of the variable (e.g., `"ST004D01T"`).
- `variable_description` (String): Human-readable definition or prompt.
- `format_specifier` (String): The data type or length format.
- `fixed_width_specification` (String): Byte-width locations (mostly relevant for legacy data).
- `variable_key_value` (List of Objects | Null): If the variable is discrete/categorical, this holds a list of `{"key": "1", "value": "Female"}` mappings. If continuous, this is `null`.
- `na_values` (List of Strings): A distinct list of keys representing missing/NA indicators (e.g., `["9997", "9999"]`).
- `source_page` (String): Where in the original document this was found.

### 4. The Validation Process (`validate_curation.py`)

Once the JSON codebooks are generated, we must ensure they align with our project's data architecture defined in the `variable_curation/` directory.

* The `validate_curation.py` script reads the `extraction_tasks.yaml` to iterate over all active years and datasets.
* It loads the newly generated `*_extracted.json` files and cross-references them against our curated mappings (`PISA_variable_curation_school.csv` and `PISA_variable_curation_student.csv`).
* **Validation Checks:**
  1. **Existence:** Confirms every source column defined in the CSV actually exists in the extracted codebook JSON.
  2. **NA Values:** Confirms that any `na_values` specified in the CSV (e.g., `9997;9999`) have corresponding documentation in the extracted JSON's value mapping list (`variable_key_value`).
* **Logging:** Validation results are output directly to the console and detailed logs are saved in the `logs/` directory (e.g., `logs/validate_2012_student.log`).

## Environment Setup

Before running the extraction pipeline, you must configure your Python environment and authenticate with LlamaCloud:

1. **Install Dependencies:**
   Ensure you have the required packages installed in your environment (e.g., your `learningtower` conda environment). The core requirements are `llama-cloud`, `llama-parse`, `jsonschema`, and `pyyaml`.

2. **Set up LlamaCloud API Key:**
   You must obtain an API key from [LlamaCloud](https://cloud.llamaindex.ai/) and set it as an environment variable in your terminal:

   ```bash
   export LLAMA_CLOUD_API_KEY="llx-your-api-key-here"
   ```

   *Note: LlamaCloud usage consumes credits. The extraction script will attempt to estimate costs and prompt for confirmation before running the extraction API.*

## How to Run the Pipeline

**1. Extract Codebooks to JSON**

```bash
python extract_codebook.py --tasks extraction_tasks.yaml
```

**2. Validate JSON against Curated CSVs**

```bash
python validate_curation.py --tasks extraction_tasks.yaml
```
