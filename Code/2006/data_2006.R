## ----packages-----------------------------------------------------------------
suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(skimr)
})

# Source the central robust pipeline scripts
source(here("Code/process_pisa.R"))

## ----logging------------------------------------------------------------------
# Auto-detects the script name and drops the log file cleanly in Code/2006
start_logging(script_path = here("Code", "2006", "data_2006.R"))

## ----legacy_notes-------------------------------------------------------------
# LEGACY NOTES:
# 1) The original script (`OUTDATED_data_2006.R`) read fixed format text using manually computed integer offsets.
# 
# NEW APPROACH:
# We use `parse_spss_syntax()` to dynamically evaluate variable boundaries from 
# `PISA2006_SPSS_student.txt` programmatically and reliably!

## ----student data processing--------------------------------------------------
message("Loading raw 2006 student data...")

# Programmatically compute variable widths from the raw SPSS syntax file directly
stu_var_widths <- parse_spss_syntax(here("Data/Raw/2006/PISA2006_SPSS_student.txt"))

raw_stu_df <- read_fwf(
  file = here("Data/Raw/2006/INT_Stu06_Dec07.txt"), 
  col_positions = fwf_widths(
    stu_var_widths$widths, 
    col_names = as.character(stu_var_widths$names)
  ),
  show_col_types = FALSE
)

# The primary goal of the year-specific script is pure, truthful data ingestion.
stu_qqq <- extract_raw_pisa(
  target_year = 2006,
  df = raw_stu_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_student.csv")
)

## ----school data processing---------------------------------------------------
message("Loading raw 2006 school data...")

# Programmatically compute variable widths from the raw SPSS syntax file directly
sch_var_widths <- parse_spss_syntax(here("Data/Raw/2006/PISA2006_SPSS_school.txt"))

raw_sch_df <- read_fwf(
  file = here("Data/Raw/2006/INT_Sch06_Dec07.txt"), 
  col_positions = fwf_widths(
    sch_var_widths$widths, 
    col_names = as.character(sch_var_widths$names)
  ),
  show_col_types = FALSE
)

sch_qqq <- extract_raw_pisa(
  target_year = 2006,
  df = raw_sch_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_school.csv")
)

## ----view summary students----------------------------------------------------
skimr::skim(stu_qqq) 

## ----view summary schools-----------------------------------------------------
skimr::skim(sch_qqq) 

## ----save files output--------------------------------------------------------
if (!dir.exists(here("Data/Output/2006"))) {
  dir.create(here("Data/Output/2006"), recursive = TRUE)
}

# Student questionnaire data files
safe_save_rds(stu_qqq, path = here("Data/Output/2006/stu_qqq.rds"))
# School questionnaire data file
safe_save_rds(sch_qqq, path = here("Data/Output/2006/sch_qqq.rds"))

## ----close-logs---------------------------------------------------------------
stop_logging()
