# Building the `learningtower` package from raw PISA data

We present `learningtower`, an `R` data package for the [PISA data published by OECD](https://www.oecd.org/pisa/data/). 

The most intensive component of publishing this data is the curation of the triennial data to ensure consistency. This repository, `learningtower_masonry` is a repo that documents clearly how every data is curated from its raw form to a curated form. 


# Workflow in OzUnconf 2019

+ Every contributor for this package (henceforth referred to as "masons") was assigned with a particular year of the survey data. 
+ Raw data were downloaded in the `Data/Raw` folder (due to size constraints, the raw data were never commited to GitHub). 
+ Each mason is responsible for cleaning one survey data by writing appropriate scripts in the `Code/yyyy` folder, where `yyyy` is the year of the survey. 
+ The cleaned data are placed in the folder `Data/output/yyyy`. The data relating to the student is named `stu_qqq.rds`. The data relating to the school is named `sch_qqq.rds`.

## Consistencies between different years

One important problem that the masons encountered was to ensure the consistency of variables between different years. For instance, the highest schooling of a student's mother is never recorded in 2000, but it was coded as "ST11R01" between the years 2003 to 2012 and "ST005Q01TA" between the years 2015 and 2018. These variables were manually curated by all masons as an integer variable, "mother_educ", in the output data. 

## Reading in SAS and SPSS data

PISA publishes both a SAS and PRSS version of the data. Where possible, the `.sav` file is used to read in the published raw data. The only exception was in the year 2000, where `.sav` files were not published and instead, `.txt` files with SPSS scripts that are necessary to produce `.sav` files were published. In order to resolve this, we used the actual SPSS software to perform conversions of `.txt` files to `.sav` files. 

## Identical school/student ID doesn't refer to the same school/student

It should be noted that it is possible for schools to receive the same school ID even within the same year! Consider the following example:

``` r
load("~/Desktop/learningtower_masonry/Data/Output/student.rda")
library(tidyverse)

student %>% 
  group_by(year, country_iso3c, school_id) %>% 
  tally() %>% 
  filter(school_id == "1001")
#> # A tibble: 14 x 4
#> # Groups:   year, country_iso3c [14]
#>     year country_iso3c school_id     n
#>    <int> <fct>         <fct>     <int>
#>  1  2000 ALB           1001         19
#>  2  2000 CAN           1001         32
#>  3  2000 ESP           1001         20
#>  4  2000 FRA           1001         13
#>  5  2000 HUN           1001         19
#>  6  2000 ISR           1001         20
#>  7  2000 LUX           1001        157
#>  8  2000 NLD           1001         15
#>  9  2000 POL           1001         16
#> 10  2000 THA           1001         19
#> 11  2006 MEX           1001         25
#> 12  2006 THA           1001         34
#> 13  2006 KGZ           1001         33
#> 14  2006 LTU           1001         27
```
