####    Create PISA data

#   The following create.pisa() function enables creation of entire PISA 2003, 2006, 2009, abd 2012 student data sets in the R environment

#  the spss Control file contains the column width for each each variable.  This information is required to read the data file, using the read_fwf function
#     Only the first chunk of variables (set ending with '.') in the Control file are required

#   Users must first download the spss Control and data files (both .txt files) from the OECD website
#   https://www.oecd.org/pisa/data/

# NOTE:   Use the 'haven' package to pull in 2015 and 2018 data sets.
#       For school data, the create.PISA function will generally work, but small tweaks to input data may be required.

#   In the function, enter the year, spss Control and data files as '  .txt' format

#

library('tidyverse')


create.PISA <- function(year, spssControl, dataFile){

                  #Relevant data in each year's control file starts on different rows.

                  if (year == '2003') {skiprow <- 7}
                  if (year == '2006') {skiprow <- 9}
                  if (year == '2009') {skiprow <- 6}
                  if (year == '2012') {skiprow <- 3}

                  #Reads spssControl file to determine column widths


                  varwidths.RAW <- read.table(spssControl, skip = skiprow, fill=T, stringsAsFactors = F) #read in raw spss Control file

                      end.indexs <-  varwidths.RAW[varwidths.RAW$V1 == '.',]  #determines all data chunks end points

                      end.index1 <- as.numeric(row.names(end.indexs)[1]) - 1   #pulls row number for end of first/relevant data chunk

                      sps_format <- varwidths.RAW[1:end.index1,] #subsets varwidth data for only relevant rows

                  var_widths <- sps_format %>%
                                   mutate(widths = as.numeric(V4) - as.numeric(V2) + 1, names = V1)  #variable width is the end - beginning + 1

                  #Based on var_widths$widths values, assigns fixed width columns
                  #       for each variable in the data table.

                  data1 <- read_fwf(file          =  dataFile,
                                 col_types     =  cols(.default = col_character()),  # use .defaul = col_character() to read all columns as type character
                                 col_positions =  fwf_widths(var_widths$widths,
                                                             col_names     =  as.character(var_widths$names)))
                  return(data1)

}


getwd()

data <- create.PISA(year = '2003', spssControl ='PISA2003_SPSS_student_py.txt', dataFile = 'INT_stui_2003_v2.txt')
View(data)

varsStu <- c('/COUNTRY',
             'CNT',
             'SCHOOLID',
             'STIDSTD',
             'ST11R01',
             'ST13R01',
             'ST03Q01',
             'ST17Q03',
             'ST17Q06',
             'PV1MATH',
             'PV1READ',
             'PV1SCIE',
             'W_FSTUWT',
             'ST17Q01',
             'ST17Q02',
             'ST17Q13',
             'ST19Q01',
             'ESCS'); length(varsStu)

data1 <- data[varsStu]


varNameSt <- c('country',
                   'country_iso3c',
                   'school_id',
                   'student_id',
                   'mother_educ',
                   'father_educ',
                   'gender',
                   'computer',
                   'internet',
                   'math',
                   'read',
                   'science',
                   'stu_wgt',
                   'desk',
                   'room',
                   'dishwasher',
                   'book',
                   'escs'
)

 #length(varNameSt)
names(data1) <- varNameSt

data1$television <- NA
data1$computer_n <- NA
data1$car <- NA
data1$wealth <- NA

View(data1)


saveRDS(data1, file = "PISAstudent_2003.rds")




#### SCHOOL DATA



data <- create.PISA(year = '2003', spssControl ='PISA2003_SPSS_school.txt', dataFile = 'INT_schi_2003.txt')




varsSchool <- c('/COUNTRY',
                'CNT',
                'SCHOOLID',
                'SC04Q01',
                'SC04Q02',
                'SC04Q03',
                'SC02Q01',
                'SC02Q02',
                'STRATIO',
                'SC03Q01',
                'TCSHORT',
                'SCWEIGHT',
                'SCHLSIZE'

)



View(data)

data1 <- data[varsSchool]

varNamesSL <- c('country',
                'country_iso3c',
                'school_id',
                'funding_gov',
                'funding_fees',
                'funding_donations',
                'enrolment_boys',
                'enrolment_girls',
                'student_teacher_ratio',
                'public_private',
                'staff_shortage',
                'sch_wgt',
                'school_size'
)

names(data1) <- varNamesSL

View(data1)

saveRDS(data1, file = "PISAschool_2003.rds")


