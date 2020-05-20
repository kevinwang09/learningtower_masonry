library(tidyverse)
library(haven)
library(here)
sch_qqq <- read_sav(here("/Data/Raw/2015/PUF_SPSS_COMBINED_CMB_SCH_QQQ.zip"),
                    col_select = c(CNT,
                                   CNTSCHID,
                                   SC016Q01TA,
                                   SC016Q02TA,
                                   SC016Q03TA,
                                   SC002Q01TA,
                                   SC002Q02TA,
                                   SC002Q02TA,
                                   STRATIO,
                                   SC013Q01TA,
                                   STAFFSHORT,
                                   W_SCHGRNRABWT,
                                   SCHSIZE))

# School questionnaire data file
saveRDS(sch_qqq,file=here("/Data/Output/2015/sch_qqq.rds"))
