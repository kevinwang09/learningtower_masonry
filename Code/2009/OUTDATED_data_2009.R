library(tidyverse)

(stu_format <- read_table("Data/Raw/2009/PISA2009_SPSS_student.txt", skip = 6,
                          col_names = c("raw")) %>%
    slice(1:437) %>%
    tidyr::separate(col = raw,
                    into = c("colnames", "span1", "dash", "span2", "note"),
                    sep = "\\s+"))

(var_widths <- stu_format %>%
  mutate(widths = as.numeric(span2) - as.numeric(span1) + 1, 
         names = colnames))

d_stu <- read_fwf(file="Data/Raw/2009/INT_STQ09_DEC11.zip", 
                  col_positions = fwf_widths(var_widths$widths, 
                                             col_names = as.character(var_widths$names)))

stu_qqq <- d_stu %>% 
  select(country_iso3c = CNT,
         school_id = SCHOOLID ,
         student_id = StIDStd,
         mother_educ = ST10Q01,
         father_educ = ST14Q01,
         gender = ST04Q01,
         computer = ST20Q04,
         internet = ST20Q06,
         math = PV1MATH,
         read = PV1READ,
         science = PV1SCIE,
         stu_wgt = W_FSTUWT,
         desk = ST20Q01,
         room = ST20Q02,
         dishwasher = ST20Q13 ,
         television = ST21Q02,
         computer_n = ST21Q03 ,
         car = ST21Q04,
         book = ST22Q01,
         wealth = WEALTH,
         escs = ESCS)


###############
(sch_format <- read_table("Data/Raw/2009/PISA2009_SPSS_school.txt", skip = 6,
                          col_names = c("raw")) %>%
   slice(1:247) %>%
   tidyr::separate(col = raw,
                   into = c("colnames", "span1", "dash", "span2", "note"),
                   sep = "\\s+"))

(var_widths <- sch_format %>%
    mutate(widths = as.numeric(span2) - as.numeric(span1) + 1, 
           names = colnames))

d_sch <- read_fwf(file="Data/Raw/2009/INT_SCQ09_Dec11.zip", 
                  col_positions = fwf_widths(var_widths$widths, 
                                             col_names = as.character(var_widths$names)))

sch_qqq <- d_sch %>% 
  select(country = CNT,
         school_id = SCHOOLID,
         fund_gov = SC03Q01,
         fund_fees = SC03Q02,
         fund_donation = SC03Q03,
         enrol_boys = SC06Q01,
         enrol_girls = SC06Q02,
         stratio = STRATIO,
         public_private = SC02Q01,
         staff_shortage = TCSHORT,
         sch_wgt = W_FSCHWT,
         school_size = SCHSIZE)


saveRDS(sch_qqq, file = "Data/Output/2009/sch_qqq.rds")
