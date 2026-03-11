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
# Auto-detects the script name and drops the log file cleanly in Code/2018
start_logging(script_path = here("Code", "2018", "data_2018.R"))

## ----student data processing--------------------------------------------------
message("Loading raw 2018 student data...")
stu_raw <- read_sav(here("Data/Raw/2018/STU/CY07_MSU_STU_QQQ.sav"))

# The primary goal of the year-specific script is pure, truthful data ingestion.
# We extract only the actual `source_col` names specified in the schema, without 
# applying any variable renaming, factor coercions, or derived calculations yet.
stu_qqq <- extract_raw_pisa(
  target_year = 2018,
  df = stu_raw,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_student.csv")
)

## ----school data processing---------------------------------------------------
message("Loading raw 2018 school data...")
sch_raw <- read_sav(here("Data/Raw/2018/SCH/CY07_MSU_SCH_QQQ.sav"))

sch_qqq <- extract_raw_pisa(
  target_year = 2018,
  df = sch_raw,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_school.csv")
)


## ----view summary students----------------------------------------------------
skimr::skim(stu_qqq) 


## ----view summary schools-----------------------------------------------------
skimr::skim(sch_qqq) 


## ----save files output--------------------------------------------------------
if (!dir.exists(here("Data/Output/2018"))) {
  dir.create(here("Data/Output/2018"), recursive = TRUE)
}

# Student questionnaire data files
safe_save_rds(stu_qqq, path = here("Data/Output/2018/stu_qqq.rds"))
# School questionnaire data file
safe_save_rds(sch_qqq, path = here("Data/Output/2018/sch_qqq.rds"))

## ----close-logs---------------------------------------------------------------
stop_logging()
