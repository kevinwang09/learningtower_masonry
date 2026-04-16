test_that("isced3a1 handles education mapping properly", {
  input <- c(1, 2, 3, 4, 5, 9, NA)
  res <- isced3a1(input)
  
  expect_equal(as.character(res[1]), "ISCED 3A")
  expect_equal(as.character(res[2]), "ISCED 3B, C")
  expect_equal(as.character(res[5]), "less than ISCED1")
  
  # Ensure invalid integers and NA both gracefully fall to NA
  expect_true(is.na(res[6]))
  expect_true(is.na(res[7]))
  expect_s3_class(res, "factor")
})

test_that("iscednone1 handles education mapping properly", {
  input <- c(1, 2, 3, 4, 5, 9, NA)
  res <- iscednone1(input)
  
  expect_equal(as.character(res[1]), "less than ISCED1")
  expect_equal(as.character(res[3]), "ISCED 2")
  expect_equal(as.character(res[5]), "ISCED 3A")
  
  expect_true(is.na(res[6]))
  expect_true(is.na(res[7]))
  expect_s3_class(res, "factor")
})

test_that("fe1ma2 handles gender conversion", {
  input <- c(1, 2, 3, NA)
  res <- fe1ma2(input)
  
  expect_equal(as.character(res[1]), "female")
  expect_equal(as.character(res[2]), "male")
  expect_true(is.na(res[3]))
  expect_true(is.na(res[4]))
  expect_s3_class(res, "factor")
})

test_that("yes1no2 handles binary possession conversion", {
  res <- yes1no2(c(1, 2, 9, NA))
  expect_equal(as.character(res), c("yes", "no", NA, NA))
  expect_s3_class(res, "factor")
})

test_that("none1one2two3threemore4 handles quantities reliably", {
  res <- none1one2two3threemore4(c(1, 2, 3, 4, 5, NA))
  expect_equal(as.character(res), c("0", "1", "2", "3+", NA, NA))
  expect_s3_class(res, "factor")
})

test_that("public_private handles conversion", {
  res <- public_private(c(1, 2, 9, NA))
  expect_equal(as.character(res), c("public", "private", NA, NA))
  expect_s3_class(res, "factor")
})

test_that("book_levels_6 convert properly", {
  # 6 levels test
  res6 <- book_levels_6(c(1, 4, 6, NA))
  expect_equal(as.character(res6), c("0-10", "101-200", "More than 500", NA))
  expect_s3_class(res6, "factor")
})
