import argparse
import csv
import json
import sys
import os
import yaml
import jsonschema

def validate_curation(json_path, csv_path, year, json_schema=None, log_file=None):
    issues = []
    warnings = []
    
    original_stdout = sys.stdout
    if log_file:
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        f_log = open(log_file, 'w')
        sys.stdout = f_log
        
    try:
        print(f"Validating {csv_path} against {json_path} for year {year}...")
        
        if not os.path.exists(json_path):
            print(f"JSON file not found: {json_path}")
            return False
            
        with open(json_path, 'r') as f:
            extracted_data = json.load(f)

        # Schema Validation
        if json_schema:
            try:
                jsonschema.validate(instance=extracted_data, schema=json_schema)
                print(" [OK] JSON schema validation passed.")
            except jsonschema.exceptions.ValidationError as e:
                print(f" [FAIL] JSON schema validation failed: {e.message}")
                issues.append(f"JSON schema validation failed: {e.message}")
                return False
            except Exception as e:
                print(f" [ERROR] Unexpected error during schema validation: {e}")
                return False
            
        if not os.path.exists(csv_path):
            print(f"CSV file not found: {csv_path}")
            return False
            
        with open(csv_path, 'r') as f:
            lines = (line for line in f if not line.startswith('#'))
            reader = csv.DictReader(lines)
            csv_data = [row for row in reader if str(row['year']) == str(year)]
            
        if not csv_data:
            print(f"No entries found in CSV for year {year}.")
            return False

        # Support both output formats:
        #   Canonical: root key "codebook_entries" (matching llamaconfig.json)
        #   Legacy:    root key "Variables" (from earlier batch pipeline runs)
        entries = extracted_data.get('codebook_entries', extracted_data.get('Variables', []))
        extracted_vars = {}
        for entry in entries:
            var_name = entry.get('variable_key', entry.get('Variable', '')).strip().upper()
            if var_name:
                extracted_vars[var_name] = entry
        
        csv_vars = set()
        
        print("\n--- Variable and NA Value Check ---")
        for row in csv_data:
            target_name = row.get('target_name', 'Unknown')
            source_cols_str = row.get('source_col', '').strip()
            na_values_str = row.get('na_values', '').strip()
            note = row.get('note', '').strip()
            
            if not source_cols_str:
                continue
                
            source_cols = source_cols_str.split()
            expected_na_values = set(na_values_str.split(';')) if na_values_str else set()
            
            for col in source_cols:
                col_upper = col.upper()
                csv_vars.add(col_upper)
                
                if col_upper not in extracted_vars:
                    msg = f"Variable '{col}' (target: {target_name}) not found in the extracted codebook. Note: {note}"
                    if note:
                        warnings.append(msg)
                    else:
                        issues.append(msg)
                    continue
                    
                entry = extracted_vars[col_upper]
                
                if expected_na_values:
                    var_values = entry.get('variable_key_value', entry.get('Values'))
                    
                    if var_values is None:
                        msg = f"Variable '{col}' (target: {target_name}) expects NA values {{{', '.join(repr(x) for x in sorted(expected_na_values))}}} but has no value mapping in codebook. Note: {note}"
                        if note:
                            warnings.append(msg)
                        else:
                            issues.append(msg)
                        continue
                    
                    codebook_keys = set(str(v.get('key')).strip() for v in var_values if 'key' in v)
                    
                    missing_nas = expected_na_values - codebook_keys
                    if missing_nas:
                        msg = f"Variable '{col}' (target: {target_name}) is missing expected NA keys in codebook: {{{', '.join(repr(x) for x in sorted(missing_nas))}}}. Found keys: {{{', '.join(repr(x) for x in sorted(codebook_keys))}}}. Note: {note}"
                        if note:
                            warnings.append(msg)
                        else:
                            issues.append(msg)
                    else:
                        print(f" [OK] {col} (target: {target_name}) -> NA values matched successfully: {{{', '.join(repr(x) for x in sorted(expected_na_values))}}}")
                else:
                    print(f" [OK] {col} (target: {target_name}) -> Exists in codebook (No NA checking required)")
                    
        json_only_vars = set(extracted_vars.keys()) - csv_vars
        if json_only_vars:
            print(f"\n--- Variables found in JSON but NOT in CSV ---")
            print(f"Total variables in this category: {len(json_only_vars)}")

        if warnings:
            print("\n--- Validation Warnings ---")
            for warning in warnings:
                print(f"- [WARNING] {warning}")

        if issues:
            print("\n--- Validation Failed ---")
            for issue in issues:
                print(f"- [FAIL] {issue}")
            return False
        else:
            print("\n--- Validation Passed! ---")
            print("All variables exist and NA values match.")
            return True
            
    finally:
        if log_file:
            sys.stdout = original_stdout
            f_log.close()


def main():
    parser = argparse.ArgumentParser(description="Validate curation CSV against extracted JSON codebook.")
    parser.add_argument("--tasks", default="extraction_tasks.yaml", help="Path to the tasks YAML file")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.tasks):
        print(f"Tasks file not found: {args.tasks}")
        sys.exit(1)
        
    with open(args.tasks, 'r') as f:
        manifest = yaml.safe_load(f)
        
    tasks = manifest.get('tasks', [])
    if not tasks and 'year' in manifest:
        tasks = [manifest]
        
    passed_tasks = []
    failed_tasks = []
    base_dir = os.path.dirname(os.path.abspath(__file__))
    logs_dir = os.path.join(base_dir, "logs")
    
    for task in tasks:
        year = task.get("year")
        if not year:
            continue
            
        for file_type in ["school", "student"]:
            file_entry = task.get(f"{file_type}_file")
            if not file_entry:
                continue
                
            # Determine the filename and schema based on type
            file_name = None
            if isinstance(file_entry, str):
                file_name = file_entry
            elif isinstance(file_entry, dict):
                file_name = file_entry.get("file")
                
            if not file_name:
                continue
                
            if file_name.lower().endswith(".pdf"):
                json_name = file_name.replace(".pdf", "_extracted.json")
                schema_name = "extracted_pdf_schema.json"
            elif file_name.lower().endswith((".csv", ".xlsx", ".xls")):
                json_name = f"{year}{file_type}_extracted.json"
                schema_name = "tabular_schema.json"
            else:
                continue
                
            json_path = os.path.join(base_dir, json_name)
            
            csv_name = f"PISA_variable_curation_{file_type}.csv"
            csv_path = os.path.join(base_dir, "..", "variable_curation", csv_name)
            
            log_name = f"validate_{year}_{file_type}.log"
            log_path = os.path.join(logs_dir, log_name)
            
            print(f"Processing {file_type} for year {year}... Check {log_path} for details.")

            # Load the unified validation schema
            schema_file = os.path.join(base_dir, schema_name)
            json_schema = None
            if os.path.exists(schema_file):
                with open(schema_file, 'r') as sf:
                    json_schema = json.load(sf)

            passed = validate_curation(json_path, csv_path, year, json_schema=json_schema, log_file=log_path)
            task_name = f"{year} {file_type}"
            if not passed:
                failed_tasks.append(task_name)
                print(f" -> Validation FAILED for {task_name}.")
            else:
                passed_tasks.append(task_name)
                print(f" -> Validation PASSED for {task_name}.")
                
    print("\n" + "="*50)
    print("VALIDATION SUMMARY")
    print("="*50)
    print(f"Total Passed: {len(passed_tasks)}")
    if passed_tasks:
        print(f"Passed Tasks: {', '.join(passed_tasks)}")
        
    print(f"\nTotal Failed: {len(failed_tasks)}")
    if failed_tasks:
        print(f"Failed Tasks: {', '.join(failed_tasks)}")
    print("="*50 + "\n")
                
    if failed_tasks:
        sys.exit(1)

if __name__ == "__main__":
    main()
