library(tidyverse)

(stu_control <- read_table("Data/Raw/2003/PISA2003_SPSS_student.txt", skip = 7,
                          col_names = c("raw")) %>%
    slice(1:404) %>%
    tidyr::separate(col = raw,
                    into = c("colnames", "span1", "dash", "span2", "note"),
                    sep = "\\s+"))

(var_widths <- stu_control %>%
    mutate(widths = as.numeric(span2) - as.numeric(span1) + 1, 
           names = colnames))

d_stu <- read_fwf(file="Data/Raw/2003/INT_stui_2003_v2.zip", 
                  col_positions = fwf_widths(var_widths$widths, 
                                             col_names = as.character(var_widths$names)))

stu_qqq <- d_stu %>% 
  transmute(country_iso3c = CNT,
         school_id = SCHOOLID ,
         student_id = STIDSTD,
         mother_educ = ST11R01,
         father_educ = ST13R01,
         gender = ST03Q01,
         computer = ST17Q04,
         internet = ST17Q06,
         math = PV1MATH,
         read = PV1READ,
         science = PV1SCIE,
         stu_wgt = W_FSTUWT,
         desk = ST17Q01,
         room = ST17Q02,
         dishwasher = ST17Q13 ,
         television = NA_character_,
         computer_n = NA_character_ ,
         car = NA_character_,
         book = ST19Q01,
         wealth = NA_real_,
         escs = ESCS)

saveRDS(stu_qqq, file = "Data/Output/2003/stu_qqq.rds")
