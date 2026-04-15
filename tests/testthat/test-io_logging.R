
test_that("safe_save_rds performs silent saves explicitly overwriting identical arrays mapping cleanly", {
  temp_rds <- tempfile("testsave_", fileext = ".rds")
  
  df <- data.frame(A = 1:5, B = letters[1:5])
  
  # First save (File doesn't exist)
  expect_message(safe_save_rds(df, temp_rds))
  expect_true(file.exists(temp_rds))
  
  # Second save (File exists, but matches identical dimensions/values!)
  expect_message(safe_save_rds(df, temp_rds))
  
  unlink(temp_rds)
})
