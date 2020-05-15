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

