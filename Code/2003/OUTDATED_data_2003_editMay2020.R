library(tidyverse)
library(haven)
stu_raw = haven::read_sav("Data/Raw/2003/student_2003.sav")

stu_qqq <- stu_raw %>% 
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

glimpse(stu_qqq)

saveRDS(stu_qqq, file = "Data/Output/2003/stu_qqq.rds")
#######################################################################
sch_raw = haven::read_sav("Data/Raw/2003/school_2003.sav")
sch_qqq = sch_raw %>% 
  dplyr::transmute(
    country = `COUNTRY`,
    country_iso3c = CNT,
    school_id = SCHOOLID,
    funding_gov = SC04Q01,
    funding_fees = SC04Q02,
    funding_donations = SC04Q03,
    enrolment_boys = SC02Q01,
    enrolment_girls = SC02Q02,
    student_teacher_ratio = STRATIO,
    public_private = SC03Q01,
    staff_shortage = TCSHORT,
    sch_wgt = SCWEIGHT,
    school_size = SCHLSIZE)

glimpse(sch_qqq)
saveRDS(sch_qqq, file = "Data/Output/2003/sch_qqq.rds")