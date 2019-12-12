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

scie = haven::read_sav("Data/Raw/2000/intstud_scie.sav")
head(scie)

read = haven::read_sav("Data/Raw/2000/intstud_read.sav")
head(read)

math = haven::read_sav("Data/Raw/2000/intstud_math.sav")
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

scie_sub = scie %>% 
  dplyr::select(COUNTRY,
                SCHOOLID,
                STIDSTD,
                ST03Q01,
                ST22Q04,
                ST21Q04,
                pv1scie,
                w_fstuwt)


read_sub = read %>% 
  dplyr::select(COUNTRY,
                SCHOOLID,
                STIDSTD,
                pv1read)

math_sub = math %>% 
  dplyr::select(COUNTRY,
                SCHOOLID,
                STIDSTD,
                pv1math)

joined_data = left_join(
  scie_sub, 
  read_sub, 
  by = c("COUNTRY",
         "SCHOOLID",
         "STIDSTD")) %>% 
  left_join(math_sub,
            by = c("COUNTRY",
                   "SCHOOLID",
                   "STIDSTD"))


joined_data
pryr::object_size(joined_data)
data2000 = joined_data
save(
  data2000, 
  file = "Data/Output/2000/data2000.rda"
)
