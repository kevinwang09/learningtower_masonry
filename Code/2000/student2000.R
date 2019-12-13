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

# pisa_2000_raw %>% write_csv(path = "Data/Raw/2000/pisa_2000_raw.csv")

stu_qqq = pisa_2000_raw %>% 
  dplyr::select(
    COUNTRY, ## country
    SCHOOLID, ## school id 
    STIDSTD, ## Student id
    ST03Q01, ## Gender
    ST22Q04, ## Possession of computers
    ST21Q04, ## Possession of internet
    pv1math, ## Plausible value of maths
    pv1read, ## Plausible value of read
    pv1scie, ## Plausible value of science
    w_fstuwt, ## Final student weight
    ST21Q07, ## Possession of desk
    ST21Q02, ## Possession of own room
    ST21Q01, ## Possession of dishwasher
    ST22Q02, ## Possession of TV
    ST22Q04, ## Possession of Computer
    ST22Q06, ## Possession of cars
    ST37Q01, ## Possession of number of books
    wealth ## family wealth
    ) %>% 
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

pryr::object_size(stu_qqq)

save(stu_qqq, file = "Data/Output/2000/stu_qqq.rda")
