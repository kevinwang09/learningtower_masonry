library(tidyverse)
library(haven)
library(here)
sch_qqq <- read_sav(here("/Data/Raw/2015/PUF_SPSS_COMBINED_CMB_SCH_QQQ.zip"),
                    col_select = c(CNT,
                                   CNTSCHID,
                                   SC016Q01TA, ## funding govt
                                   SC016Q02TA, ## funding student fees
                                   SC016Q03TA, ## funding benefactors
                                   SC002Q01TA, ## num boys
                                   SC002Q02TA, ## num girls
                                   STRATIO,
                                   SC013Q01TA, ## public of private
                                   STAFFSHORT,
                                   W_SCHGRNRABWT,
                                   SCHSIZE))

# School questionnaire data file
saveRDS(sch_qqq,file=here("/Data/Output/2015/sch_qqq.rds"))
