import os
import zipfile
import json
import logging
import hashlib
from datetime import datetime
from pathlib import Path

def calculate_md5(file_path, chunk_size=8192):
    md5 = hashlib.md5()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(chunk_size), b''):
            md5.update(chunk)
    return md5.hexdigest()

def load_manifest(manifest_path):
    if manifest_path.exists():
        with open(manifest_path, 'r', encoding='utf-8') as f:
            try:
                return json.load(f)
            except json.JSONDecodeError:
                return {}
    return {}

def save_manifest(manifest, manifest_path):
    with open(manifest_path, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=4)

def extract_zip_files(input_dir, manifest_path):
    """
    Finds all .zip files in the input_dir and extracts them in place
    into their respective year folders.
    """
    input_path = Path(input_dir)

    if not input_path.exists():
        logging.error(f"Input directory '{input_dir}' does not exist.")
        return

    # Find all zip files inside the year directories
    zip_files = [
        p for p in input_path.rglob('*.zip') 
        if len(p.relative_to(input_path).parts) > 1
    ]
    
    if not zip_files:
        logging.warning(f"No .zip files found in '{input_dir}'.")
        return

    logging.info(f"Found {len(zip_files)} .zip files. Starting extraction...")
    
    manifest = load_manifest(manifest_path)

    for zip_file in zip_files:
        # Determine the year folder (the immediate child of input_dir)
        try:
            relative_path = zip_file.relative_to(input_path)
            # The first part of the relative path is the year folder (e.g., 2022)
            year_folder = relative_path.parts[0]
        except ValueError:
            # Fallback if somehow not strictly inside year folder
            year_folder = "Unknown_Year"

        # The target directory is the same directory the zip file is in
        target_dir = zip_file.parent

        logging.info(f"Extracting {zip_file.name} to {target_dir}...")
        try:
            with zipfile.ZipFile(zip_file, 'r') as zf:
                zf.extractall(path=target_dir)
                extracted_files = zf.namelist()
                
            # Update manifest with extracted files
            manifest_key = f"{year_folder}/{zip_file.name}"
            if manifest_key not in manifest:
                manifest[manifest_key] = {
                    'year': year_folder,
                    'filename': zip_file.name,
                    'md5sum': None
                }
            manifest[manifest_key]['extracted_files'] = extracted_files
            
            # Always compute and update md5sum when processed
            logging.info(f"Computing md5sum for {zip_file.name}...")
            manifest[manifest_key]['md5sum'] = calculate_md5(zip_file)
            
        except zipfile.BadZipFile:
            logging.error(f"Bad zip file: {zip_file}")
        except Exception as e:
            logging.error(f"Failed to extract {zip_file}: {e}")

    # Save manifest after extraction loop
    save_manifest(manifest, manifest_path)
    logging.info("Extraction complete.")

def generate_file_tree_dict(dir_path):
    tree = {
        "type": "directory",
        "name": dir_path.name,
        "children": []
    }
    
    try:
        entries = sorted(os.listdir(dir_path))
    except PermissionError:
        return tree
    
    for entry in entries:
        if entry == '.DS_Store' or entry.endswith('.log'):
            continue
            
        full_path = dir_path / entry
        if full_path.is_dir():
            tree["children"].append(generate_file_tree_dict(full_path))
        else:
            size_mb = full_path.stat().st_size / (1024 * 1024)
            tree["children"].append({
                "type": "file",
                "name": entry,
                "size_mb": round(size_mb, 2)
            })
    return tree

def generate_file_tree(directory, output_file):
    """
    Creates a JSON file containing the tree structure of the directory,
    including file sizes.
    """
    dir_path = Path(directory)
    if not dir_path.exists():
        logging.warning(f"Directory '{directory}' does not exist. Cannot generate tree.")
        return

    logging.info(f"Generating file tree for '{directory}' into '{output_file}'...")
    
    tree_data = generate_file_tree_dict(dir_path)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(tree_data, f, indent=4)
                
    logging.info("File tree generated.")

def main():
    # Resolve paths relative to this script's location
    script_dir = Path(__file__).parent.resolve()
    
    # Setup Timestamped Logging
    log_filename = script_dir / f"prepare_raw_data_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(log_filename),
            logging.StreamHandler()
        ]
    )
    logging.info(f"Started prepare_raw_data script. Logging to {log_filename.name}")
    
    input_dir = script_dir
    tree_file = script_dir / 'extracted_files_tree.json'
    manifest_path = script_dir / 'data_manifest.json'

    # Step 1: Extract
    extract_zip_files(input_dir, manifest_path)
    logging.info("-" * 30)
    # Step 2: Generate Tree
    generate_file_tree(input_dir, tree_file)

if __name__ == "__main__":
    main()
