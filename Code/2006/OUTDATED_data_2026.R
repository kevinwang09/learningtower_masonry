# Download data files from 
# https://www.oecd.org/pisa/pisaproducts/INT_Stu06_Dec07.zip. (151Mb)
# https://www.oecd.org/pisa/pisaproducts/INT_Sch06_Dec07.zip 

# Download SPSS control files from
# https://www.oecd.org/pisa/pisaproducts/PISA2006_SPSS_student.txt
# https://www.oecd.org/pisa/pisaproducts/PISA2006_SPSS_school.txt

# Brute force text conversion
library(tidyverse)

# Extract just the rows of the SPSS control file with the data format
stu_format <- read.table("stu_script.sps") # skip and n don't seem to work
var_widths <- stu_format %>% 
  mutate(widths = as.numeric(V4) - as.numeric(V2) + 1, names = V1) 
d <- read_fwf(file="INT_Stu06_Dec07.txt", 
              col_positions=fwf_widths(var_widths$widths, 
                                       col_names=var_widths$names))
# Save data to csv
write_csv(d, path="pisa_student_2006.csv")

# Check it reads in ok
d <- read_csv("pisa_2006.csv")

# Generate subset for learningtower package
stu_qqq <- d %>%
  select("COUNTRY", "CNT", "SCHOOLID", "STIDSTD", 
         "ST06Q01", "ST09Q01", "ST04Q01", "ST13Q04",
         "ST13Q06", "PV1MATH", "PV1READ", "PV1SCIE", "W_FSTUWT",
         "ST13Q01", "ST13Q02", "ST13Q13", "ST14Q02", "ST14Q03", 
         "ST14Q04", "ST15Q01", "WEALTH", "ESCS")
save(stu_qqq, file="stu_qqq.rda")

# School
sch_format <- read.table("sch_script.sps") # skip and n don't seem to work
var_widths <- sch_format %>% 
  mutate(widths = as.numeric(V4) - as.numeric(V2) + 1, names = V1) 
d_sch <- read_fwf(file="INT_Sch06_Dec07.zip", 
              col_positions=fwf_widths(var_widths$widths, 
                                       col_names=var_widths$names))
write_csv(d_sch, path="pisa__school_2006.csv")

# Generate subset
sch_qqq <- d_sch %>%
  select("COUNTRY", "CNT", "SCHOOLID", "SC03Q01", 
         "SC03Q02", "SC03Q03", "SC01Q01", "SC01Q02",
         "STRATIO", "SC02Q01", "TCSHORT", "W_FSCHWT", "SCHSIZE")
save(sch_qqq, file="sch_qqq.rda")
