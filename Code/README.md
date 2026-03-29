# PISA Data Processing Pipeline

This directory contains the code to ingest, standardize, and transform raw PISA dataset files (`.sav`) into our final R-package-ready `.rda` formats.

We employ a two-step pipeline for processing this data, utilizing centralized schemas (like `variable_curation/PISA_variable_curation_student.csv`) to map variable names across multiple years.

## ELT Data Architecture: Transform Late

To maximize data quality, unbroken lineage, and long-term maintainability, this project strictly adheres to an **ELT (Extract, Load, Transform)** database pattern.

**Architectural Rules:**

1. **Raw Ingestion (Extract/Load):** The individual year scripts (e.g., `Code/<year>/data_<year>.R`) MUST act purely as extractors. They strictly slice out the physical target columns specified in the schemas without modifying the underlying raw integers or string values. This ensures `Data/Output/<year>/` serves as an immutable "bronze" data lake securely mirroring the raw SPSS definitions.
2. **Centralized Transformation:** All data harmonization, factor coercions, and string decodings strictly happen *as late as possible* in the pipeline (e.g., inside `Code/student_bind_rows.Rmd` or via a dedicated centralized schema engine).

**Why Transform Late?**

- **Data Lineage:** It preserves absolute fidelity to the source binary/text `.sav` structures, meaning pipeline extraction operations don't destructively overwrite the fundamental data representations natively in transit.
- **Missing Value Protection:** PISA handles missingness inconsistently year-to-year (`99`, `9997`, `M/R`). By transporting the unaltered raw values to the central harmoniser, we maintain maximum analytical visibility over mapping decisions.
- **Scalability:** Baking single-year edge cases and native translations into individualized ETL scripts fragments the codebase and forces researchers to manage localized, differing outputs, whereas a centralized generic processor handles everything consistently.

## Two-Step Data Pipeline

### Step 1: Raw Ingestion (`Code/<year>/data_<year>.R`)

The first step of the pipeline focuses solely on safely and truthfully reading the raw SPSS files.

> **Developer Note: `fwf_positions` vs `fwf_widths`**
> When reading raw ASCII `.txt` data files with `readr::read_fwf()`, scripts **MUST** strictly use `fwf_positions(start, end)` instead of `fwf_widths(widths)`.
>
> - **The Bug:** Raw fixed-width data files often contain scattered blank spaces meant to be skipped by the SPSS dictionary definitions. Using `fwf_widths()` forces `read_fwf` to ingest contiguous blocks of characters. This causes any defined "skipped spaces" in the raw file to push subsequent columns out of alignment, silently corrupting the ingested dataframe.
> - **The Solution:** `fwf_positions(start, end)` correctly anchors variables to their explicit absolute string indices, natively hurdling over undocumented whitespace.

For each year, we utilize the function `extract_raw_pisa()` from `Code/process_pisa.R`. This function reads the relevant schema CSV (e.g., `variable_curation/PISA_variable_curation_student.csv`), looks for the variables indicated in `source_col`, extracts those raw variables from the `.sav` or raw ascii dataset, and identically renames them to our unified `target_name`.

At this stage, **no data transformations or categorical factor conversions occur**. We preserve the original values and data types to prevent masking discrepancies.

The scripts then perform an automated validation check using `safe_save_rds()`, comparing the schema of the new extracted dataframe against the previous `.rds` file. These scripts write fully-transparent, localized timestamps and tracking output into `.log` files.

### Step 2: Transformation and Ensembling (`Code/student_bind_rows.Rmd` & `Code/school_bind_rows.Rmd`)

Once the localized `.rds` datasets for all individual years have been cleanly extracted, we execute `Code/student_bind_rows.Rmd` and `Code/school_bind_rows.Rmd`.

These Markdown files load the assembled `.rds` files from `Data/Output/` and apply the heavy, year-specific data transformations (converting numeric values into string-based logical factors) necessary to bind all years longitudinally. The output from these scripts drops the polished data directly into the R-package-ready format within the `Data/Output/Transfer/` folder.

## Year-Specific Data Issues

### PISA 2000: Joining Split Assessment Booklets

When a specific year splits its student data across multiple domain-specific text files (e.g., Reading, Math, and Science in 2000), you **MUST** execute `full_join` strictly via the dataset's explicit primary keys: `c("COUNTRY", "SCHOOLID", "STIDSTD")`.

- **The Issue:** Blindly merging across all identically named overlapping columns across tests (e.g., `intersect(names(df1), names(df2))`) will systematically fabricate thousands of duplicate rows. Even though the demographic columns identically overlap, PISA assigns completely different scaled student inclusion weights (`w_fstuwt`) conditionally for each differing domain sub-test. When `full_join` evaluates the different numeric weights over identical students, it fundamentally interprets a mismatch conflict and splits the student into two disparate rows.
- **The Resolution:** Designate one test as the primary assessment booklet and selectively extract all generic variables (and `w_fstuwt`) exclusively from it. For all supplementary files, strip them down purely to the primary keys and the target plausible values (e.g. `pv1math`) prior to the `full_join`.

### PISA 2015
- **Missing Variables:** The `dishwasher` metric natively does not map accurately due to problematic storage inside the raw 2015 source dictionaries. The column is retained structurally for standardization but is explicitly populated with 100% missing (`NA`) values per legacy convention.

### PISA 2022
- **Missing Variables:** The `desk`, `dishwasher`, and `wealth` metrics were not uniquely surveyed in the 2022 PISA iteration. These missing components formally retain their standard structural identities within the pipeline payload but default strictly to isolated `NA` collections.

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
