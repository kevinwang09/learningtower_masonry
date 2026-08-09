"""
Parse PISA codebook PDFs into Markdown files using LlamaCloud.

This script handles Step 1 of the pipeline:
  PDF → Markdown (cached to codebook/markdown/)

Usage:
  python parse_codebook.py --tasks extraction_tasks.yaml
  python parse_codebook.py --tasks extraction_tasks.yaml --all-pages
  python parse_codebook.py --tasks extraction_tasks.yaml --skip-confirmation
"""
import os
import argparse
import tempfile
import PyPDF2

from llama_utils import (
    load_tasks_manifest,
    collect_pdf_files,
    get_markdown_path,
    initialize_client,
    estimate_cost_for_files,
    DEFAULT_PARSE_TIER,
    MARKDOWN_DIR,
)


def parse_arguments():
    """Parse command line arguments for the parse script."""
    parser = argparse.ArgumentParser(
        description="Parse PISA codebook PDFs into Markdown using LlamaCloud."
    )
    parser.add_argument("--tasks", type=str, required=True, help="Path to the tasks YAML file")
    parser.add_argument(
        "--all-pages", action="store_true", default=False,
        help="Parse all pages instead of defaulting to the first 3 pages",
    )
    parser.add_argument(
        "--skip-confirmation", action="store_true", default=False,
        help="Skip user confirmation before running the API",
    )
    return parser.parse_args()


def prepare_pdf_for_parsing(pdf_path, all_pages):
    """
    If not parsing all pages, subset the PDF to the first 3 pages.
    Returns (path_to_parse, temp_path_or_None).
    """
    if all_pages:
        print(f"\nProcessing {pdf_path} (All pages)...")
        return pdf_path, None

    print(f"\nProcessing {pdf_path} (First 3 pages)...")
    with open(pdf_path, "rb") as f_in:
        reader = PyPDF2.PdfReader(f_in)
        writer = PyPDF2.PdfWriter()
        pages_to_extract = min(3, len(reader.pages))
        for i in range(pages_to_extract):
            writer.add_page(reader.pages[i])

        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as temp_pdf:
            writer.write(temp_pdf)
            return temp_pdf.name, temp_pdf.name


def parse_pdf_to_markdown(client, file_to_parse, original_pdf_path):
    """
    Parse a single PDF to Markdown via LlamaCloud and cache the result.
    Returns the Markdown text, or None on failure.
    """
    md_file_path = get_markdown_path(original_pdf_path)

    # Skip if already cached
    if os.path.exists(md_file_path):
        print(f"  Markdown already cached at {md_file_path}. Skipping parse.")
        with open(md_file_path, "r", encoding="utf-8") as f:
            return f.read()

    print(f"  Parsing {file_to_parse} with LlamaCloud Parse...")
    try:
        with open(file_to_parse, "rb") as f:
            file_obj = client.files.create(file=f, purpose="parse")

        result = client.parsing.parse(
            file_id=file_obj.id,
            tier=DEFAULT_PARSE_TIER,
            version="latest",
            expand=["markdown_full"],
        )

        markdown_text = result.markdown_full
        print(f"  Parsed into Markdown ({len(markdown_text):,} chars).")

        # Cache to markdown directory
        with open(md_file_path, "w", encoding="utf-8") as f:
            f.write(markdown_text)
        print(f"  Cached to {md_file_path}")

        return markdown_text

    except Exception as e:
        print(f"  Error parsing {original_pdf_path}: {e}")
        return None


def main():
    args = parse_arguments()

    tasks = load_tasks_manifest(args.tasks)

    # Collect all PDFs from the manifest
    all_pdf_items = collect_pdf_files(tasks)

    # Filter out PDFs that already have cached Markdown
    pending = [(task, pdf) for task, pdf in all_pdf_items if not os.path.exists(get_markdown_path(pdf))]

    if not pending:
        print("\nAll PDFs already have cached Markdown files. Nothing to parse.")
        return

    pending_files = [pdf for _, pdf in pending]

    # Cost estimate and confirmation
    estimate_cost_for_files(pending_files, args.all_pages, parse=True, extract=False)

    if not args.skip_confirmation:
        confirmation = input("\nWARNING: You are about to use the LlamaCloud Parse API.\nProceed? (y/n): ")
        if confirmation.strip().lower() not in ["y", "yes"]:
            print("Parsing cancelled by user.")
            return

    # Initialize client
    client = initialize_client()
    if not client:
        return

    # Process each pending PDF
    success_count = 0
    for task, pdf_path in pending:
        if not os.path.exists(pdf_path):
            print(f"Warning: {pdf_path} does not exist. Skipping.")
            continue

        file_to_parse, temp_pdf_path = prepare_pdf_for_parsing(pdf_path, args.all_pages)
        try:
            result = parse_pdf_to_markdown(client, file_to_parse, pdf_path)
            if result:
                success_count += 1
        finally:
            if temp_pdf_path and os.path.exists(temp_pdf_path):
                os.remove(temp_pdf_path)

    print(f"\nDone. Parsed {success_count}/{len(pending)} PDFs → {MARKDOWN_DIR}/")


if __name__ == "__main__":
    main()
