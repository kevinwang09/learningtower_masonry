test_that("parse_spss_syntax successfully resolves names and widths from fixed format blocks", {
  tmp <- tempfile(fileext = ".txt")
  writeLines(c(
    "DATA LIST FILE='mock.dat' /",
    "  STUDENT_ID 1-4",
    "  AGE 5-6 (A)",
    "  GENDER 7",
    "VALUE LABELS etc"
  ), tmp)
  
  res <- parse_spss_syntax(tmp)
  
  expect_equal(nrow(res), 3)
  expect_equal(res$names, c("STUDENT_ID", "AGE", "GENDER"))
  expect_equal(res$start, c(1, 5, 7))
  expect_equal(res$widths, c(4, 2, 1))
  
  unlink(tmp)
})

test_that("parse_spss_value_labels extracts variable/value dictionaries dynamically slicing across slash domains", {
  tmp <- tempfile(fileext = ".txt")
  writeLines(c(
    "VALUE LABELS",
    "  GENDER 1 \"Female\" 2 \"Male\" /",
    "  BOOK_VAR \"A\" \"0-10\" \"B\" \"11-20\" /",
    "EXECUTE."
  ), tmp)
  
  res <- parse_spss_value_labels(tmp)
  
  expect_equal(nrow(res), 4)
  expect_equal(res$variables, c("GENDER", "GENDER", "BOOK_VAR", "BOOK_VAR"))
  expect_equal(res$value, c("1", "2", "A", "B"))
  expect_equal(res$label, c("Female", "Male", "0-10", "11-20"))
  
  unlink(tmp)
})
