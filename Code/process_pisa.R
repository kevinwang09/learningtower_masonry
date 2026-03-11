library(tidyverse)
library(haven)
library(here)
library(dplyr)

# -------------------------------------------------------------------------
# Logging Utilities
# -------------------------------------------------------------------------
#' Starts transparent logging, saving stdout and stderr to a log file
#' @param target_dir Optional. Directory to save log in. Auto-detected if NULL.
#' @param script_path Optional override for the script name. Auto-detected if NULL.
start_logging <- function(target_dir = NULL, script_path = NULL) {
  if (is.null(script_path)) {
    cmd_args <- commandArgs(trailingOnly = FALSE)
    file_arg <- grep("^--file=", cmd_args, value = TRUE)
    if (length(file_arg) > 0) {
      script_path <- sub("^--file=", "", file_arg[1])
    } else {
      script_path <- "interactive_session.R"
      for (i in 1:sys.nframe()) {
        if (!is.null(sys.frame(i)$ofile)) {
          script_path <- sys.frame(i)$ofile
        }
      }
    }
  }
  
  prefix <- tools::file_path_sans_ext(basename(script_path))
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  log_filename <- sprintf("%s_%s.log", prefix, timestamp)
  
  if (is.null(target_dir)) {
    target_dir <- dirname(script_path)
    if (target_dir == "." || target_dir == "") {
      target_dir <- getwd()
    }
  }
  
  log_file_path <- file.path(target_dir, log_filename)
  options(current_log_file = log_file_path)
  
  sink(log_file_path, split = TRUE, append = TRUE)
  
  globalCallingHandlers(
    message = function(m) { 
      opts <- getOption("current_log_file")
      if (!is.null(opts)) {
        ts <- format(Sys.time(), "[%Y-%m-%d %H:%M:%S]")
        msg_clean <- sub("\\n$", "", m$message)
        cat(sprintf("%s INFO: %s\n", ts, msg_clean), file = opts, append = TRUE)
      }
    },
    warning = function(w) { 
      opts <- getOption("current_log_file")
      if (!is.null(opts)) {
        ts <- format(Sys.time(), "[%Y-%m-%d %H:%M:%S]")
        msg_clean <- sub("\\n$", "", w$message)
        cat(sprintf("%s WARNING: %s\n", ts, msg_clean), file = opts, append = TRUE)
      }
    },
    error   = function(e) { 
      opts <- getOption("current_log_file")
      if (!is.null(opts)) {
        ts <- format(Sys.time(), "[%Y-%m-%d %H:%M:%S]")
        msg_clean <- sub("\\n$", "", e$message)
        cat(sprintf("%s ERROR: %s\n", ts, msg_clean), file = opts, append = TRUE)
      }
    }
  )
  message(sprintf("Logging started natively. Writing output to: %s", log_file_path))
  return(invisible(log_file_path))
}

#' Stops logging
stop_logging <- function() {
  message(sprintf("Execution finished at %s", Sys.time()))
  message("\n--- R Environment & Package Information ---")
  message(paste(capture.output(sessionInfo()), collapse = "\n"))
  message("-------------------------------------------")
  sink()
  options(current_log_file = NULL)
}

# -------------------------------------------------------------------------
# Audit Data Frames
# -------------------------------------------------------------------------
#' Audits two data frames and prints differences
#' @param df_new The new data frame to be saved
#' @param df_old The existing data frame loaded from disk
#' @return Boolean indicating if they are fully equal
audit_dataframes <- function(df_new, df_old) {
  message("\n==================================================")
  message("RDS Audit Tool")
  message("==================================================")
  
  if (!is.data.frame(df_new)) stop("New object is not a data frame.")
  if (!is.data.frame(df_old)) stop("Old object (from file) is not a data frame.")
  
  message("\n[1] Basic Dimensions")
  message(sprintf("  -> New Data: %d rows, %d columns", nrow(df_new), ncol(df_new)))
  message(sprintf("  -> Old Data: %d rows, %d columns", nrow(df_old), ncol(df_old)))
  
  if (nrow(df_new) != nrow(df_old)) {
      message("  -> WARNING: Row counts do not match!")
  }
  
  message("\n[2] Column Names Comparison")
  names_new <- names(df_new)
  names_old <- names(df_old)
  
  missing_in_old <- setdiff(names_new, names_old)
  missing_in_new <- setdiff(names_old, names_new)
  
  if (length(missing_in_old) == 0 && length(missing_in_new) == 0) {
    message("  -> SUCCESS: Both objects contain the exact same column names.")
  } else {
    if (length(missing_in_old) > 0) {
      message("  -> WARNING: Columns present in New Data but missing in Old Data:")
      message(paste("       -", missing_in_old, collapse = "\n"))
    }
    if (length(missing_in_new) > 0) {
      message("  -> WARNING: Columns present in Old Data but missing in New Data:")
      message(paste("       -", missing_in_new, collapse = "\n"))
    }
  }
  
  message("\n[3] Data Type Comparison (for matching columns)")
  common_cols <- intersect(names_new, names_old)
  type_diffs <- 0
  
  for (col in common_cols) {
    class_new <- class(df_new[[col]])[1] 
    class_old <- class(df_old[[col]])[1]
    
    if (class_new != class_old) {
      type_diffs <- type_diffs + 1
      if ((class_new == "numeric" && class_old == "haven_labelled") || 
          (class_new == "haven_labelled" && class_old == "numeric")) {
        message(sprintf("  -> INFO: %s differs slightly in 'haven' labelling: [New=%s | Old=%s]", col, class_new, class_old))
      } else {
        message(sprintf("  -> WARNING: Type mismatch in '%s': [New=%s | Old=%s]", col, class_new, class_old))
      }
    }
  }
  
  if (type_diffs == 0) {
    message("  -> SUCCESS: All matched columns have identical primary data classes.")
  } else {
    message(sprintf("  -> Found %d column class discrepancies.", type_diffs))
  }
  
  message("\n[4] Comprehensive all.equal() Check")
  
  # Strip attributes for haven_labelled columns before all.equal check
  df_new_compare <- df_new
  df_old_compare <- df_old
  
  for (col in common_cols) {
    if (inherits(df_new[[col]], "haven_labelled") || inherits(df_old[[col]], "haven_labelled")) {
      # Manual explicit value comparison for haven_labelled (safely handling NAs)
      val_match <- isTRUE(all((df_new[[col]] == df_old[[col]]) | (is.na(df_new[[col]]) & is.na(df_old[[col]]))))
      if (!val_match) {
        message(sprintf("  -> WARNING: Value mismatch explicitly found in column '%s'", col))
      }
      
      # Strip attributes down to base vectors to prevent all.equal() metadata failures
      df_new_compare[[col]] <- as.vector(df_new_compare[[col]])
      df_old_compare[[col]] <- as.vector(df_old_compare[[col]])
    }
  }
  
  equality_result <- all.equal(target=df_new_compare, current=df_old_compare)
  
  is_equal <- isTRUE(equality_result)
  
  if (is_equal) {
    message("  -> SUCCESS: all.equal() confirms the two data frames are exactly identical in content and attributes.")
  } else {
    message("  -> WARNING: all.equal() found differences between the data frames:")
    for (diff_msg in head(equality_result, n = 10)) {
      message(sprintf("       - %s", diff_msg))
    }
    if (length(equality_result) > 10) {
      message(sprintf("       ... and %d more differences.", length(equality_result) - 10))
    }
  }
  
  message("==================================================\n")
  return(is_equal)
}

# -------------------------------------------------------------------------
# Safe RDS Saving
# -------------------------------------------------------------------------
#' Safely overwrite an existing RDS file with verification
#' @param df The data frame to save
#' @param path The filepath to write to
safe_save_rds <- function(df, path) {
  # If file doesn't exist, just save it
  if (!file.exists(path)) {
    message(sprintf("File '%s' does not exist yet. Saving new RDS.", path))
    saveRDS(df, file = path)
    return(invisible(TRUE))
  }
  
  # File exists, so we audit it
  message(sprintf("File '%s' already exists. Loading to audit changes...", path))
  old_df <- readRDS(path)
  
  is_equal <- audit_dataframes(df_new = df, df_old = old_df)
  
  if (is_equal) {
    message("Audit passed (data frames are functionally identical). Overwriting RDS file with new output.")
    saveRDS(df, file = path)
    return(invisible(TRUE))
  } else {
    # If interactive R session (RStudio, interactive shell), prompt with readline
    if (interactive()) {
      ans <- readline(prompt = sprintf("\nWARNING: The data frame you are trying to save differs from the existing RDS file at '%s'.\nAre you sure you want to overwrite it? Type 'YES' to confirm: ", path))
    } else {
      # Fallback for standard script environments
      cat(sprintf("\nWARNING: The data frame you are trying to save differs from the existing RDS file at '%s'.\n", path))
      cat("Are you sure you want to overwrite it? Type 'YES' to confirm: ")
      ans <- readLines("stdin", n = 1)
    }
    
    if (!is.na(ans) && trimws(ans) == "YES") {
      message("User confirmed. Overwriting RDS file.")
      saveRDS(df, file = path)
      return(invisible(TRUE))
    } else {
      message("Overwrite aborted. Data was not saved.")
      return(invisible(FALSE))
    }
  }
}


# -------------------------------------------------------------------------
# Part 1: Raw Data Extraction
# -------------------------------------------------------------------------
#' Extract PISA Source Columns Truthfully
#'
#' Reads the mapping CSV for a specific year, identifies all required source columns 
#' (handling space-separated multi-columns like derivations), and cleanly extracts 
#' them from the raw `.sav` dataframe without renaming them.
#' 
#' @param target_year The study year (e.g., 2022) as a numeric
#' @param df The raw dataframe loaded from '.sav' file
#' @param mapping_csv_path The filepath to the schema CSV
#' 
#' @return A dataframe containing purely the required raw source columns
extract_raw_pisa <- function(target_year, df, mapping_csv_path) {
  
  message(sprintf("\n[Extraction] Reading raw variables and standardizing names for %s...", target_year))
  schema <- read_csv(mapping_csv_path, show_col_types = FALSE)
  
  if (!target_year %in% schema$year) {
    stop(paste("Year", target_year, "not found in the schema file."))
  }
  
  year_mapping <- schema %>% 
    filter(year == target_year) %>%
    filter(!is.na(target_name) & target_name != "")
  
  out_cols <- list()
  
  for (i in seq_len(nrow(year_mapping))) {
    target <- year_mapping$target_name[i]
    source_str <- year_mapping$source_col[i]
    
    # NA Placeholder handling
    if (is.na(source_str) || source_str %in% c("NA", "", "N/A")) {
       out_cols[[target]] <- rep(NA, nrow(df))
       message(sprintf("  -> mapped: %s (NA filler)", target))
       next
    }
    
    # Just take the exact variable name or the first if multiple are listed
    source_col_clean <- str_split(source_str, "\\s+")[[1]][1]
    
    if (source_col_clean %in% names(df)) {
        out_cols[[target]] <- df[[source_col_clean]]
        message(sprintf("  -> mapped: %s <- %s", target, source_col_clean))
    } else {
        warning(sprintf("Source column %s not found in raw data for target %s. Outputting NAs.", source_col_clean, target))
        out_cols[[target]] <- rep(NA, nrow(df))
        message(sprintf("  -> mapped: %s <- %s (MISSING IN RAW DATA)", target, source_col_clean))
    }
  }
  
  message("Binding standardized columns...")
  return(bind_cols(out_cols))
}

# -------------------------------------------------------------------------
# Part 2: Schema Transformations & Standardizations
# -------------------------------------------------------------------------
# Registry for string-based transformations
transformation_registry <- list(
  "as.character" = as.character,
  "as.numeric" = as.numeric,
  "as.integer" = as.integer,
  
  # Minimal factor placeholders
  "isced3a1" = function(x) { as.factor(x) },
  "fe1ma2" = function(x) { as.factor(x) },
  "yes1no2" = function(x) { as.factor(x) },
  "none1one2two3threemore4" = function(x) { as.factor(x) },
  "public_private" = function(x) { as.factor(x) },
  
  # Derived calculations for 2022
  "sum_computers" = function(df, cols) {
    rowSums(df %>% select(all_of(cols)), na.rm = TRUE)
  },
  "calc_stratio" = function(df, cols) {
    tot_stu <- df[[cols[1]]] + df[[cols[2]]]
    tot_tch <- df[[cols[3]]] + df[[cols[4]]]
    tot_stu / tot_tch
  },
  "calc_schsize" = function(df, cols) {
    df[[cols[1]]] + df[[cols[2]]]
  },
  "calc_staffshort" = function(df, cols) {
    tot_tch <- df[[cols[1]]] + df[[cols[2]]]
    cert_tch <- df[[cols[3]]] + df[[cols[4]]]
    1 - (cert_tch / tot_tch)
  }
)

#' Apply Transformations and Rename to Target
#'
#' Evaluates the extracted raw columns and standardizes them to their `target_name`,
#' computing derivations and applying typing logic.
#' 
#' @param target_year The study year (e.g., 2022)
#' @param df The extracted raw dataframe
#' @param mapping_csv_path Path to the variable mapping CSV
transform_pisa_variables <- function(target_year, df, mapping_csv_path) {
  
  message(sprintf("\n[Transformation] Standardizing names and transformations for %s...", target_year))
  schema <- read_csv(mapping_csv_path, show_col_types = FALSE) %>% filter(year == target_year)
  
  out_cols <- list()
  
  for (i in seq_len(nrow(schema))) {
    target <- schema$target_name[i]
    source_str <- schema$source_col[i]
    trans_str <- schema$transformation[i]
    
    # NA Placeholder handling
    if (is.na(source_str) || source_str %in% c("NA", "", "N/A")) {
       out_cols[[target]] <- rep(NA, nrow(df))
       message(sprintf("  -> mapped: %s (NA filler)", target))
       next
    }
    
    source_cols <- str_split(source_str, "\\s+")[[1]]
    avail_cols <- intersect(source_cols, names(df))
    
    if (length(avail_cols) == 0) {
       out_cols[[target]] <- rep(NA, nrow(df))
       message(sprintf("  -> mapped: %s (Source columns missing)", target))
       next
    }
    
    if (!is.na(trans_str) && trans_str %in% names(transformation_registry)) {
      func <- transformation_registry[[trans_str]]
      
      if (trans_str %in% c("sum_computers", "calc_stratio", "calc_schsize", "calc_staffshort")) {
        if (length(avail_cols) == length(source_cols)) {
          out_cols[[target]] <- func(df, source_cols)
        } else {
          out_cols[[target]] <- rep(NA, nrow(df))
        }
      } else {
        out_cols[[target]] <- func(df[[avail_cols[1]]])
      }
    } else {
      out_cols[[target]] <- df[[avail_cols[1]]]
    }
    
    message(sprintf("  -> mapped: %s <- %s [via %s]", target, paste(avail_cols, collapse=" "), ifelse(is.na(trans_str), 'none', trans_str)))
  }
  
  message("Binding final unified columns...")
  return(bind_cols(out_cols))
}
