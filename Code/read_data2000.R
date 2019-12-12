# Brute force text conversion
library(tidyverse)
# 
# ## Science 
# script = "Data/Raw/2000/PISA2000_SPSS_student_science_spss_script.txt"
# var_table = read.table(script, fill = TRUE) %>% 
#   as_tibble %>% 
#   mutate(widths = as.numeric(V4) - as.numeric(V2) + 1, 
#          names = V1)
# 
# science_df = read_fwf(
#   file = "Data/Raw/2000/intstud_scie.zip",
#   col_positions = fwf_widths(var_table$widths,
#                              col_names = var_table$names))

scie = haven::read_sav("Data/Raw/2000/sav/intstud_scie.sav")
head(scie)

read = haven::read_sav("Data/Raw/2000/sav/intstud_read.sav")
head(read)

math = haven::read_sav("Data/Raw/2000/sav/intstud_math.sav")
head(math)

list_data = list(
  scie = scie,
  read = read,
  math = math
)

v = list_data %>% 
  lapply(colnames) %>% 
  gplots::venn()

v

common_cols = list_data %>% 
  lapply(colnames) %>% 
  Reduce(intersect, .)

scie_sub = scie %>% 
  dplyr::select(one_of(common_cols),
                pv1scie,
                w_fstuwt)


read_sub = read %>% 
  dplyr::select(one_of(common_cols),
                pv1read)

math_sub = math %>% 
  dplyr::select(one_of(common_cols),
                pv1math)

pisa_2000_raw = left_join(
  scie_sub, 
  read_sub, 
  by = common_cols) %>% 
  left_join(math_sub,
            by = common_cols)

pisa_2000_raw %>% write_csv(path = "Data/Raw/2000/pisa_2000_raw.csv")

pisa_2000 = pisa_2000_raw %>% 
  dplyr::select(
    COUNTRY, # id columns
    SCHOOLID, # id columns
    STIDSTD, # id columns
    ST03Q01, #
    ST22Q04,
    ST21Q04,
    pv1math,
    pv1read,
    pv1scie,
    w_fstuwt) %>% 
  dplyr::rename(student_id = STIDSTD,
                stu_wgt = w_fstuwt,
                country = COUNTRY,
                school_id = SCHOOLID,
                gender = ST03Q01,
                computer = ST22Q04,
                internet = ST21Q04,
                math = pv1math,
                science = pv1scie,
                read = pv1read)

pryr::object_size(pisa_2000)

readr::write_rds(pisa_2000, path = "Data/Output/2000/pisa_2000.rds")
