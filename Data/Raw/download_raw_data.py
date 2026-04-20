import os
import time
import requests
import hashlib
import threading
import re
import json
import argparse
import logging
from datetime import datetime
from bs4 import BeautifulSoup
from urllib.parse import urlparse, unquote
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

working_dir = Path(__file__).resolve().parent
HTML_FILE = working_dir / 'PISA Data Files.html'
OUTPUT_DIR = working_dir
MANIFEST_FILE = working_dir / 'data_manifest.json'
DELAY = 2                           # Seconds to sleep between downloads (politeness)

# Special cases where dataset links are inconsistently formatted in the HTML source
HARDCODED_EXCEPTIONS = {
    '2000': [
        'https://www.oecd.org/content/dam/oecd/en/data/datasets/pisa/pisa-2000-datasets/PISA2000_ESCS.zip'
    ]
}

tqdm.set_lock(threading.RLock())
manifest_lock = threading.Lock()

def load_manifest():
    if MANIFEST_FILE.exists():
        with open(MANIFEST_FILE, 'r', encoding='utf-8') as f:
            try:
                return json.load(f)
            except json.JSONDecodeError:
                return {}
    return {}

def update_manifest_md5(key, md5sum, year_name, filename, url=None):
    with manifest_lock:
        manifest = load_manifest()
        if key not in manifest:
            manifest[key] = {}
        manifest[key]['year'] = year_name
        manifest[key]['filename'] = filename
        manifest[key]['md5sum'] = md5sum
        if url is not None:
            manifest[key]['url'] = url
        if 'extracted_files' not in manifest[key]:
            manifest[key]['extracted_files'] = []
        with open(MANIFEST_FILE, 'w', encoding='utf-8') as f:
            json.dump(manifest, f, indent=4)

def compute_md5(file_path):
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 64), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()

def save_file(url, folder, year_name, position=0, dry_run=False):
    """
    Downloads a file with a progress bar and resume capability, and computes MD5.
    If dry_run is True, creates a fake file instead of downloading.
    """
    try:
        # Extract filename
        parsed_url = urlparse(url)
        filename = unquote(os.path.basename(parsed_url.path))
        
        # Filter: Skip invalid filenames
        if not filename or filename.lower().endswith(('.html', '.htm', '.php')):
            return
            
        file_path = os.path.join(folder, filename)
        md5_path = file_path + '.md5'
        manifest_key = f"{year_name}/{filename}"

        # Check manifest before doing anything
        with manifest_lock:
            manifest = load_manifest()
        
        expected_md5 = manifest.get(manifest_key, {}).get("md5sum")
        
        # Fallback to local .md5 file if manifest is empty or missing this entry
        if not expected_md5 and os.path.exists(md5_path):
            with open(md5_path, 'r') as f:
                saved_md5 = f.read().strip()
                if saved_md5:
                    expected_md5 = saved_md5
        
        if expected_md5 and os.path.exists(file_path):
            current_md5 = compute_md5(file_path)
            if current_md5 != expected_md5:
                if not dry_run:
                    raise ValueError(f"Data integrity error: MD5 mismatch for {file_path}. Expected {expected_md5}, got {current_md5}")
            else:
                # File already downloaded and matches MD5. 
                # Ensure the manifest is updated since it might have used the .md5 fallback
                if not dry_run:
                    update_manifest_md5(manifest_key, current_md5, year_name, filename, url)
                logging.info(f"Skipping {file_path}: already exists and MD5 matches.")
                return
                
        if dry_run:
            with open(file_path, 'wb') as f:
                f.write(b"dry_run_fake_content\n")
            md5_hash = compute_md5(file_path)
            with open(md5_path, 'w') as f:
                f.write(md5_hash)
            return

        # 1. Get Remote File Info (Size) without downloading yet
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}
        try:
            head_response = requests.get(url, headers=headers, stream=True)
            total_size = int(head_response.headers.get('content-length', 0))
            head_response.close()
        except Exception:
            total_size = 0

        # 2. Check Local File for Resume capability
        resume_byte_pos = 0
        file_mode = 'wb'  # Default: Write new

        if os.path.exists(file_path):
            local_size = os.path.getsize(file_path)
            
            if total_size > 0 and local_size == total_size:
                # Already complete
                md5_hash = compute_md5(file_path)
                if not os.path.exists(md5_path):
                    with open(md5_path, 'w') as f:
                        f.write(md5_hash)
                update_manifest_md5(manifest_key, md5_hash, year_name, filename, url)
                logging.info(f"Skipping {file_path}: already exists and local file size matches remote size.")
                return
            elif total_size > 0 and local_size < total_size:
                resume_byte_pos = local_size
                headers['Range'] = f'bytes={local_size}-'
                file_mode = 'ab'  # Append mode
            else:
                pass

        # 3. Start Download
        response = requests.get(url, headers=headers, stream=True)
        
        if response.status_code == 403:
            raise Exception("403 Forbidden! The server blocked this download (likely Cloudflare protection - you may need to manually download this file).")
        elif response.status_code == 404:
            raise Exception("404 Not Found! The URL appears to be dead.")
            
        # Note: If server rejects resume (sends 200 instead of 206), we must restart
        if response.status_code == 200 and resume_byte_pos > 0:
            resume_byte_pos = 0
            file_mode = 'wb'

        # 4. Write File with Progress Bar
        block_size = 1024 * 8 # 8KB chunks
        
        with open(file_path, file_mode) as f, tqdm(
            desc=filename,
            total=total_size,
            unit='iB',
            unit_scale=True,
            unit_divisor=1024,
            initial=resume_byte_pos,
            ascii=False,
            ncols=100,
            position=position,
            leave=False
        ) as bar:
            for chunk in response.iter_content(chunk_size=block_size):
                if chunk:
                    size = f.write(chunk)
                    bar.update(size)
        
        # Compute and save MD5
        md5_hash = compute_md5(file_path)
        with open(md5_path, 'w') as f:
            f.write(md5_hash)
            
        update_manifest_md5(manifest_key, md5_hash, year_name, filename, url)
            
        # Be polite to the server
        time.sleep(DELAY)

    except Exception as e:
        logging.error(f"Failed to download {url}: {e}")

def main():
    parser = argparse.ArgumentParser(description="Download PISA Data Files")
    parser.add_argument('--dry-run', action='store_true', help="Populate folders with mock files without downloading")
    parser.add_argument('--years', type=str, default="", help="Comma separated list of years to download (e.g. '2000,2003')")
    args = parser.parse_args()
    
    # Setup Timestamped Logging
    log_filename = working_dir / f"download_raw_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_filename),
            logging.StreamHandler()
        ]
    )
    logging.info(f"Started download_raw_data script. Logging to {log_filename.name}")
    
    target_years = [y.strip() for y in args.years.split(',')] if args.years else None

    # 1. Read the HTML file
    if not os.path.exists(HTML_FILE):
        logging.error(f"Could not find {HTML_FILE}. Please save the HTML content to this file.")
        return

    with open(HTML_FILE, 'r', encoding='utf-8') as f:
        soup = BeautifulSoup(f, 'html.parser')

    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    # 2. Find all PISA Year Sections
    sections = soup.find_all('section')
    tasks = []

    for section in sections:
        header = section.find('h2')
        if not header:
            continue
            
        header_text = header.get_text(strip=True)
        year_match = re.search(r'\d{4}', header_text)
        year_name = year_match.group(0) if year_match else header_text.replace(' ', '_')
        
        if target_years and year_name not in target_years:
            continue
            
        year_folder = os.path.join(OUTPUT_DIR, year_name)
        
        # 3. Apply modular hardcoded exceptions for inconsistently mapped years
        if year_name in HARDCODED_EXCEPTIONS:
            logging.info(f"Applying hardcoded dataset link exceptions for year {year_name}...")
            if not os.path.exists(year_folder):
                os.makedirs(year_folder)
            for url in HARDCODED_EXCEPTIONS[year_name]:
                url_task = (url, year_folder, year_name)
                if url_task not in tasks:
                    tasks.append(url_task)
                    
        # 4. Find SPSS specific blocks and TXT specific blocks (for older years)
        spss_headers = section.find_all('h3', string=lambda text: text and ('SPSS' in text or 'Data sets in TXT format' in text))
        
        if not spss_headers:
            continue
        
        if not os.path.exists(year_folder):
            os.makedirs(year_folder)

        for h3 in spss_headers:
            parent_div = h3.find_parent('div')
            if parent_div:
                links = parent_div.find_all('a', href=True)
                for link in links:
                    url = link['href']
                    if not url.startswith('http'):
                        url = 'https://webfs.oecd.org/pisa2022/' + url 
                    
                    if url.endswith('.zip'):
                        tasks.append((url, year_folder, year_name))
    
    if not tasks:
        logging.info("No files to download.")
        return

    logging.info(f"Starting download of {len(tasks)} files with up to 3 parallel workers...")
    
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = []
        for i, (url, folder, year_name) in enumerate(tasks):
            # i % 3 keeps progress bars in roughly 3 slots
            futures.append(executor.submit(save_file, url, folder, year_name, i % 3, args.dry_run))
            
        for future in as_completed(futures):
            future.result()

    logging.info("All downloads completed.")

if __name__ == "__main__":
    main()