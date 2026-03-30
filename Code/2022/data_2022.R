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

stu_raw <- stu_raw %>%
  dplyr::mutate(
    # Create numeric estimates for desktop and laptop based on categorical codes
    num_desktop = dplyr::case_when(
      as.numeric(ST254Q02JA) == 1 ~ 0, # None
      as.numeric(ST254Q02JA) == 2 ~ 1, # 1 or 2 (conservative)
      as.numeric(ST254Q02JA) == 3 ~ 3, # 3 - 5
      as.numeric(ST254Q02JA) == 4 ~ 5, # More than 5
      TRUE ~ NA_real_
    ),
    num_laptop = dplyr::case_when(
      as.numeric(ST254Q03JA) == 1 ~ 0, # None
      as.numeric(ST254Q03JA) == 2 ~ 1, # 1 or 2
      as.numeric(ST254Q03JA) == 3 ~ 3, # 3 - 5
      as.numeric(ST254Q03JA) == 4 ~ 5, # More than 5
      TRUE ~ NA_real_
    ),
    num_total = num_desktop + num_laptop,
    
    # Map back to 1=None, 2=One, 3=Two, 4=Three or more for backward compatibility
    # so `none1one2two3threemore4` parses it safely exactly like previous years.
    COMPUTER_N = dplyr::case_when(
      num_total == 0 ~ 1,
      num_total == 1 ~ 2,
      num_total == 2 ~ 3,
      num_total >= 3 ~ 4,
      TRUE ~ NA_real_
    ),
    
    # Map to 1=Yes, 2=No for `computer` possession (`yes1no2`) compatibility
    COMPUTER = dplyr::case_when(
      num_total == 0 ~ 2,
      num_total > 0 ~ 1,
      TRUE ~ NA_real_
    )
  )

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

