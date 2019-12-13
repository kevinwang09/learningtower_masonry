# Brute force text conversion
library(tidyverse)

school = haven::read_sav("Data/Raw/2000/sav/intscho.sav")
head(school)


sch_qqq = school %>% 
  dplyr::select(
    country, ## Country 3 digits
    cnt, ## Country 3 char
    schoolid, ## School id
    sc04q01, ## funding govt
    sc04q02, ## funding student fees
    sc04q03, ## funding benefactors
    sc02q01, ## Number of boys
    sc02q02, ## Number of girls
    stratio, ## School size to teacher ratios 
    sc03q01, ## School is public or private
    tcshort, ## Teacher shortage
    wnrschbw, ## School weight
    schlsize ## School size
    )

save(sch_qqq, file = "Data/Output/2000/sch_qqq.rda")