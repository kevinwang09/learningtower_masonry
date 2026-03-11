# PISA Data Processing Pipeline

This directory contains the code to ingest, standardize, and transform raw PISA dataset files (`.sav`) into our final R-package-ready `.rda` formats.

We employ a two-step pipeline for processing this data, utilizing centralized schemas (like `variable_curation/PISA_variable_curation_student.csv`) to map variable names across multiple years.

## Two-Step Data Pipeline

### Step 1: Raw Ingestion (`Code/<year>/data_<year>.R`)

The first step of the pipeline focuses solely on safely and truthfully reading the raw SPSS `.sav` files.

For each year (e.g., in `Code/2022/data_2022.R`), we utilize the function `extract_raw_pisa()` from `Code/process_pisa.R`. This function reads the relevant schema CSV (e.g., `variable_curation/PISA_variable_curation_student.csv`), looks for the variables indicated in `source_col`, extracts those raw variables from the `.sav` file, and identically renames them to our unified `target_name`.

At this stage, **no data transformations or categorical factor conversions occur**. We preserve the original values and data types to prevent masking discrepancies.

The scripts then perform an automated validation check using `safe_save_rds()`, comparing the schema (dimensions and data types) of the new extracted dataframe against the previous `.rds` file (if one exists in the `Data/Output/<year>/` folder). These individual data extraction scripts write fully-transparent, localized timestamps and tracking output into `.log` files cleanly placed next to the scripts.

*(Note: In 2026, the `<year>` folder scripts such as `2022/data_2022.R` are being migrated to use this schema-based approach.)*

### Step 2: Transformation and Ensembling (`Code/student_bind_rows.Rmd` & `Code/school_bind_rows.Rmd`)

Once the localized `.rds` datasets for all individual years have been cleanly extracted, we execute `Code/student_bind_rows.Rmd` and `Code/school_bind_rows.Rmd`.

These Markdown files load the assembled `.rds` files from `Data/Output/` and apply the heavy, year-specific data transformations (converting numeric values into string-based logical factors) necessary to bind all years longitudinally. The output from these scripts drops the polished data directly into the R-package-ready format within the `Data/Output/Transfer/` folder.

## Target Schema Structure: Long-Format

As of 2026, we are migrating to a **Long-Format** schema, where each row explicitly defines how a single variable is extracted **for a specific year**. This allows us to handle year-to-year changes in variable names and value encodings smoothly.

The authoritative schema format is defined in `Code/pisa_variable_mapping.csv`.

### Column Definitions

| Column | Description | Example |
| --- | --- | --- |
| `year` | The study year the mapping applies to. | `2006` |
| `target_name` | The unified, generic variable name that will be published and consumed by downstream scripts. | `mother_educ` |
| `source_col` | The original column name as it appears in the specific year's raw data file. Can be `NA` if absent. | `ST13Q01` |
| `transformation` | The specific R function to apply, referencing the `transformation_registry` (see below) to perform explicit categorical decoding or type coercion. | `isced3a1`, `as.numeric` |
| `na_values` | Specific string or numeric codes in the raw data that should be explicitly interpreted as missing `NA` values. | `"9997,9999"` |
| `description` | A human-readable note or description of the variable. | `Mother's highest level of education (factor)` |
| `type` | The final expected R data type for the transformed column. | `factor`, `numeric` |

### Example Layout

| year | target_name | source_col | transformation | na_values | description | type |
| --- | --- | --- | --- | --- | --- | --- |
| 2000 | mother_educ | NA | NA | NA | Mother's highest education | factor |
| 2003 | mother_educ | ST11R01 | iscednone1 | NA | Mother's highest education | factor |
| 2006 | mother_educ | ST13Q01 | isced3a1 | NA | Mother's highest education | factor |
| 2018 | wealth | WEALTH | as.numeric | "95,97,98" | Family wealth index | numeric |

## Historical Information

The initial goal of this design was to resolve the maintenance nightmare of hardcoding variable name mappings, categorical value decodings, and ad-hoc data cleaning steps within separate R scripts for each year. We use a CSV tabular format to act as the single source of truth for all PISA variables across all years.

The old schema definitions were stored in wide-format files (`variable_curation/OUTDATED_PISA_variable_curation_student.csv`), which led to generic types and difficult management when encodings changed between years, prompting the shift to long-format schemas.
