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
# Auto-detects the script name and drops the log file cleanly in Code/2022
start_logging(script_path = here("Code", "2022", "data_2022.R"))

## ----student data processing--------------------------------------------------
message("Loading raw 2022 student data...")
stu_raw <- read_sav(here("Data/Raw/2022/CY08MSP_STU_QQQ.SAV"))

# The primary goal of the year-specific script is pure, truthful data ingestion.
# We extract only the actual `source_col` names specified in the schema, without 
# applying any variable renaming, factor coercions, or derived calculations yet.
stu_qqq <- extract_raw_pisa(
  target_year = 2022,
  df = stu_raw,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_student.csv")
)

## ----school data processing---------------------------------------------------
message("Loading raw 2022 school data...")
sch_raw <- read_sav(here("Data/Raw/2022/CY08MSP_SCH_QQQ.SAV"))

sch_qqq <- extract_raw_pisa(
  target_year = 2022,
  df = sch_raw,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_school.csv")
)


## ----view summary students----------------------------------------------------
skimr::skim(stu_qqq) 


## ----view summary schools-----------------------------------------------------
skimr::skim(sch_qqq) 


## ----save files output--------------------------------------------------------
if (!dir.exists(here("Data/Output/2022"))) {
  dir.create(here("Data/Output/2022"), recursive = TRUE)
}

# Student questionnaire data files
safe_save_rds(stu_qqq, path = here("Data/Output/2022/stu_qqq.rds"))
# School questionnaire data file
safe_save_rds(sch_qqq, path = here("Data/Output/2022/sch_qqq.rds"))

## ----close-logs---------------------------------------------------------------
stop_logging()

