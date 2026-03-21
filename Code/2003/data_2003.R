## ----packages-----------------------------------------------------------------
suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(skimr)
})

# Source the central robust pipeline scripts
source(here("Code/process_pisa.R"))

## ----logging------------------------------------------------------------------
# Auto-detects the script name and drops the log file cleanly in Code/2003
start_logging(script_path = here("Code", "2003", "data_2003.R"))

## ----legacy_notes-------------------------------------------------------------
# LEGACY NOTES:
# 1) The original script (`OUTDATED_data_2003_editMay2020.R`) read fixed format haven binary `.sav` files.
# 
# NEW APPROACH:
# We use `parse_spss_syntax()` to dynamically evaluate variable boundaries from 
# the downloaded ascii dictionary `PISA2003_SPSS_student.txt` natively!

## ----student data processing--------------------------------------------------
message("Loading raw 2003 student data...")

# Programmatically compute variable widths from the raw SPSS syntax file directly
stu_var_widths <- parse_spss_syntax(here("Data/Raw/2003/PISA2003_SPSS_student.txt"))

raw_stu_df <- read_fwf(
  file = here("Data/Raw/2003/INT_stui_2003_v2.txt"), 
  col_positions = fwf_widths(
    stu_var_widths$widths, 
    col_names = as.character(stu_var_widths$names)
  ),
  show_col_types = FALSE
)

# The primary goal of the year-specific script is pure, truthful data ingestion.
stu_qqq <- extract_raw_pisa(
  target_year = 2003,
  df = raw_stu_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_student.csv")
)

## ----school data processing---------------------------------------------------
message("Loading raw 2003 school data...")

# Programmatically compute variable widths from the raw SPSS syntax file directly
sch_var_widths <- parse_spss_syntax(here("Data/Raw/2003/PISA2003_SPSS_school.txt"))

raw_sch_df <- read_fwf(
  file = here("Data/Raw/2003/INT_schi_2003.txt"), 
  col_positions = fwf_widths(
    sch_var_widths$widths, 
    col_names = as.character(sch_var_widths$names)
  ),
  show_col_types = FALSE
)

sch_qqq <- extract_raw_pisa(
  target_year = 2003,
  df = raw_sch_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_school.csv")
)

## ----view summary students----------------------------------------------------
skimr::skim(stu_qqq) 

## ----view summary schools-----------------------------------------------------
skimr::skim(sch_qqq) 

## ----save files output--------------------------------------------------------
if (!dir.exists(here("Data/Output/2003"))) {
  dir.create(here("Data/Output/2003"), recursive = TRUE)
}

# Student questionnaire data files
safe_save_rds(stu_qqq, path = here("Data/Output/2003/stu_qqq.rds"))
# School questionnaire data file
safe_save_rds(sch_qqq, path = here("Data/Output/2003/sch_qqq.rds"))

## ----close-logs---------------------------------------------------------------
stop_logging()
