# Raw Data Directory

This directory manages the initial acquisition, verification, and extraction of the raw PISA datasets. It contains the Python scripts and tracking mechanisms necessary to ensure data integrity across multiple download sessions and extraction phases.

## Workflow Overview

The general process for acquiring and preparing raw data is:

1. **Source Tracking:** Ensure `PISA Data Files.html` is present. This file contains the source links for the datasets.
2. **Downloading:** Execute `download_raw_data.py` to download the specific dataset `.zip` archives.
3. **Extraction:** Execute `prepare_raw_data.py` to seamlessly extract the `.zip` files directly within their respective year folders (e.g., extracting `2000/data.zip` into `2000/`).

## Special Considerations: 2012 Data

It is important to note that the datasets for the year **2012** (found under the section "Data sets in TXT format" on the OECD website, which contains all the necessary `.zip` files) are protected by CloudFlare. Because of this security measure, they cannot be successfully retrieved via the automated download script and **must be manually downloaded** by developers into the `Data/Raw/2012/` directory.

## Key Files and Scripts

### `PISA Data Files.html`

This is the source HTML file containing the official links for downloading the PISA datasets from the OECD webfs. The downloading script parses this file to extract SPSS dataset URLs for each PISA year.

### `download_raw_data.py`

This script processes the HTML source file and downloads the dataset ZIP archives directly from the OECD servers.

- **Year-Based Folders:** It parses the year (e.g., `2000`, `2022`) from the HTML sections and automatically categorizes downloads into year-specific folders.
- **Data Integrity:** It uses a JSON manifest (`data_manifest.json`) to track downloaded files. It computes the MD5 checksum of each file.
- **Idempotency and Resumes:** If the script is run multiple times, it will skip files that have already been downloaded and whose MD5 checksum perfectly matches the recording in the manifest. If a checksum mismatch occurs on an existing file, a `ValueError` is aggressively raised to alert developers of corruption.
- **Hardcoded Exceptions:** The script contains a modular `HARDCODED_EXCEPTIONS` dictionary to safely manage specific datasets that are inconsistently linked in the OECD HTML (such as the year 2000 ESCS dataset), routing them safely into their respective year folders.

**Command Line Usage:**

- `python download_raw_data.py --years "2000,2003"`: Only downloads datasets for the explicitly listed (comma-separated) years. By default, it runs all years if omitted.
- `python download_raw_data.py --dry-run`: Skips actual network downloading. Instead, it generates empty mock files filled with placeholder content and computes local MD5 hashes for testing, but **actively prevents any updates to `data_manifest.json`** to ensure the production registry remains clean. Useful for rapid structural testing.

### `prepare_raw_data.py`

This script extracts the downloaded `.zip` files directly in place within their respective year folders (e.g., `2000/`).

- **Structure Preservation:** It preserves the year-based folder structure during extraction.
- **Manifest Updates:** It leverages the same `data_manifest.json` file. Upon successfully unzipping a file, it catalogs the internal `namelist` of the archive and registers the extracted files within the manifest.
- **Tree Generation:** It automatically generates a lightweight `extracted_files_tree.json` file summarizing the resulting local folder structure and file sizes of the unzipped data in a structured JSON format.

### `data_manifest.json`

A system-generated central registry maintained and utilized by both scripts. It acts as the ultimate source of truth for the raw folder state. It records:

- The year of the data
- The absolute filename
- The computed MD5 checksum of the remote file
- The exact list of extracted files contained within the ZIP archive (after extraction)

## Folder Structure

```text
Data/Raw/
├── README.md                  # This file
├── PISA Data Files.html       # Source HTML with download links
├── download_raw_data.py       # Script to download data and verify integrity
├── prepare_raw_data.py        # Script to extract ZIP archives
├── data_manifest.json         # Manifest tracking downloads and extracted files
├── extracted_files_tree.json  # JSON summary of extracted file sizes and tree
└── <Year>/                    # e.g., 2000/, 2022/ - Raw ZIP archives downloaded and extracted here
```
