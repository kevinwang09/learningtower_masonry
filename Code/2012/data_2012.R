## ----packages-----------------------------------------------------------------
suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(skimr)
})

# Source the central robust pipeline scripts
source(here("Code/process_pisa.R"))

## ----logging------------------------------------------------------------------
# Auto-detects the script name and drops the log file cleanly in Code/2012
start_logging(script_path = here("Code", "2012", "data_2012.R"))

## ----legacy_notes-------------------------------------------------------------
# LEGACY NOTES:
# 1) The original script (`OUTDATED_data_2012.R`) specifically read from "altered" 
# text files:
#   - `PISA2012_SPSS_student_altered.txt`
#   - `PISA2012_SPSS_school_altered.txt`
# These files were manually created by an analyst who physically deleted 
# unnecessary header lines (like lines 1, 2, and lines 635-8762 etc.) from the 
# original `SPSS syntax to read in ___ questionnaire data file.txt`. 
#
# NEW APPROACH:
# We no longer require the analyst to manually alter and create these intermediate
# format text files. Instead, we use `readLines()` and a targeted regular expression
# to programmatically identify only the correctly formatted variable definition rows, 
# extracting the variables dynamically and computing their exact `read_fwf()` widths
# on the fly directly from the raw original downloaded syntax file natively!

## ----student data processing--------------------------------------------------
message("Loading raw 2012 student data...")

# Programmatically compute variable widths from the raw SPSS syntax file directly
# (replacing the manual `PISA2012_SPSS_student_altered.txt` completely!)
stu_var_widths <- parse_spss_syntax(here("Data/Raw/2012/SPSS syntax to read in student questionnaire data file.txt"))

raw_stu_df <- read_fwf(
  file = here("Data/Raw/2012/INT_STU12_DEC03.txt"), 
  col_positions = fwf_widths(
    stu_var_widths$widths, 
    col_names = as.character(stu_var_widths$names)
  ),
  show_col_types = FALSE
)

# The primary goal of the year-specific script is pure, truthful data ingestion.
stu_qqq <- extract_raw_pisa(
  target_year = 2012,
  df = raw_stu_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_student.csv")
)

## ----school data processing---------------------------------------------------
message("Loading raw 2012 school data...")

# Programmatically compute variable widths from the raw SPSS syntax file directly
# (replacing the manual `PISA2012_SPSS_school_altered.txt` completely!)
sch_var_widths <- parse_spss_syntax(here("Data/Raw/2012/SPSS syntax to read in school questionnaire data file.txt"))

raw_sch_df <- read_fwf(
  file = here("Data/Raw/2012/INT_SCQ12_DEC03.txt"), 
  col_positions = fwf_widths(
    sch_var_widths$widths, 
    col_names = as.character(sch_var_widths$names)
  ),
  show_col_types = FALSE
)

sch_qqq <- extract_raw_pisa(
  target_year = 2012,
  df = raw_sch_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_school.csv")
)

## ----view summary students----------------------------------------------------
skimr::skim(stu_qqq) 

## ----view summary schools-----------------------------------------------------
skimr::skim(sch_qqq) 

## ----save files output--------------------------------------------------------
if (!dir.exists(here("Data/Output/2012"))) {
  dir.create(here("Data/Output/2012"), recursive = TRUE)
}

# Student questionnaire data files
safe_save_rds(stu_qqq, path = here("Data/Output/2012/stu_qqq.rds"))
# School questionnaire data file
safe_save_rds(sch_qqq, path = here("Data/Output/2012/sch_qqq.rds"))

## ----close-logs---------------------------------------------------------------
stop_logging()
