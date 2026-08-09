# Introduction

This is the code respository for curating the `learningtower` package in `R`. This package is currently available at <https://github.com/kevinwang09/learningtower> and via CRAN at <https://cran.r-project.org/web/packages/learningtower/index.html>.

The `learningtower` package contains a subset of the [PISA data published by OECD](https://www.oecd.org/pisa/data/). The data curated by OECD is very comprehensive but can be formidable for exploratory data analysis. The most intensive component of publishing the `learningtower` package is the curation of the triennial data to ensure consistency. This repository, `learningtower_masonry` is a repo that documents clearly how every data is curated from its raw form to a curated form.

# Acknowledgment of authorship

+ This data was initially curated in OzUnconf 2019. The original contributors are Kevin Wang, Erika Siregar, Sarah Romanes, Kim Fitter, Giulio Valentino Dalla Riva, Di Cook and Nick Tierney.
  
+ This data was later curated by Priya Dingorkar, Guan Ru Chen and Shabarish from Monash University, under the supervision of Dr Kevin Wang and Professor Di Cook.

# Data structure

To fully understand the `learningtower_masonry` repository, it is helpful to visualize the overarching data pipeline. We strictly separate data acquisition, metadata extraction, raw data ingestion, and final transformation into distinct phases across Python and R.

```text
========================================================================================
                          OVERALL PISA DATA PIPELINE ARCHITECTURE
========================================================================================

 1. DATA ACQUISITION & EXTRACTION (Python)
    --------------------------------------
    [PISA Data Files.html] 
             |
             v
    [download_raw_data.py] ---> (Downloads .zip files to Data/Raw/<year>/)
             |
             v
    [prepare_raw_data.py]  ---> (Extracts .sav/.txt files locally)


 2. CODEBOOK METADATA CURATION (Python + AI)
    ----------------------------------------
    [extraction_tasks.yaml]
             |
    [extract_codebook.py]  ---> (Routes PDFs to LlamaCloud / Excel to Pandas)
             |
             v
    [{year}_extracted.json] --> [validate_curation.py] <--> [variable_curation/*.csv]
                                 (Validates expected schemas & NA values)

 3. RAW DATA INGESTION: "Transform Late" Pattern (R)
    ------------------------------------------------
    [Data/Raw/<year>/*.sav] 
             |
    [Code/<year>/data_<year>.R]  <-- Uses [variable_curation/*.csv] for target mapping
             |                       (Strict extraction ONLY, no transformations)
             v
    [Data/Output/<year>/*.rds]   <-- (Immutable "Bronze" Data Lake)


 4. HARMONIZATION & FINAL AGGREGATION (R)
    -------------------------------------
    [Data/Output/<year>/*.rds]
             |
    [Code/student_bind_rows.Rmd] & [Code/school_bind_rows.Rmd]
             |                   <-- (Type coercion, categorical decoding, binding)
             v
    [Data/Output/student.rda] & [Data/Output/school.rda]  <-- Final R Package Data
========================================================================================
```
It is important to recognise the structure of the PISA data being curated. Every 3 years, the PISA data is published with:

+ Student questionnaire, typically named as "STU_QQQ.zip".
+ School questionnaire, typically named as "SCH_QQQ.zip".
+ "Code books", which are similar to data dictionaries.

The questionnaire zip folders can contain data in either SAS or SPSS formats. Depending on the data specifications of that year, these data can be read by their respective proprietary software or through open-source `R` libraries. The code books are typically published in Excel formats for recent years, and as complex PDF documents for older legacy years.

### The Critical Role of Codebooks

Codebooks (or data dictionaries) act as the absolute source of truth for making sense of the raw PISA datasets. Because the OECD frequently alters variable names, scaling metrics, and categorical missing value encodings (e.g., using `99` in one year and `9997` in another) between triennial surveys, it is impossible to reliably bind raw datasets together blindly.

By systematically extracting the unstructured text from these codebooks into standardized JSON formats (via our Automated Extraction Pipeline), we gain programmatic visibility into all historical variations. We use this extracted metadata to construct and continuously validate our centralized CSV mapping schemas (`variable_curation/PISA_variable_curation_*.csv`). 

These CSV schemas act as the "rosetta stone" for the pipeline—they instruct the R scripts exactly how to locate, extract, and translate fluctuating raw variables across multiple decades into a single, cohesive, and carefully curated final R package dataset.
**In the `learningtower` package we only curate**:

1. Student data
2. School data
3. Country data

Since the list of countries do not differ significantly between the years, the student and school data are typically the ones that needs to be updated upon new publication of PISA data.

## Workflow to curate new data (updated: April 2026)

Please consult with either Kevin Wang about adding new data.

In 2026, PISA changed how their data can be accessed, hence a new framework that automates the raw data download process was developed, see [this document](Data/Raw/README.md) to understand how the raw data can now be downloaded using the PISA html file and a python script. **Due to size constraints, the raw data were never committed to GitHub. The proper folder structures are preserved using .gitkeep.**.

+ After the raw data are downloaded, create a new R script to document how the raw data should be extracted into an `rds` format at `Data/Output/yyyy/sch_qqq.rds` and `Data/Output/yyyy/stu_qqq.rds`. The student data should be named `stu_qqq.rds` and the school data should be named `sch_qqq.rds`. These rds format should be a 'faithful' extraction of the raw data without additional transformations.
+ Add new code books into the `codebook` folder.
+ **CAUTION: we do not accept curation of new variables unless there are some fundamental changes in how PISA publishes their data**. Curation of new variables must be documented in [PISA Variables' Table](https://docs.google.com/spreadsheets/d/1yuwYUO3A9fBThuMFnTZaP_Bb8lD0TF5w7lPvoEo7HvU/edit?gid=0#gid=0){.uri}
+ The cleaned data should be saved in `Data/Output/yyyy`.
+ Update `Code/student_bind_rows.Rmd` and `Code/school_bind_rows.Rmd`. The updated data with all years bound together will be saved under `Data/Output/Transfer/` (including `Data/Output/Transfer/data/` for `.rda` subsets and `Data/Output/Transfer/student_full_data/` for full `.rds` files).
+ Copy over the files to a forked copy of the `learningtower` package. Update relevant vignettes and scripts.

## Automated Codebook Extraction Architecture (New in 2026)

To tackle the complexities of extracting structured metadata from messy legacy PDF and Excel codebooks, we introduced a new Python-based extraction pipeline that operates independently of R.

```text
========================================================================
                 Automated Codebook Extraction Pipeline
========================================================================
                                
                    [extraction_tasks.yaml] (Manifest)
                                  |
                                  v
                       [extract_codebook.py]
                                (Router)
                               /        \
                    (PDF tasks)          (Excel tasks)
                        /                  \
   [parse_codebook.py]                      \
     (LlamaCloud Parse)                      \
            |                                 \
            v                                  v
       [Markdown]                 [extract_tabular_codebook.py]
            |                             (Pandas)
            v                                  |
 [extract_pdf_codebook.py]                     |
    (LlamaCloud Extract)                       |
            |                                  |
            +-----------------+----------------+
                              |
                              v
                   [{year}_extracted.json] 
                       (Structured Data)
                              |
                              v
                   [validate_curation.py] <----- [PISA_variable_curation_*.csv]
                              |                  (Expected NA keys, mappings)
                              v
                       [Validation Logs]
                     (Pass / Fail / Warn)
========================================================================
```

**Key Components:**

1. **`extraction_tasks.yaml`**: The central configuration mapping PISA years to their respective codebook files.
2. **`extract_codebook.py`**: An intelligent wrapper that routes tasks based on the file format.
3. **`parse_codebook.py` & `extract_pdf_codebook.py`**: Uses LlamaCloud Parse to convert legacy PDFs into markdown, and then LlamaCloud Extract to pull structured variable definitions (including tricky `na_values`) into JSON.
4. **`extract_tabular_codebook.py`**: A heuristic-driven pandas script that extracts codebooks from more modern Excel files.
5. **`validate_curation.py`**: A validation engine that checks the extracted JSON codebooks against our master CSV schemas (`PISA_variable_curation_*.csv`), ensuring missing variables or undocumented NA values are flagged immediately.

# Miscellaneous issues

## Geographical and Regional Representation

In the context of the PISA data and the `learningtower` package, the term "country" is used as a convenient shorthand for the various geographic and administrative entities that participate in the survey. It is important to note that these participating entities often represent specific regions, territories, or sub-national economies, rather than fully sovereign states.

The nomenclature used in this dataset (including ISO-style codes and region names) strictly reflects the administrative labels provided by the official PISA surveys. It is utilized here solely for data organization and statistical purposes, and does not imply any expression of opinion concerning the legal status or geopolitical designation of any territory or area. Furthermore, please be aware that these administrative labels may evolve from year to year depending on how the PISA organizers designate participating entities.

## Variable naming consistencies between different years (updated: April 2026)

The main challenge that the contributors encountered was to ensure the consistency of variables between different years. For instance, the highest schooling of a student's mother was never recorded in 2000, but it was coded as "ST11R01" between the years 2003 to 2012 and "ST005Q01TA" between the years 2015 and 2018. These variables were manually curated by all contributors as a factor variable, "mother_educ", in the output data.

We created schema files to document these variable changes:

+ [Schema for student data variable curation](variable_curation/PISA_variable_curation_student.csv)
+ [Schema for school data variable curation](variable_curation/PISA_variable_curation_school.csv)

### Year-Specific Codebook & Data Anomalies

Throughout the curation process, we have identified numerous inconsistencies between the published PISA codebooks and the raw dataset files. 

For instance, several variables may be missing due to the reconstruction of questionnaires. A question regarding student's possession of a desk is not recorded in 2022, but it was coded in previous questionnaires, hence these variables were manually curated by all masons as a character variable in the output data. Another important issue we faced is the missing variable `WEALTH` in the 2022 codebook. This variable could be used to estimate a student's socioeconomic status. For further related analysis or research, another variable called `ESCS` (economic, social and cultural status) is more suitable.

**Note:** There are other similar issues where variables are entirely missing, or missing values (`NA`) are documented completely incorrectly in the codebook compared to the actual raw `.sav` data (e.g., documenting `9999995` instead of `95`). For an exhaustive and detailed list of these extraction anomalies, please refer to the **Codebook Anomalies & Known Issues** section in [codebook/README.md](codebook/README.md).

## Reading in SAS and SPSS data

PISA publishes data in both SAS and PRSS format for all survey years. Where possible, the `.sav` file was used to read in the published raw data. The only exception was in the year 2000, where `.sav` files were not published and instead, `.txt`files with SPSS scripts were published to allow for the creation of `.sav` files. In order to resolve this, we used the SPSS software to perform conversions of `.txt` files to `.sav` files.

## Identical school/student ID doesn't refer to the same school/student

It should be noted that it was possible for schools to receive the same school ID even within the same year. Consider the following example:

``` r
load("~/Desktop/learningtower_masonry/Data/Output/student.rda")
library(tidyverse)

student %>% 
  group_by(year, country_iso3c, school_id) %>% 
  tally() %>% 
  filter(school_id == "1001")
#> # A tibble: 14 x 4
#> # Groups:   year, country_iso3c [14]
#>     year country_iso3c school_id     n
#>    <int> <fct>         <fct>     <int>
#>  1  2000 ALB           1001         19
#>  2  2000 CAN           1001         32
#>  3  2000 ESP           1001         20
#>  4  2000 FRA           1001         13
#>  5  2000 HUN           1001         19
#>  6  2000 ISR           1001         20
#>  7  2000 LUX           1001        157
#>  8  2000 NLD           1001         15
#>  9  2000 POL           1001         16
#> 10  2000 THA           1001         19
#> 11  2006 MEX           1001         25
#> 12  2006 THA           1001         34
#> 13  2006 KGZ           1001         33
#> 14  2006 LTU           1001         27
```

This means that the school ID is only unique within the year and the country. This means that the school ID is only unique within the year and the country.
