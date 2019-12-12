# doesn't work
library(intsvy)
d <- pisa.select.merge(student.file="INT_Stu06_Dec07.txt", 
                       student= c("SCHOOLID", "School ID"))
# doesn't work

# doesn't work
devtools::install_github("lebebr01/SPSStoR")
library(SPSStoR)

# doesn't work
spss_to_r(file="PISA2006_SPSS_student.txt")
get_to_r("PISA2006_SPSS_student.txt")

# doesn't work - no SAS script file
library(SAScii)
read.SAScii("PISA2006_SPSS_student.txt")

# doesn't work
library(asciiSetupReader)
d <- read_ascii_setup("INT_Stu06_Dec07.txt", "PISA2006_SPSS_student.sps")

library(EdSurvey)
downloadPISA(".", years="2006")
d <- readPISA(".", countries="036")

# Brute force text conversion
library(tidyverse)
# Extract just the rows of the SPSS control file with the data format
sps_format <- read.table("spss_script.sps") # skip and n don't seem to work
var_widths <- sps_format %>% 
  mutate(widths = as.numeric(V4) - as.numeric(V2) + 1, names = V1) 
d <- read.fwf(file="INT_Stu06_Dec07.txt", 
              widths=var_widths$widths, 
              col.names=var_widths$names)
write_csv(d, path="pisa_2006.csv")

d2 <- read_csv("pisa_2006.csv")
