"""
Extract structured codebook data from cached Markdown files using LlamaCloud.

This script handles Step 2 of the pipeline:
  Markdown → Anchor-Based Sliding Window Chunking → LLM Extraction → Dedup → JSON

The "Anchor-Based Sliding Window" strategy:
  1. Find all potential variable anchors using a universal regex pattern
     (e.g., uppercase identifiers at the start of a line).
  2. Create overlapping text windows (chunks) based on these anchor positions.
  3. Extract structured data from each window using the LlamaCloud Extract API.
  4. Deduplicate the aggregated results by 'variable_key' in Python.

Key Parameters:
  - anchor:      A "Seed Anchor" is a text pattern that reliably identifies the start of a
                 variable definition in the codebook (e.g., "COUNTRY (3)" or "ST01Q01 (1)").
                 The script uses these to map the document's structure regardless of
                 formatting changes between PISA years.
  - window_size: The number of variable anchors included in a single extraction chunk.
                 A larger window provides more context but may exceed LLM attention limits.
  - step_size:   The number of anchors to advance between chunks.
                 The overlap between consecutive chunks is (window_size - step_size).
                 This overlap ensures that variables near a chunk boundary are captured
                 with full context in at least one window.

Batch Determination:
  The number of extraction batches (chunks) is determined by the total number of anchors
  found in the document divided by the step_size. Because the windows overlap to preserve
  context, this results in more batches than a simple non-overlapping split (which would
  be anchors / window_size). Each batch is sent as a separate request to the extraction endpoint.

This approach is robust to formatting drift across PISA years (2000–2015).

Prerequisites:
  Markdown files must already exist in codebook/markdown/.
  Run parse_codebook.py first if they don't.

Usage:
  python extract_codebook.py --tasks extraction_tasks.yaml
  python extract_codebook.py --tasks extraction_tasks.yaml --all-pages
  python extract_codebook.py --tasks extraction_tasks.yaml --window-size 30 --step-size 27
"""
import os
import json
import argparse
import tempfile
import re
import jsonschema
import asyncio

from llama_utils import (
    load_tasks_manifest,
    collect_pdf_files,
    get_markdown_path,
    initialize_client,
    initialize_async_client,
    load_extraction_config,
    load_output_schema,
    normalize_variable_entry,
    DEFAULT_EXTRACT_TIER,
    MARKDOWN_DIR,
)


def parse_arguments():
    """Parse command line arguments for the extraction script."""
    parser = argparse.ArgumentParser(
        description="Extract codebook data from Markdown files using LlamaCloud Extract."
    )
    parser.add_argument("--tasks", type=str, required=True, help="Path to the tasks YAML file")
    parser.add_argument(
        "--all-pages", action="store_true", default=False,
        help="Extract all pages of the Markdown. Without this flag, only the first 3 pages are used.",
    )
    parser.add_argument(
        "--skip-confirmation", action="store_true", default=False,
        help="Skip user confirmation before running the API",
    )
    parser.add_argument(
        "--window-size", type=int, default=30,
        help="Number of variable anchors per extraction window (default: 30)",
    )
    parser.add_argument(
        "--step-size", type=int, default=27,
        help="Number of anchors to advance between windows; overlap = window - step (default: 27)",
    )
    return parser.parse_args()


def truncate_to_pages(markdown_text, max_pages=3):
    """
    Truncate Markdown text to the first `max_pages` pages.

    LlamaParse inserts '---' on its own line as a page separator.
    We split by that marker and keep the first `max_pages` sections.
    If no separators are found, the full text is returned as-is.
    """
    pages = re.split(r'(?m)^---$', markdown_text)
    if len(pages) <= max_pages:
        return markdown_text

    truncated = "---".join(pages[:max_pages])
    print(f"  Truncated to first {max_pages} pages ({len(pages)} total in file).")
    return truncated


def get_expected_variables(markdown_text):
    """
    Returns a dictionary mapping expected variable_keys to their raw text blocks,
    preserving the chronological order of the document.
    """
    # Relaxed regex to handle both plain text and Markdown/HTML table cells
    anchor_pattern = re.compile(r'(?:^|<td>|>|\s)([A-Z][A-Z0-9_]{2,9})(?:</td>|<|\s+|\()')
    matches = list(anchor_pattern.finditer(markdown_text))
    
    expected_vars = {}
    for i, match in enumerate(matches):
        key = match.group(1).strip().upper()
        # Filter out common false positives (like HTML tags or table headers)
        if key in ["VARIABLE", "NAME", "POSITION", "FORMAT", "COLUMNS", "VALUE", "LABEL"]:
             continue
             
        start_idx = match.start(1) # Start at the actual variable name
        end_idx = matches[i+1].start(1) if i+1 < len(matches) else len(markdown_text)
        expected_vars[key] = markdown_text[start_idx:end_idx]
        
    return expected_vars


def chunk_markdown(markdown_text, window_size=30, step_size=27):
    # Use the same relaxed regex here
    anchor_pattern = re.compile(r'(?:^|<td>|>|\s)([A-Z][A-Z0-9_]{2,9})(?:</td>|<|\s+|\()')
    matches = list(anchor_pattern.finditer(markdown_text))
    
    # Filter out the table header false positives to keep chunks aligned
    valid_matches = []
    for m in matches:
        key = m.group(1).strip().upper()
        if key not in ["VARIABLE", "NAME", "POSITION", "FORMAT", "COLUMNS", "VALUE", "LABEL"]:
            valid_matches.append(m)
            
    indices = [m.start(1) for m in valid_matches]

    if not indices:
        return [markdown_text]

    chunks = []
    for i in range(0, len(indices), step_size):
        start = indices[i]
        end_idx = i + window_size
        end = indices[end_idx] if end_idx < len(indices) else len(markdown_text)
        chunks.append(markdown_text[start:end])

    return chunks


def deduplicate_variables(variables):
    """
    Remove duplicate variable entries produced by overlapping windows.

    When the same variable_key appears in multiple extraction windows,
    we keep the first occurrence (which typically has the best context
    since it appears closer to the center of its window).

    Returns:
        A deduplicated list of variable dicts, preserving insertion order.
    """
    seen = {}
    for var in variables:
        key = var.get("variable_key", "").strip().upper()
        if key and key not in seen:
            seen[key] = var
    deduped = list(seen.values())
    n_dupes = len(variables) - len(deduped)
    if n_dupes > 0:
        print(f"  Deduplication: removed {n_dupes} duplicate entries ({len(variables)} → {len(deduped)} unique variables).")
    return deduped


async def extract_batch(async_client, batch_content, extraction_config, batch_num, total_batches, semaphore):
    """
    Upload a batch of Markdown variable text and run LlamaCloud Extract asynchronously.
    Returns a list of normalized variable dicts.
    """
    async with semaphore:
        print(f"  Starting batch {batch_num}/{total_batches}...")
        temp_md_path = None
        try:
            # Save batch to a temp file for upload
            with tempfile.NamedTemporaryFile(suffix=".md", delete=False, mode="w", encoding="utf-8") as temp_md:
                temp_md.write(batch_content)
                temp_md_path = temp_md.name

            # Upload to LlamaCloud
            with open(temp_md_path, "rb") as f:
                file_obj = await async_client.files.create(file=f, purpose="extract")

            # Run LlamaExtract
            # Note: Using AsyncLlamaCloud's run equivalent
            try:
                result = await asyncio.wait_for(
                    async_client.extract.run(
                        file_input=file_obj.id,
                        configuration=extraction_config,
                    ),
                    timeout=600.0  # 10 minute absolute timeout per batch
                )
            except asyncio.TimeoutError:
                print(f"    [TIMEOUT] Batch {batch_num} exceeded 10 minutes. Skipping for now (will be caught by patch logic later).")
                return []

            batch_data = result.extract_result
            if hasattr(batch_data, "model_dump"):
                batch_data = batch_data.model_dump()
            elif hasattr(batch_data, "dict"):
                batch_data = batch_data.dict()

            # Extract variables list from response (handle varying root keys)
            batch_vars = []
            if isinstance(batch_data, dict):
                for key in ["codebook_entries", "Variables"]:
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

            # Normalize field names to canonical form
            batch_vars = [normalize_variable_entry(v) for v in batch_vars]

            print(f"    Extracted {len(batch_vars)} variables from batch {batch_num}.")
            return batch_vars

        except Exception as e:
            print(f"  Error in batch {batch_num}: {e}")
            return []
        finally:
            if temp_md_path and os.path.exists(temp_md_path):
                os.remove(temp_md_path)


async def process_extraction(async_client, chunks, output_path, extraction_config, year,
                               expected_vars, existing_variables, concurrency_limit=10):
    """
    Extracts chunks concurrently, deduplicates, merges with existing variables,
    sorts chronologically, and saves to JSON.
    """
    all_extracted_variables = list(existing_variables)
    
    expected_order = {k: i for i, k in enumerate(expected_vars.keys())}
    def sort_key(var):
        k = var.get("variable_key", "").strip().upper()
        return expected_order.get(k, float('inf'))
        
    if chunks:
        # Concurrent extraction with semaphore
        print(f"  Submitting {len(chunks)} chunks to LlamaCloud (concurrency limit: {concurrency_limit})...")
        semaphore = asyncio.Semaphore(concurrency_limit)
        tasks = []
        for idx, chunk_content in enumerate(chunks):
            tasks.append(extract_batch(async_client, chunk_content, extraction_config, idx + 1, len(chunks), semaphore))

        # Incremental checkpointing
        for future in asyncio.as_completed(tasks):
            batch_vars = await future
            if batch_vars:
                # Merge immediately
                all_extracted_variables.extend(batch_vars)
                # Deduplicate
                all_extracted_variables = deduplicate_variables(all_extracted_variables)
                # Sort
                all_extracted_variables.sort(key=sort_key)

                # Save checkpoint
                output_data = {"codebook_entries": all_extracted_variables}
                for var in output_data["codebook_entries"]:
                    var["Year"] = int(year)
                    
                with open(output_path, "w", encoding="utf-8") as f:
                    json.dump(output_data, f, indent=2)
                print(f"  [Checkpoint] Saved {len(all_extracted_variables)} variables to {output_path}")

    else:
        # No chunks to extract, but we still sort and save to ensure consistency
        all_extracted_variables.sort(key=sort_key)
        output_data = {"codebook_entries": all_extracted_variables}
        for var in output_data["codebook_entries"]:
            var["Year"] = int(year)
            
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(output_data, f, indent=2)

    # Post-process: Ensure Year is integer and matches task year
    for var in output_data["codebook_entries"]:
        var["Year"] = int(year)

    # Validate output against the unified schema before saving
    output_schema = load_output_schema()
    if output_schema:
        try:
            jsonschema.validate(instance=output_data, schema=output_schema)
            print("  Schema validation passed.")
        except jsonschema.exceptions.ValidationError as e:
            print(f"  WARNING: Output failed schema validation: {e.message}")
            print("  The file will still be saved for inspection, but may need manual fixes.")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent=2)

    print(f"  Extraction complete! {len(all_extracted_variables)} unique variables → {output_path}")


def main():
    args = parse_arguments()

    tasks = load_tasks_manifest(args.tasks)
    all_pdf_items = collect_pdf_files(tasks)

    # Prepare tasks and determine diffs
    pending = []
    total_chunks = 0
    for task, pdf_path in all_pdf_items:
        output_path = pdf_path.replace(".pdf", "_extracted.json")
        md_path = get_markdown_path(pdf_path)

        if not os.path.exists(md_path):
            print(f"Markdown {md_path} not found. Run parse_codebook.py first. Skipping.")
            continue

        with open(md_path, "r", encoding="utf-8") as f:
            markdown_text = f.read()

        if not args.all_pages:
            markdown_text = truncate_to_pages(markdown_text, max_pages=3)

        expected_vars = get_expected_variables(markdown_text)

        existing_variables = []
        if os.path.exists(output_path):
            with open(output_path, "r", encoding="utf-8") as f:
                try:
                    data = json.load(f)
                    existing_variables = data.get("codebook_entries", [])
                except Exception as e:
                    print(f"Error reading existing {output_path}: {e}")

        existing_keys = {var.get("variable_key", "").strip().upper() for var in existing_variables}
        missing_keys = [k for k in expected_vars.keys() if k not in existing_keys]

        chunks = []
        if len(missing_keys) == len(expected_vars) or not existing_variables:
            # Full extraction
            chunks = chunk_markdown(markdown_text, window_size=args.window_size, step_size=args.step_size)
        elif missing_keys:
            # Patch extraction
            missing_blocks = [expected_vars[k] for k in missing_keys]
            for i in range(0, len(missing_blocks), args.window_size):
                batch = "\n\n".join(missing_blocks[i:i+args.window_size])
                chunks.append(batch)

        pending.append({
            "task": task,
            "pdf_path": pdf_path,
            "output_path": output_path,
            "chunks": chunks,
            "expected_vars": expected_vars,
            "existing_variables": existing_variables,
            "missing_keys": missing_keys,
            "year": task.get("year")
        })
        total_chunks += len(chunks)

    if not pending:
        print("\nAll files missing Markdown. Nothing to do.")
        return

    # Cost Estimate based on chunks
    extract_tier = DEFAULT_EXTRACT_TIER
    from llama_utils import EXTRACT_COSTS
    cost_per_page = EXTRACT_COSTS.get(extract_tier, 5)

    print(f"\nFiles queued for extraction ({len(pending)} total):")
    for item in pending:
        pdf = item["pdf_path"]
        n_expected = len(item["expected_vars"])
        n_missing = len(item["missing_keys"])
        n_chunks = len(item["chunks"])
        if n_missing == n_expected or not item["existing_variables"]:
            print(f"  - {pdf} (Full Extraction: {n_chunks} chunks)")
        elif n_missing > 0:
            print(f"  - {pdf} (Patch Extraction: {n_missing} missing variables -> {n_chunks} chunks)")
        else:
            print(f"  - {pdf} (No extraction needed, just sorting)")

    estimated_credits = total_chunks * cost_per_page
    print(f"\n--- Cost Estimate ---")
    print(f"Total files to process:       {len(pending)}")
    print(f"Total API requests (chunks):  {total_chunks}")
    print(f"Extract tier:                 {extract_tier} ({cost_per_page} credits/page)")
    print(f"Minimum estimated credits:    {estimated_credits:,} (assuming 1 page per chunk)")
    print(f"WARNING: Actual cost will be significantly higher due to sliding window overlap and per-chunk API minimums.")
    print(f"----------------------")

    if not args.skip_confirmation and total_chunks > 0:
        confirmation = input("\nWARNING: You are about to use the LlamaCloud Extract API.\nProceed? (y/n): ")
        if confirmation.strip().lower() not in ["y", "yes"]:
            print("Extraction cancelled by user.")
            return

    # Initialize async client only if needed
    client = None
    if total_chunks > 0:
        client = initialize_async_client()
        if not client:
            return

    # Run the main extraction loop asynchronously
    async def run_extractions():
        success_count = 0
        for item in pending:
            task = item["task"]
            year = item["year"]
            pdf_path = item["pdf_path"]
            
            if not year:
                print(f"Skipping task for {pdf_path}: missing 'year' key.")
                continue

            extraction_config = load_extraction_config(task, year)
            if not extraction_config:
                continue

            if "tier" not in extraction_config:
                extraction_config["tier"] = DEFAULT_EXTRACT_TIER

            print(f"\nProcessing {pdf_path} (year {year}, tier {extraction_config['tier']})...")
            try:
                await process_extraction(
                    async_client=client, 
                    chunks=item["chunks"], 
                    output_path=item["output_path"], 
                    extraction_config=extraction_config, 
                    year=year,
                    expected_vars=item["expected_vars"],
                    existing_variables=item["existing_variables"]
                )
                success_count += 1
            except Exception as e:
                print(f"  Error processing {pdf_path}: {e}")
        
        print(f"\nDone. Processed {success_count}/{len(pending)} files.")

    asyncio.run(run_extractions())


if __name__ == "__main__":
    main()
