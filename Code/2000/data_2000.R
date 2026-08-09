## ----packages-----------------------------------------------------------------
suppressPackageStartupMessages({
  library(here)
  library(tidyverse)
  library(skimr)
  library(haven)
})

# Source the central robust pipeline scripts
source(here("Code/process_pisa.R"))

## ----logging------------------------------------------------------------------
# Auto-detects the script name and drops the log file cleanly in Code/2000
start_logging(script_path = here("Code", "2000", "data_2000.R"))

## ----legacy_notes-------------------------------------------------------------
# LEGACY NOTES:
# 1) The original scripts (`OUTDATED_school2000.R` & `OUTDATED_student2000.R`) read fixed format haven binary `.sav` files.
#    Since PISA 2000 separated domain assignments, a `left_join` dropped all non-science students.
# 
# NEW APPROACH:
# We use `parse_spss_syntax()` to dynamically evaluate variable boundaries from 
# the downloaded ascii dictionaries `PISA2000_SPSS_student_*.txt` natively! 
# A full join preserves the entire student base across all test modes.

# SPSS Decoding Helper
apply_spss_labels <- function(df, labels_df) {
  all_cols <- colnames(df)
  for (var_group in unique(labels_df$variables)) {
    tokens <- strsplit(var_group, "\\s+")[[1]]
    out_vars <- character()
    
    i <- 1
    while (i <= length(tokens)) {
      if (i < length(tokens) - 1 && tolower(tokens[i+1]) == "to") {
        s_idx <- match(tokens[i], all_cols)
        e_idx <- match(tokens[i+2], all_cols)
        if (!is.na(s_idx) && !is.na(e_idx) && s_idx <= e_idx) {
          out_vars <- c(out_vars, all_cols[s_idx:e_idx])
        }
        i <- i + 3
      } else {
        if (tokens[i] %in% all_cols) out_vars <- c(out_vars, tokens[i])
        i <- i + 1
      }
    }
    
    valid_vars <- unique(out_vars)
    if (length(valid_vars) > 0) {
      mapping <- labels_df[labels_df$variables == var_group, ]
      map_vec <- setNames(mapping$label, mapping$value)
      
      for (v in valid_vars) {
        target_vec <- as.character(df[[v]])
        df[[v]] <- ifelse(target_vec %in% names(map_vec), map_vec[target_vec], df[[v]])
      }
    }
  }
  return(df)
}

## ----student data processing--------------------------------------------------
message("Loading raw 2000 student data (Read, Math, Science)...")

# Isolate requested curation variables to optimize memory parsing limits
stu_mapped_vars <- read_csv(here("variable_curation/PISA_variable_curation_student.csv"), show_col_types = FALSE, comment = "#") %>%
  filter(year == 2000, !is.na(source_col) & source_col != "NA") %>%
  pull(source_col)

# Join keys are strictly required
stu_mapped_vars <- unique(c(stu_mapped_vars, "COUNTRY", "SCHOOLID", "STIDSTD"))

w_read <- parse_spss_syntax(here("Data/Raw/2000/PISA2000_SPSS_student_reading.txt")) %>% filter(names %in% stu_mapped_vars)
w_math <- parse_spss_syntax(here("Data/Raw/2000/PISA2000_SPSS_student_mathematics.txt")) %>% filter(names %in% stu_mapped_vars)
w_scie <- parse_spss_syntax(here("Data/Raw/2000/PISA2000_SPSS_student_science.txt")) %>% filter(names %in% stu_mapped_vars)

raw_read_df <- read_fwf(
  file = here("Data/Raw/2000/intstud_read_v3.txt"), 
  col_positions = fwf_positions(w_read$start, w_read$end, col_names = as.character(w_read$names)),
  show_col_types = FALSE
)
raw_math_df <- read_fwf(
  file = here("Data/Raw/2000/intstud_math_v3.txt"), 
  col_positions = fwf_positions(w_math$start, w_math$end, col_names = as.character(w_math$names)),
  show_col_types = FALSE
)
raw_scie_df <- read_fwf(
  file = here("Data/Raw/2000/intstud_scie_v3.txt"), 
  col_positions = fwf_positions(w_scie$start, w_scie$end, col_names = as.character(w_scie$names)),
  show_col_types = FALSE
)

message("Fusing split text vectors...")
common_cols <- Reduce(intersect, list(colnames(raw_read_df), colnames(raw_math_df), colnames(raw_scie_df)))

pk_cols <- c("COUNTRY", "SCHOOLID", "STIDSTD")

# Isolate the exact subset needed for fusing to minimize memory duplication limits.
# We pull all core variables & weights natively from the primary Reading assessment,
# and strictly attach only the distinct plausible values from the Math/Science sub-tests.
read_sub <- raw_read_df %>% select(all_of(common_cols), pv1read)
math_sub <- raw_math_df %>% select(all_of(pk_cols), pv1math)
scie_sub <- raw_scie_df %>% select(all_of(pk_cols), pv1scie)

rm(raw_read_df, raw_math_df, raw_scie_df)
gc()

pisa_2000_merged <- read_sub %>% 
  full_join(math_sub, by = pk_cols) %>% 
  full_join(scie_sub, by = pk_cols)

# Load ESCS index from standalone SPSS Sav because it lacks text representation
message("Loading ESCS indexing...")
escs_raw <- haven::read_sav(here("Data/Raw/2000/ESCS_PISA2000.sav")) %>%
  select(COUNTRY = CNT, SCHOOLID, STIDSTD, ESCS) %>%
  mutate(across(c(COUNTRY, SCHOOLID, STIDSTD), as.character))

message("Dynamically translating numeric encodings to SPSS descriptive factors...")
stu_val_labels <- parse_spss_value_labels(here("Data/Raw/2000/PISA2000_SPSS_student_reading.txt"))
pisa_2000_merged <- apply_spss_labels(pisa_2000_merged, stu_val_labels)

message("Bridging Student COUNTRY full names to ISO 3-character equivalents...")
cnt_dict_stu <- stu_val_labels %>% filter(variables == "CNT")
inv_cnt_map_stu <- setNames(cnt_dict_stu$value, cnt_dict_stu$label) 

pisa_2000_merged$COUNTRY <- ifelse(
  pisa_2000_merged$COUNTRY %in% names(inv_cnt_map_stu),
  inv_cnt_map_stu[pisa_2000_merged$COUNTRY],
  pisa_2000_merged$COUNTRY
)

pisa_2000_merged <- pisa_2000_merged %>% left_join(escs_raw, by = c("COUNTRY", "SCHOOLID", "STIDSTD"))

# Perform extraction map protocol
stu_qqq <- extract_raw_pisa(
  target_year = 2000,
  df = pisa_2000_merged,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_student.csv")
)

## ----school data processing---------------------------------------------------
message("Loading raw 2000 school data...")

sch_mapped_vars <- read_csv(here("variable_curation/PISA_variable_curation_school.csv"), show_col_types = FALSE, comment = "#") %>%
  filter(year == 2000, !is.na(source_col) & source_col != "NA") %>%
  pull(source_col)

sch_var_widths <- parse_spss_syntax(here("Data/Raw/2000/PISA2000_SPSS_school_questionnaire.txt")) %>%
  filter(names %in% sch_mapped_vars)

raw_sch_df <- read_fwf(
  file = here("Data/Raw/2000/intscho.txt"), 
  col_positions = fwf_positions(sch_var_widths$start, sch_var_widths$end, col_names = as.character(sch_var_widths$names)),
  show_col_types = FALSE
)

message("Translating school questionnaire factors...")
sch_val_labels <- parse_spss_value_labels(here("Data/Raw/2000/PISA2000_SPSS_school_questionnaire.txt"))
raw_sch_df <- apply_spss_labels(raw_sch_df, sch_val_labels)

message("Bridging School COUNTRY full names to ISO 3-character equivalents...")
cnt_dict_sch <- sch_val_labels %>% filter(variables == "CNT")
inv_cnt_map_sch <- setNames(cnt_dict_sch$value, cnt_dict_sch$label)

raw_sch_df$country <- ifelse(
  raw_sch_df$country %in% names(inv_cnt_map_sch),
  inv_cnt_map_sch[raw_sch_df$country],
  raw_sch_df$country
)

sch_qqq <- extract_raw_pisa(
  target_year = 2000,
  df = raw_sch_df,
  mapping_csv_path = here("variable_curation/PISA_variable_curation_school.csv")
)

## ----save files output--------------------------------------------------------
if (!dir.exists(here("Data/Output/2000"))) {
  dir.create(here("Data/Output/2000"), recursive = TRUE)
}

# Optional visual summaries
# skimr::skim(stu_qqq)
# skimr::skim(stu_qqq_old)

# Student questionnaire data files
safe_save_rds(stu_qqq, path = here("Data/Output/2000/stu_qqq.rds"))
# School questionnaire data file
safe_save_rds(sch_qqq, path = here("Data/Output/2000/sch_qqq.rds"))

## ----close-logs---------------------------------------------------------------
stop_logging()
