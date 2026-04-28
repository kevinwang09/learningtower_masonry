import argparse
import csv
import json
import sys

def validate_curation(json_path, csv_path, year):
    print(f"Validating {csv_path} against {json_path} for year {year}...")
    
    with open(json_path, 'r') as f:
        extracted_data = json.load(f)
        
    with open(csv_path, 'r') as f:
        # Skip comment lines
        lines = (line for line in f if not line.startswith('#'))
        reader = csv.DictReader(lines)
        csv_data = [row for row in reader if str(row['year']) == str(year)]
        
    if not csv_data:
        print(f"No entries found in CSV for year {year}.")
        return

    # Create a mapping of uppercase variable keys to their entries for case-insensitive matching
    extracted_vars = {
        entry.get('variable_key', '').strip().upper(): entry 
        for entry in extracted_data.get('codebook_entries', [])
    }
    
    issues = []
    csv_vars = set()
    
    print("\n--- Variable and NA Value Check ---")
    for row in csv_data:
        target_name = row.get('target_name', 'Unknown')
        source_cols_str = row.get('source_col', '').strip()
        na_values_str = row.get('na_values', '').strip()
        
        if not source_cols_str:
            continue
            
        # source_col can contain multiple variables separated by spaces
        source_cols = source_cols_str.split()
        expected_na_values = set(na_values_str.split(';')) if na_values_str else set()
        
        for col in source_cols:
            col_upper = col.upper()
            csv_vars.add(col_upper)
            
            # 1. Check if raw variable exists
            if col_upper not in extracted_vars:
                issues.append(f"Variable '{col}' (target: {target_name}) not found in the extracted codebook.")
                continue
                
            entry = extracted_vars[col_upper]
            
            # 2. Check if NA values are coded correctly
            if expected_na_values:
                var_values = entry.get('variable_key_value')
                
                if var_values is None:
                    # Some continuous variables might not have a value map, but if CSV expects NA values, it's worth noting
                    issues.append(f"Variable '{col}' (target: {target_name}) expects NA values {expected_na_values} but has no value mapping in codebook.")
                    continue
                
                # Extract all keys present in the codebook for this variable
                codebook_keys = set(str(v.get('key')).strip() for v in var_values if 'key' in v)
                
                missing_nas = expected_na_values - codebook_keys
                if missing_nas:
                    issues.append(f"Variable '{col}' (target: {target_name}) is missing expected NA keys in codebook: {missing_nas}. Found keys: {codebook_keys}")
                else:
                    print(f" [OK] {col} (target: {target_name}) -> NA values matched successfully: {expected_na_values}")
            else:
                print(f" [OK] {col} (target: {target_name}) -> Exists in codebook (No NA checking required)")
                
    json_only_vars = set(extracted_vars.keys()) - csv_vars
    if json_only_vars:
        print("\n--- Variables found in JSON but NOT in CSV ---")
        for v in sorted(json_only_vars):
            entry = extracted_vars[v]
            description = entry.get('variable_description', 'No description provided')
            print(f"- {v}: {description}")

    if issues:
        print("\n--- Validation Failed ---")
        for issue in issues:
            print(f"- {issue}")
        sys.exit(1)
    else:
        print("\n--- Validation Passed! ---")
        print("All variables exist and NA values match.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate curation CSV against extracted JSON codebook.")
    parser.add_argument("--json", required=True, help="Path to the extracted JSON file (e.g., 2000school_extracted.json)")
    parser.add_argument("--csv", required=True, help="Path to the curation CSV file (e.g., PISA_variable_curation_school.csv)")
    parser.add_argument("--year", required=True, type=int, help="The year to filter in the CSV")
    
    args = parser.parse_args()
    validate_curation(args.json, args.csv, args.year)
