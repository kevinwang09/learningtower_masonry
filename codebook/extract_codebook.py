import os
import sys
import argparse
import subprocess
import tempfile
import yaml
from llama_utils import load_tasks_manifest
import extract_pdf_codebook
import extract_tabular_codebook

def split_tasks(manifest):
    """
    Splits the given task manifest into a PDF-only manifest and a Tabular-only manifest.
    This guarantees that the underlying specialized scripts only receive tasks they can handle.
    """
    pdf_tasks = []
    tab_tasks = []
    
    for task in manifest:
        pdf_task = task.copy()
        tab_task = task.copy()
        
        has_pdf = False
        has_tab = False
        
        for key in ["school_file", "student_file"]:
            if key in task:
                val = task[key]
                is_pdf = False
                is_tab = False
                if isinstance(val, str):
                    if val.lower().endswith(".pdf"): is_pdf = True
                    elif val.lower().endswith((".csv", ".xlsx", ".xls")): is_tab = True
                elif isinstance(val, dict):
                    f = val.get("file", "")
                    if f.lower().endswith(".pdf"): is_pdf = True
                    elif f.lower().endswith((".csv", ".xlsx", ".xls")): is_tab = True
                    
                if is_pdf:
                    tab_task.pop(key, None)
                    has_pdf = True
                elif is_tab:
                    pdf_task.pop(key, None)
                    has_tab = True
                else:
                    tab_task.pop(key, None)
                    pdf_task.pop(key, None)
                    
        # Handle "files" key fallback
        if "files" in task:
            pdf_files = []
            tab_files = []
            for f in task["files"]:
                if isinstance(f, str):
                    if f.lower().endswith(".pdf"):
                        pdf_files.append(f)
                        has_pdf = True
                    elif f.lower().endswith((".csv", ".xlsx", ".xls")):
                        tab_files.append(f)
                        has_tab = True
            if pdf_files:
                pdf_task["files"] = pdf_files
            else:
                pdf_task.pop("files", None)
                
            if tab_files:
                tab_task["files"] = tab_files
            else:
                tab_task.pop("files", None)
                
        if has_pdf:
            pdf_tasks.append(pdf_task)
        if has_tab:
            tab_tasks.append(tab_task)
            
    return pdf_tasks, tab_tasks

def main():
    parser = argparse.ArgumentParser(description="Wrapper to route extraction to PDF or Tabular processors.", add_help=False)
    parser.add_argument("--tasks", required=True, help="Path to extraction tasks YAML.")
    # Allow passing through arguments like --all-pages or --skip-confirmation
    args, unknown = parser.parse_known_args()
    
    manifest = load_tasks_manifest(args.tasks)
    pdf_tasks, tab_tasks = split_tasks(manifest)
    
    base_dir = os.path.dirname(os.path.abspath(args.tasks))
    
    if pdf_tasks:
        print(f"Routing {len(pdf_tasks)} PDF-based tasks to extract_pdf_codebook...")
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', dir=base_dir, delete=False) as f:
            yaml.dump({"tasks": pdf_tasks}, f)
            temp_pdf_tasks = f.name
            
        try:
            old_argv = sys.argv.copy()
            sys.argv = [sys.argv[0], "--tasks", temp_pdf_tasks] + unknown
            extract_pdf_codebook.main()
        except Exception as e:
            print(f"extract_pdf_codebook failed: {e}")
        finally:
            sys.argv = old_argv
            if os.path.exists(temp_pdf_tasks):
                os.remove(temp_pdf_tasks)
                
    if tab_tasks:
        print(f"\nRouting {len(tab_tasks)} tabular-based tasks to extract_tabular_codebook...")
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', dir=base_dir, delete=False) as f:
            yaml.dump({"tasks": tab_tasks}, f)
            temp_tab_tasks = f.name
            
        try:
            old_argv = sys.argv.copy()
            # extract_tabular_codebook.py only expects --tasks, so we don't pass unknown args
            sys.argv = [sys.argv[0], "--tasks", temp_tab_tasks]
            extract_tabular_codebook.main()
        except Exception as e:
            print(f"extract_tabular_codebook failed: {e}")
        finally:
            sys.argv = old_argv
            if os.path.exists(temp_tab_tasks):
                os.remove(temp_tab_tasks)
                
    if not pdf_tasks and not tab_tasks:
        print("No recognized file formats (.pdf, .csv, .xlsx, .xls) found in tasks manifest.")

if __name__ == "__main__":
    main()
