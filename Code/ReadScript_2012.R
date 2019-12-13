
#----------------------------------------- ### STUDENT DATA ### ------------------------------

# 1) Download PISA2012_SPSS_student.txt from  "https://www.oecd.org/pisa/pisaproducts/pisa2012database-downloadabledata.htm" (Section, SPSS Syntax)
# 2) Download INT_STU12_DEC03.txt from same link, (Section, Data sets in TXT format (compressed))
# 3) Remove lines 1,2, 635-8762 from the SPSS Syntax file (make sure no blank lines at end). Save as "PISA2012_SPSS_student_altered.txt"
# 4) Run code below

# Brute force text conversion
library(tidyverse)
# Extract just the rows of the SPSS control file with the data format
sps_format <- read.table("Data/Raw/2012/PISA2012_SPSS_student_altered.txt") # skip and n don't seem to work
var_widths <- sps_format %>% 
  mutate(widths = as.numeric(V4) - as.numeric(V2) + 1, names = V1) 

d_stu <- read_fwf(file="Data/Raw/2012/INT_STU12_DEC03.txt", 
              col_positions = fwf_widths(var_widths$widths, 
                                         col_names = as.character(var_widths$names)))

stu_qqq <- d_stu %>% 
  select(CNT, 
         SCHOOLID, 
         StIDStd, 
         ST13Q01, 
         ST17Q01, 
         ST04Q01, 
         ST26Q04, 
         ST26Q06, 
         PV1MATH, 
         PV1READ, 
         PV1SCIE, 
         W_FSTUWT,
         ST26Q01,
         ST26Q02,
         ST26Q13,
         ST27Q02,
         ST27Q03,
         ST27Q04,
         ST28Q01,
         WEALTH,
         ESCS)


save(stu_qqq, file = "Data/Output/2012/stu_qqq.rda")


#----------------------------------------- ### SCHOOL DATA ### ------------------------------

# 1) Download PISA2012_SPSS_school.txt from  "https://www.oecd.org/pisa/pisaproducts/pisa2012database-downloadabledata.htm" (Section, SPSS Syntax)
# 2) Download INT_SQU12_DEC03.txt from same link, (Section, Data sets in TXT format (compressed))
# 3) Remove lines 1,2, 294-3125 from the SPSS Syntax file (make sure no blank lines at end). Save
# 4) Run code below

# Brute force text conversion
library(tidyverse)
# Extract just the rows of the SPSS control file with the data format
sps_format <- read.table("Data/Raw/2012/PISA2012_SPSS_school_altered.txt") # skip and n don't seem to work
var_widths <- sps_format %>% 
  mutate(widths = as.numeric(V4) - as.numeric(V2) + 1, names = V1) 

d_sch <- read_fwf(file="Data/Raw/2012/INT_SCQ12_DEC03.txt", 
              col_positions = fwf_widths(var_widths$widths, 
                                         col_names = as.character(var_widths$names)))

sch_qqq <- d_sch %>% 
  select(CNT, 
         SCHOOLID, 
         SC02Q01, 
         SC02Q02, 
         SC02Q03, 
         SC07Q01, 
         SC07Q02, 
         STRATIO, 
         SC01Q01, 
         TCSHORT, 
         W_FSCHWT, 
         SCHSIZE)


save(sch_qqq, file = "Data/Output/2012/sch_qqq.rda")
