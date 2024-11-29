# Introduction

This is the code respository for curating the `learningtower` package in `R`. This package is currently available at <https://github.com/kevinwang09/learningtower> and via CRAN at <https://cran.r-project.org/web/packages/learningtower/index.html>.

The `learningtower` package contains a subset of the [PISA data published by OECD](https://www.oecd.org/pisa/data/). The data curated by OECD is very comprehensive but can be formidable for exploratory data analysis. The most intensive component of publishing the `learningtower` package is the curation of the triennial data to ensure consistency. This repository, `learningtower_masonry` is a repo that documents clearly how every data is curated from its raw form to a curated form. 

# Acknowledgment of authorship

+ This data was initially curated in OzUnconf 2019. The original contributors are Kevin Wang, Erika Siregar, Sarah Romanes, Kim Fitter, Giulio Valentino Dalla Riva, Di Cook and Nick Tierney.
  
+ This data was later curated by Priya Dingorkar, Guan Ru Chen and Shabarish from Monash University, under the supervision of Dr Kevin Wang and Professor Di Cook.


# Data structrure

It is important to recognise the structure of the PISA data being curated. Every 3 years, the PISA data is published with: 

+ Student questionnaire, typically named as "STU_QQQ.zip".
+ School questionnaire, typically named as "SCH_QQQ.zip".
+ Teacher questionnaire, typically named as "TCH_QQQ.zip".
+ "Code books", which are similar to data dictionaries. 

The questionnarie zip folders can contain data in either SAS or SPSS formats. Depending on the data specifications of that year, these data can be read by their respective proprietary software or through open-source `R` libraries. The code books are always in Excel file formats. 

**In the `learningtower` package we only curate**: 

1. Student data
2. School data
3. Country data

Since the list of countries do not differ significantly between the years, the student and school data are typically the ones that needs to be updated upon new publication of PISA data. 


## Workflow to cureate new data (updated: Nov 2024)

Please consult with either Kevin Wang or Di Cook about adding new data.

  - Download the raw data into `Data/Raw` folder. Raw data should be documented in `Data/download_urls.csv`. **Due to size constraints, the raw data were never committed to GitHub. You should set up the proper folder structures using .gitkeep.** See how this is done for previous years. 
  - Add new code books into the `codebook` folder.
  - Create a new Rmarkdown/Quarto to document how the raw data should be curated into a cleaned format that is ready to be used in the `R` package. This document should be added to the folder `Code/yyyy`. Consult how data curation is done for the previous years to ensure data consistency.
  - **CAUTION: we do not accept curation of new variables unless there are some fundamental changes in how PISA publishes their data**. Curate of new variables must be documented in [PISA Variables' Table](https://docs.google.com/spreadsheets/d/1yuwYUO3A9fBThuMFnTZaP_Bb8lD0TF5w7lPvoEo7HvU/edit?gid=0#gid=0){.uri}
  - The cleaned data should be saved in the `Data/Output/yyyy`. The student data should be named `stu_qqq.rds` and the school data should be named `sch_qqq.rds`. 
  - Update `Code/student_bind_rows.Rmd` and `Code/school_bind_rows.Rmd`. The updated data with all years binded together will be available at `Data/Output/student.rda` and `Data/Output/school.rda`.
  - Copy over the files to a forked copy of the `learningtower` package. Update relevant vignettes and scripts. 

# Miscellaneous issues

## Variable naming consistencies between different years

The main challenge that the contributors encountered was to ensure the consistency of variables between different years. For instance, the highest schooling of a student's mother was never recorded in 2000, but it was coded as "ST11R01" between the years 2003 to 2012 and "ST005Q01TA" between the years 2015 and 2018. These variables were manually curated by all contributors as a factor variable, "mother_educ", in the output data.

We created an online spreadsheet to document the change of variables between different years, please go to [PISA Variables' Table](https://github.com/kevinwang09/learningtower_masonry/raw/master/codebook/PISA_data_variables_2022_table.xlsx) for reference, and the Excel file is saved in `codebook` folder as well.

### Data issues in 2022

Several variables may be missing due to the reconstruction of questionnaires. For instance, a question regarding student's possession of desk is not recorded in 2022, but it was coded in previous questionnaires, hence these variables were manually curated by all masons as an character variable in the output data. Another important issue we faced is a missing variable `WEALTH`, this variable could be used to estimate a student's socioeconomic status. So for further related analysis or research, another variable called `ESCS` (economic, social and cultural status) is more suitable.

## Reading in SAS and SPSS data

PISA publishes data in both SAS and PRSS format for all survey years. Where possible, the `.sav` file was used to read in the published raw data. The only exception was in the year 2000, where `.sav` files were not published and instead, `.txt`files with SPSS scripts were published to allow for the creation of `.sav` files. In order to resolve this, we used the SPSS software to perform conversions of `.txt` files to `.sav` files.

## Identical school/student ID doesn't refer to the same school/student

It should be noted that it was possible for schools to receive the same school ID even within the same year. Consider the following example:

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

This means that the school ID is only unique within the year and the country. This means that the school ID is only unique within the year and the country. 
