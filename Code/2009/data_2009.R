## ----packages-----------------------------------------------------------------
suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(skimr)
})

# Source the central robust pipeline scripts
source(here("Code/process_pisa.R"))

## ----logging------------------------------------------------------------------
# Auto-detects the script name and drops the log file cleanly in Code/2009
start_logging(script_path = here("Code", "2009", "data_2009.R"))

## ----legacy_notes-------------------------------------------------------------
# LEGACY NOTES:
# 1) The original script (`OUTDATED_data_2009.R`) read fixed format text using manually calculated widths.
# 
# NEW APPROACH:
# We use `parse_spss_syntax()` to programmatically identify only the correctly formatted variable definition rows, 
# extracting the variables dynamically and computing their exact `read_fwf()` widths
# on the fly directly from the raw original downloaded syntax file natively!

## ----student data processing--------------------------------------------------
message("Loading raw 2009 student data...")

# Programmatically compute variable widths from the raw SPSS syntax file directly
stu_var_widths <- parse_spss_syntax(here("Data/Raw/2009/PISA2009_SPSS_student.txt"))

raw_stu_df <- read_fwf(
  file = here("Data/Raw/2009/INT_STQ09_DEC11.txt"), 
  col_positions = fwf_widths(
    stu_var_widths$widths, 
    col_names = as.character(stu_var_widths$names)
  ),
  show_col_types = FALSE
)

# The primary goal of the year-specific script is pure, truthful data ingestion.
stu_qqq <- extract_raw_pisa(
  target_year = 2009,
  df = raw_stu_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_student.csv")
)

## ----school data processing---------------------------------------------------
message("Loading raw 2009 school data...")

# Programmatically compute variable widths from the raw SPSS syntax file directly
sch_var_widths <- parse_spss_syntax(here("Data/Raw/2009/PISA2009_SPSS_school.txt"))

raw_sch_df <- read_fwf(
  file = here("Data/Raw/2009/INT_SCQ09_Dec11.txt"), 
  col_positions = fwf_widths(
    sch_var_widths$widths, 
    col_names = as.character(sch_var_widths$names)
  ),
  show_col_types = FALSE
)

sch_qqq <- extract_raw_pisa(
  target_year = 2009,
  df = raw_sch_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_school.csv")
)

## ----view summary students----------------------------------------------------
skimr::skim(stu_qqq) 

## ----view summary schools-----------------------------------------------------
skimr::skim(sch_qqq) 

## ----save files output--------------------------------------------------------
if (!dir.exists(here("Data/Output/2009"))) {
  dir.create(here("Data/Output/2009"), recursive = TRUE)
}

# Student questionnaire data files
safe_save_rds(stu_qqq, path = here("Data/Output/2009/stu_qqq.rds"))
# School questionnaire data file
safe_save_rds(sch_qqq, path = here("Data/Output/2009/sch_qqq.rds"))

## ----close-logs---------------------------------------------------------------
stop_logging()
