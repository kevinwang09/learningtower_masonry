## ----packages-----------------------------------------------------------------
suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(haven)
  library(skimr)
})

# Source the central robust pipeline scripts
source(here("Code/process_pisa.R"))

## ----logging------------------------------------------------------------------
# Auto-detects the script name and drops the log file cleanly in Code/2015
start_logging(script_path = here("Code", "2015", "data_2015.R"))

## -----------------------------------------------------------------------------
# Legacy notes from OUTDATED_data_2015.Rmd:
# We initially extracted columns: "CNT", "CNTSCHID", "CNTSTUID", "ST005Q01TA", 
# "ST007Q01TA", "ST004D01T", "ST011Q04TA", "ST011Q06TA", "PV1MATH", "PV1READ", 
# "PV1SCIE", "W_FSTUWT", "ST011Q01TA", "ST011Q02TA", "ST012Q01TA", "ST012Q06NA", 
# "ST012Q02TA", "ST013Q01TA", "WEALTH", "ESCS".
#
# Notably, `dishwasher` (previously mapped differently or unavailable) is structurally
# set to NA per the new schema mapping (and the old legacy script).

## ----student data processing--------------------------------------------------
message("Loading raw 2015 student data...")
# Read the .sav format instead of the old .sas7bdat format
stu_raw <- read_sav(here("Data/Raw/2015/CY6_MS_CMB_STU_QQQ.sav"))

# The primary goal of the year-specific script is pure, truthful data ingestion.
# We extract only the actual `source_col` names specified in the schema, without 
# applying any variable renaming, factor coercions, or derived calculations yet.
stu_qqq <- extract_raw_pisa(
  target_year = 2015,
  df = stu_raw,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_student.csv")
)

## ----school data processing---------------------------------------------------
message("Loading raw 2015 school data...")
# Read the .sav format instead of the old .sas7bdat format
sch_raw <- read_sav(here("Data/Raw/2015/CY6_MS_CMB_SCH_QQQ.sav"))

sch_qqq <- extract_raw_pisa(
  target_year = 2015,
  df = sch_raw,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_school.csv")
)

## ----view summary students----------------------------------------------------
skimr::skim(stu_qqq) 

## ----view summary schools-----------------------------------------------------
skimr::skim(sch_qqq) 

## ----save files output--------------------------------------------------------
if (!dir.exists(here("Data/Output/2015"))) {
  dir.create(here("Data/Output/2015"), recursive = TRUE)
}

# Student questionnaire data files
safe_save_rds(stu_qqq, path = here("Data/Output/2015/stu_qqq.rds"))
# School questionnaire data file
safe_save_rds(sch_qqq, path = here("Data/Output/2015/sch_qqq.rds"))

## ----close-logs---------------------------------------------------------------
stop_logging()
