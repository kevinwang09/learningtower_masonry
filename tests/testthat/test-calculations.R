test_that("sum_computers algorithm evaluates row sums dynamically handling NAs", {
  df <- data.frame(
    ST254Q02JA = c(1, 2, NA, NA),
    ST254Q03JA = c(2, NA, 3, NA)
  )
  
  res <- transformation_registry[["sum_computers"]](df, c("ST254Q02JA", "ST254Q03JA"))
  
  # Note: rowSums(x, na.rm=TRUE) evaluates c(NA, NA) to 0. 
  expect_equal(res, c(3, 2, 3, 0))
})

test_that("calc_stratio computes teacher to student ratio", {
  df <- data.frame(
    St1 = c(10, 20, NA), St2 = c(5, 5, 20),
    Tch1 = c(2, 4, NA), Tch2 = c(1, 1, NA)
  )
  
  res <- transformation_registry[["calc_stratio"]](df, c("St1", "St2", "Tch1", "Tch2"))
  
  # res = (St1 + St2) / (Tch1 + Tch2) -> c(15/3, 25/5, NA)
  expect_equal(res, c(5, 5, NA))
})

test_that("calc_schsize evaluates total student populations", {
  df <- data.frame(St1 = c(100, 200, NA), St2 = c(50, 50, 10))
  
  res <- transformation_registry[["calc_schsize"]](df, c("St1", "St2"))
  # Note: Direct addition (St1 + St2) natively returns NA if one is NA.
  expect_equal(res, c(150, 250, NA))
})

test_that("calc_staffshort computes certification shortages correctly", {
  df <- data.frame(
    Tch1 = c(10, 20, NA), Tch2 = c(0,  5, NA),
    Cert1 = c(8, 15, NA), Cert2 = c(0, 5, NA)
  )
  
  # Format structure: tot_tch, cert_tch
  # cols: Tch1, Tch2, Cert1, Cert2
  res <- transformation_registry[["calc_staffshort"]](df, c("Tch1", "Tch2", "Cert1", "Cert2"))
  
  # short = 1 - (Cert1+Cert2)/(Tch1+Tch2)
  # row 1: 1 - (8/10) = 0.2
  # row 2: 1 - (20/25) = 1 - 0.8 = 0.2
  expect_equal(res, c(0.2, 0.2, NA))
})
