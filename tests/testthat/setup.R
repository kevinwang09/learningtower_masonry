# Setup logic evaluated automatically by testthat prior to executing tests
suppressPackageStartupMessages({
  library(testthat)
  library(dplyr)
  library(stringr)
  library(readr)
  library(here)
})

# Source the primary pipeline script so its functions are instantiated within the test environment directly.
# This bypasses R-package encapsulation rules safely simulating a package namespace.
source(here("Code", "process_pisa.R"))
