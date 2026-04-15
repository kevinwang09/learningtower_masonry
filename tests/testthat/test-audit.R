test_that("audit_dataframes evaluates simple structural changes appropriately intercepting warnings without terminating the core process natively", {
  df_new <- data.frame(A = 1:5, B = c("a", "b", "c", "d", "e"))
  df_old <- data.frame(A = 1:5, B = c("a", "b", "X", "d", "e"))
  
  # Audit just prints to console natively generating standard message streams
  expect_message(
    audit_dataframes(df_new, df_old),
    "differ" # We expect the string differ to be outputted in standard diagnostics message warning
  )
})
