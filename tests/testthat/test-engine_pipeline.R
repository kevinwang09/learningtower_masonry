library(dplyr)

test_that("extract_raw_pisa extracts exact column subsets safely dropping arbitrary subsets", {
  mock_schema <- tempfile(fileext = ".csv")
  
  writeLines(c(
    "year,target_name,source_col,transformation,na_values,description,type,notes",
    "2000,gender,GENDER_RAW,fe1ma2,,Gender,factor,",
    "2000,combined,VAR_A VAR_B,sum_computers,,Combined,numeric,"
  ), mock_schema)
  
  df_input <- data.frame(
    GENDER_RAW = c(1, 2),
    VAR_A = c(10, 20),
    VAR_B = c(5, 5),
    EXTRA_IGNORE = c(99, 99)
  )
  
  res <- extract_raw_pisa(2000, df_input, mock_schema)
  
  # extract_raw_pisa drops arbitrary subsets.
  expect_false("EXTRA_IGNORE" %in% names(res))
  # It automatically extracts the first space-separated mapping and renames it dynamically to the target!
  expect_true("combined" %in% names(res))
  expect_false("VAR_A" %in% names(res))
  expect_false("VAR_B" %in% names(res))
  # For single columns, it dynamically renames it exactly to the target immediately prior to saving.
  expect_true("gender" %in% names(res))
  
  unlink(mock_schema)
})

test_that("transform_pisa_variables translates targets gracefully generating NAs when variables go missing", {
  mock_schema <- tempfile(fileext = ".csv")
  
  writeLines(c(
    "year,target_name,source_col,transformation,na_values,description,type,notes",
    "2000,gender,GENDER_RAW,fe1ma2,,Gender,factor,",
    "2000,age,AGE_RAW,as.numeric,99,Age,numeric,",
    "2000,missing_col,,as.numeric,,Fake,numeric,",
    "2000,country,COUNTRY,as.character,,Country,character,",
    "2000,school_id,SCHOOL,as.character,,School,character,",
    "2000,student_id,STUDENT,as.character,,Student,character,"
  ), mock_schema)
  
  df_input <- data.frame(
    gender = c(1, 2, NA, 3),    # Already renamed by extract_raw_pisa!
    age = c(15, 16, 99, NA),
    country = c("USA", "USA", "USA", "USA"),
    school_id = c("1", "1", "2", "3"),
    student_id = c("A", "B", "C", "D"),
    dummy_col = c(NA, NA, NA, NA)
  )
  
  res <- transform_pisa_variables(2000, df_input, mock_schema)
  
  expect_true("gender" %in% names(res))
  expect_equal(as.character(res$gender), c("female", "male", NA, NA))
  
  expect_true("age" %in% names(res))
  # The NA rules mask 99 successfully!
  expect_equal(res$age, c(15, 16, NA, NA))
  
  expect_true("missing_col" %in% names(res))
  expect_true(all(is.na(res$missing_col)))
  
  # Checks primary keys propagate without duplicating
  expect_equal(nrow(res), 4)
  
  unlink(mock_schema)
})
