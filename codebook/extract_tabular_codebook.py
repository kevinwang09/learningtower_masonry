import os
import json
import argparse
import pandas as pd
import jsonschema

from llama_utils import (
    load_tasks_manifest,
    load_output_schema,
    normalize_variable_entry
)

def process_tabular_codebook(file_path, sheet_name, year, cookbook_type):
    na_indicators = ["valid skip", "not applicable", "invalid", "no response", "missing", "not reached"]
    print(f"Processing {file_path} (sheet: {sheet_name})...")
    
    schema = None
    schema_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tabular_schema.json")
    if os.path.exists(schema_path):
        with open(schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)
    
    try:
        if file_path.lower().endswith('.csv'):
            df = pd.read_csv(file_path)
        elif file_path.lower().endswith(('.xlsx', '.xls')):
            df = pd.read_excel(file_path, sheet_name=sheet_name)
        else:
            print(f"Unsupported file format: {file_path}")
            return
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return
        
    # Data Cleaning: Normalize headers (strip "NEW", strip whitespace, uppercase)
    df.columns = [str(col).upper().replace('NEW', '').strip() for col in df.columns]
    
    # Check for required columns
    required_cols = ['NAME', 'VARLABEL', 'FORMAT', 'VAL', 'LABEL']
    missing_cols = [col for col in required_cols if col not in df.columns]
    if missing_cols:
        print(f"Skipping {file_path} due to missing columns: {missing_cols}")
        return
        
    # Flattening: forward-fill the parent context
    df[['NAME', 'VARLABEL', 'FORMAT']] = df[['NAME', 'VARLABEL', 'FORMAT']].ffill()
    
    codebook_entries = []
    
    # Grouping & Mapping
    grouped = df.groupby('NAME', sort=False)
    
    for name, group in grouped:
        first_row = group.iloc[0]
        
        # Filter out NaN VAL rows
        valid_vals = group.dropna(subset=['VAL'])
        
        val_mappings = []
        na_values = []
        
        for _, row in valid_vals.iterrows():
            val_str = str(row['VAL']).strip() if pd.notna(row['VAL']) else ""
            label_str = str(row['LABEL']).strip() if pd.notna(row['LABEL']) else ""
            label_lower = label_str.lower()
            
            # Check if this label represents missing data
            if any(indicator in label_lower for indicator in na_indicators) or val_str == "SYSTEM MISSING":
                # Extract just the numeric code before the slash (e.g., "97 / .N" -> "97")
                clean_na_code = val_str.split('/')[0].strip()
                if clean_na_code:
                    na_values.append(clean_na_code)
            else:
                if val_str:
                    val_mappings.append({"key": val_str, "value": label_str})

        # Clean up empty lists to null for schema compliance
        if not val_mappings:
            val_mappings = None
            
        # Source tracking: Original row number (0-indexed name + 2 for header)
        source_page = int(first_row.name) + 2
        
        raw_entry = {
            "variable_key": str(name).strip(),
            "variable_description": str(first_row['VARLABEL']).strip() if pd.notna(first_row['VARLABEL']) else "",
            "format_specifier": str(first_row['FORMAT']).strip() if pd.notna(first_row['FORMAT']) else "",
            "fixed_width_specification": "",
            "variable_key_value": val_mappings,
            "na_values": na_values,
            "source_page": str(source_page)
        }
        
        # Pipeline Integration
        normalized_entry = normalize_variable_entry(raw_entry)
        normalized_entry["Year"] = int(year)
        codebook_entries.append(normalized_entry)
        
    output_dict = {
        "Year": int(year),
        "cookbook_type": cookbook_type,
        "codebook_entries": codebook_entries
    }
    
    if schema:
        try:
            jsonschema.validate(instance=output_dict, schema=schema)
            print(f"  Schema validation passed for {file_path}.")
        except jsonschema.exceptions.ValidationError as e:
            print(f"  WARNING: Validation failed for {file_path}: {e.message}")
            
    # Output to [year][type]_extracted.json to avoid overwriting files from the same Excel
    output_dir = os.path.dirname(file_path)
    output_name = f"{year}{cookbook_type}_extracted.json"
    output_path = os.path.join(output_dir, output_name)
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output_dict, f, indent=2)
        
    print(f"Successfully processed {file_path} -> {output_path}")

def main():
    parser = argparse.ArgumentParser(description="Extract tabular codebooks (2015+ CSVs/XLSXs).")
    parser.add_argument("--tasks", required=True, help="Path to extraction tasks YAML.")
    args = parser.parse_args()
    
    manifest = load_tasks_manifest(args.tasks)
    
    base_dir = os.path.dirname(os.path.abspath(args.tasks))
    
    # Orchestration
    processed = 0
    for task in manifest:
        year = task.get("year")
        if not year:
            continue
            
        for cb_type in ['school', 'student']:
            file_key = f"{cb_type}_file"
            file_entry = task.get(file_key)
            
            if not file_entry:
                continue
                
            file_name = None
            sheet_name = None
            
            if isinstance(file_entry, dict):
                file_name = file_entry.get("file")
                sheet_name = file_entry.get("sheet")
            elif isinstance(file_entry, str):
                file_name = file_entry
                
            if file_name and file_name.lower().endswith(('.csv', '.xlsx', '.xls')):
                file_path = os.path.join(base_dir, file_name)
                if os.path.exists(file_path):
                    process_tabular_codebook(file_path, sheet_name, year, cb_type)
                    processed += 1
                else:
                    print(f"File not found: {file_path}")
                    
    if processed == 0:
        print("No tabular codebooks found in tasks.")

if __name__ == "__main__":
    main()
