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

escs = haven::read_sav("Data/Raw/2000/PISA2000_ESCS/ESCS_PISA2000.sav")
head(escs)

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
                cnt,
                pv1scie,
                w_fstuwt)


read_sub = read %>% 
  dplyr::select(one_of(common_cols),
                pv1read)

math_sub = math %>% 
  dplyr::select(one_of(common_cols),
                pv1math)

escs_sub = escs %>% 
  dplyr::select(CNT,
                SCHOOLID,
                STIDSTD,
                ESCS)

pisa_2000_raw = left_join(
  scie_sub, 
  read_sub, 
  by = common_cols) %>% 
  left_join(math_sub,
            by = common_cols) %>% 
  left_join(escs_sub,
            by = c("cnt" = "CNT",
                   "SCHOOLID" = "SCHOOLID",
                   "STIDSTD" = "STIDSTD"))

stu_qqq = pisa_2000_raw %>% 
  dplyr::transmute(
    country_iso3c = cnt %>% as.character(),
    school_id = SCHOOLID %>% as.integer(), ## school id 
    student_id = STIDSTD %>% as.integer(), ## Student id
    mother_educ = NA_integer_, ## Missing in data
    father_educ = NA_integer_,
    gender = ST03Q01 %>% as.character(), ## Gender
    computer = NA_character_, ## Possession of computers
    internet = ST21Q04 %>% as.character(), ## Possession of internet
    math = pv1math %>% as.numeric(), ## Plausible value of maths
    read = pv1read %>% as.numeric(), ## Plausible value of read
    science = pv1scie %>% as.numeric(), ## Plausible value of science
    stu_wgt = w_fstuwt %>% as.numeric(), ## Final student weight
    desk = ST21Q07 %>% as.character(), ## Possession of desk
    room = ST21Q02 %>% as.character(), ## Possession of own room
    dishwasher = ST21Q01 %>% as.character(), ## Possession of dishwasher
    television = ST22Q02 %>% as.character() %>% as.integer(), ## Possession of TV
    computer_n = ST22Q04 %>% as.character() %>% as.integer(),
    car = ST22Q06 %>% as.character() %>% as.integer(), ## Possession of cars
    book = ST37Q01 %>% as.character() %>% as.integer(), ## Possession of number of books
    wealth = wealth %>% as.numeric(), ## family wealth
    escs = ESCS %>% as.numeric() ## Index of economic, social and cultural status
  ) 

pryr::object_size(stu_qqq)

saveRDS(stu_qqq, file = "Data/Output/2000/stu_qqq.rds")
