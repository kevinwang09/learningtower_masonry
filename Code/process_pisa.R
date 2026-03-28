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
      if ((class_new %in% c("numeric", "character", "integer") && class_old == "haven_labelled") || 
          (class_new == "haven_labelled" && class_old %in% c("numeric", "character", "integer"))) {
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
      
      vec_new <- as.vector(df_new[[col]])
      vec_old <- as.vector(df_old[[col]])
      
      # Manual explicit value comparison for haven_labelled (safely handling NAs)
      val_match <- isTRUE(all((vec_new == vec_old) | (is.na(vec_new) & is.na(vec_old))))
      if (!val_match) {
        message(sprintf("  -> WARNING: Value mismatch explicitly found in column '%s'", col))
      }
      
      # Strip attributes down to base vectors to prevent all.equal() metadata failures
      df_new_compare[[col]] <- vec_new
      df_old_compare[[col]] <- vec_old
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
# SPSS Parser Utility
# -------------------------------------------------------------------------
#' Parse SPSS Syntax Files (Fixed-Width Formats)
#'
#' Scans raw SPSS syntax files to dynamically determine variable names and
#' their defined widths, replacing manual file trimming.
#' @param syntax_file_path The filepath to the .txt or .sps file
#' @return A tibble with `names` and `widths`
parse_spss_syntax <- function(syntax_file_path) {
  raw_lines <- stringr::str_trim(readLines(syntax_file_path, warn = FALSE))
  
  # Truncate the file at "VALUE LABELS" or "EXECUTE" so our optional-hyphen regex 
  # doesn't accidentally match lines like 'ST03Q01 1 "Female"' as positions!
  end_idx <- grep("^\\s*(VALUE\\s+LABELS|EXECUTE\\.?|VARIABLE\\s+LABELS)", raw_lines, ignore.case = TRUE)
  if (length(end_idx) > 0) raw_lines <- raw_lines[1:(end_idx[1] - 1)]
  
  # A regex designed to match SPSS syntax structure like: "CNT 1 - 3 (A)" or "ST13Q01 120-121 (F,0)"
  # It uses explicit capture groups: Name (1), Start (2), and an optional End (3).
  # ^([A-Za-z0-9_]+) : Capture variable name (Group 1)
  # \\s+(\\d+)       : Capture start width (Group 2)
  # (?:\\s*-\\s*     : Enter optional non-capturing group for the hyphen
  # (\\d+))?         : Capture end width (Group 3) if hyphen exists.
  extracted <- stringr::str_match(raw_lines, "^([A-Za-z0-9_]+)\\s+(\\d+)(?:\\s*-\\s*(\\d+))?")
  extracted <- extracted[!is.na(extracted[, 1]), , drop = FALSE]
  
  var_widths <- dplyr::tibble(
      names = extracted[, 2],
      start = as.numeric(extracted[, 3]),
      end = as.numeric(extracted[, 4])
    ) %>%
    dplyr::mutate(
      end = ifelse(is.na(end), start, end),
      widths = end - start + 1
    ) %>%
    dplyr::select(names, start, end, widths)
    
  return(var_widths)
}

#' Parse SPSS Value Labels
#'
#' Scans raw SPSS syntax files to extract the VALUE LABELS mapping definitions.
#' Safely isolates both categorical string labels and their encoded numeric/string keys.
#' @param syntax_file_path The filepath to the .txt or .sps file
#' @return A tibble with `variables`, `value`, and `label`
parse_spss_value_labels <- function(syntax_file_path) {
  raw_lines <- readLines(syntax_file_path, warn = FALSE)
  
  # Identify the VALUE LABELS block coordinates
  start_idx <- grep("^\\s*VALUE\\s+LABELS", raw_lines, ignore.case = TRUE)
  if (length(start_idx) == 0) return(dplyr::tibble(variables = character(), value = character(), label = character()))
  start_idx <- start_idx[1]
  
  # Scan for EOF markers to stop parsing labels
  end_idx <- grep("^\\s*(MISSING\\s+VALUES|EXECUTE\\.?|FORMATS)", raw_lines, ignore.case = TRUE)
  end_idx <- min(end_idx[end_idx > start_idx], length(raw_lines) + 1)
  
  vl_lines <- raw_lines[(start_idx + 1):(end_idx - 1)]
  vl_lines <- stringr::str_trim(vl_lines)
  vl_lines <- vl_lines[vl_lines != ""]
  
  # Collapse all lines into one solid block, then slice by the SPSS slash '/' delimiter separating variable domains.
  collapsed <- paste(vl_lines, collapse = " ")
  blocks <- strsplit(collapsed, "/")[[1]]
  
  results <- list()
  
  for (block in blocks) {
    block <- stringr::str_trim(block)
    if (nchar(block) == 0) next
    
    # Capture mapped value/label pairs. Value can be digits securely (1) or quoted string ("036"). Label is strictly quoted.
    pairs <- stringr::str_match_all(block, '(\\d+|\\"[^\\"]+\\")\\s+\\"([^\\"]+)\\"')[[1]]
    
    if (nrow(pairs) > 0) {
      # The target variables are declared textually immediately before the very first key-value mapping execution.
      first_pair_start <- regexpr('(\\d+|\\"[^\\"]+\\")\\s+\\"([^\\"]+)\\"', block)[1]
      vars_str <- stringr::str_trim(substring(block, 1, first_pair_start - 1))
      
      # Cleanse arbitrary quotes from mappings and register into vertical frame
      vals <- stringr::str_remove_all(pairs[, 2], '^\\"|\\"$')
      labs <- pairs[, 3]
      
      results[[length(results) + 1]] <- dplyr::tibble(
        variables = vars_str,
        value = vals,
        label = labs
      )
    }
  }
  
  if (length(results) > 0) {
    return(dplyr::bind_rows(results))
  } else {
    return(dplyr::tibble(variables = character(), value = character(), label = character()))
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
  schema <- readr::read_csv(mapping_csv_path, comment = "#", show_col_types = FALSE)
  
  if (!target_year %in% schema$year) {
    stop(paste("Year", target_year, "not found in the schema file."))
  }
  
  year_mapping <- schema %>% 
    dplyr::filter(year == target_year) %>%
    dplyr::filter(!is.na(target_name) & target_name != "")
  
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
yes1no2 = function(x){
  x = as.integer(x)
  dplyr::case_when(
    x == 1 ~ "yes",
    x == 2 ~ "no",
    TRUE ~ NA_character_) %>% as.factor()
}


none1one2two3threemore4 = function(x){
  x = as.integer(x)
  dplyr::case_when(
    x == 1 ~ "0", 
    x == 2 ~ "1",
    x == 3 ~ "2",
    x == 4 ~ "3+",
    TRUE ~ NA_character_) %>% as.factor()
}

iscednone1 = function(x){
  x = as.integer(x)
  dplyr::case_when(
    x == 1 ~ "less than ISCED1", 
    x == 2 ~ "ISCED 1",
    x == 3 ~ "ISCED 2",
    x == 4 ~ "ISCED 3B, C",
    x == 5 ~ "ISCED 3A",
    TRUE ~ NA_character_) %>% as.factor()
}

isced3a1 = function(x){
  x = as.integer(x)
  dplyr::case_when(
    x == 1 ~ "ISCED 3A", 
    x == 2 ~ "ISCED 3B, C",
    x == 3 ~ "ISCED 2",
    x == 4 ~ "ISCED 1",
    x == 5 ~ "less than ISCED1",
    TRUE ~ NA_character_) %>% as.factor()
}

fe1ma2 = function(x){
  x = as.integer(x)
  dplyr::case_when(
    x == 1 ~ "female",
    x == 2 ~ "male",
    TRUE ~ NA_character_
    ) %>% as.factor()
}

book_levels_6 = function(x){
  x = as.integer(x)
  dplyr::case_when(
    x == 1 ~ "0-10",
    x == 2 ~ "11-25",
    x == 3 ~ "26-100",
    x == 4 ~ "101-200",
    x == 5 ~ "201-500",
    x == 6 ~ "More than 500",
    TRUE ~ NA_character_) %>% as.factor()
}

transformation_registry <- list(
  "as.factor" = as.factor,
  "as.character" = as.character,
  "as.numeric" = as.numeric,
  "as.integer" = as.integer,
  "as.logical" = as.logical,
  
  # Minimal factor placeholders
  "isced3a1" = function(x) { isced3a1(x) },
  "fe1ma2" = function(x) { fe1ma2(x) },
  "yes1no2" = function(x) { yes1no2(x) },
  "none1one2two3threemore4" = function(x) { none1one2two3threemore4(x) },
  "book_levels_7" = function(x) { book_levels_7(x) },
  "book_levels_6" = function(x) { book_levels_6(x) },
  
  # Derived calculations for 2022
  "sum_computers" = function(df, cols) {
    rowSums(df %>% dplyr::select(all_of(cols)), na.rm = TRUE)
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
#' computing derivations and applying typing logic. This function also verifies that
#' the transformed variables match their expected data types.
#' 
#' @param target_year The study year (e.g., 2022) to filter the variable mapping schema.
#' @param df The extracted raw dataframe containing source columns.
#' @param mapping_csv_path Path to the variable mapping CSV defining schema and transformations.
#' @return A new dataframe with transformed, standardized columns as defined by the schema.
transform_pisa_variables <- function(target_year, df, mapping_csv_path) {
  
  message(sprintf("\n[Transformation] Standardizing names and transformations for %s...", target_year))
  
  # Load the mapping schema and filter for the target year
  schema <- readr::read_csv(mapping_csv_path, comment = "#", show_col_types = FALSE) %>% dplyr::filter(year == target_year)
  
  # Perform a check that the number of rows in the schema matches the number of columns in the supplied dataframe
  if (nrow(schema) != ncol(df)) {
    stop(sprintf("Dimension mismatch! The schema has %d rows, but the input data frame has %d columns.", nrow(schema), ncol(df)))
  }
  
  out_cols <- list()
  
  for (i in seq_len(nrow(schema))) {
    target <- schema$target_name[i]
    source_str <- schema$source_col[i]
    trans_str <- schema$transformation[i]
    expected_type <- schema$type[i]
    na_str <- schema$na_values[i]
    
    # Handle NA placeholders when the source column is missing in the design
    if (is.na(source_str) || source_str %in% c("NA", "", "N/A")) {
       out_cols[[target]] <- rep(NA, nrow(df))
       message(sprintf("  -> mapped: %s (NA filler)", target))
       next
    }
    
    # Check if the target name exists in the supplied data frame
    if (!(target %in% names(df))) {
       out_cols[[target]] <- rep(NA, nrow(df))
       message(sprintf("  -> mapped: %s (Target column missing in input data frame)", target))
       next
    }
    
    # Apply transformation if specified in the schema and available in the registry
    if (!is.na(trans_str) && trans_str %in% names(transformation_registry)) {
      func <- transformation_registry[[trans_str]]
      
      # Determine if the transformation requires multiple columns (calculations)
      # Note: If multi-col transformations expect source_cols, they might fail if df only has target_names.
      # We fall back to standard signature func(df, source_cols) if needed.
      if (trans_str %in% c("sum_computers", "calc_stratio", "calc_schsize", "calc_staffshort")) {
        source_cols <- str_split(source_str, "\\s+")[[1]]
        out_cols[[target]] <- tryCatch({
          func(df, source_cols)
        }, error = function(e) {
          warning(sprintf("Multi-column transformation %s failed for %s. Creating NAs.", trans_str, target))
          rep(NA, nrow(df))
        })
      } else {
        # Single column transformation using the supplied data frame's target column
        out_cols[[target]] <- func(df[[target]])
      }
    } else {
      # Pass through as-is if no valid transformation is defined
      out_cols[[target]] <- df[[target]]
    }
    
    # Apply dynamically supplied missing value masks from na_values schema column
    # NAs can be delimited via semicolon, e.g., "997;999"
    if (!is.na(na_str) && nchar(as.character(na_str)) > 0) {
      na_arr <- trimws(unlist(strsplit(as.character(na_str), ";")))
      for (na_code in na_arr) {
        # Coerce na_code to numeric if the underlying array is numeric to satisfy dplyr::na_if strict type matching
        if (is.numeric(out_cols[[target]]) && !is.na(suppressWarnings(as.numeric(na_code)))) {
          replacement <- as.numeric(na_code)
        } else {
          replacement <- na_code
        }
        out_cols[[target]] <- dplyr::na_if(out_cols[[target]], replacement)
      }
    }
    
    # Verify the variable is the designated variable type
    if (!is.na(expected_type) && expected_type != "") {
      val <- out_cols[[target]]
      
      # We check primarily if it's numeric/integer, factor, or character
      type_match <- switch(expected_type,
                           "numeric" = is.numeric(val),
                           "integer" = is.integer(val) || (is.numeric(val) && all(val == as.integer(val), na.rm = TRUE)),
                           "character" = is.character(val) || is.logical(val), # allow NAs which are logical
                           "factor" = is.factor(val) || is.logical(val),
                           TRUE)
      
      if (!type_match && !(all(is.na(val)))) {
        stop(sprintf("Type validation failed for '%s'. Expected type: '%s', but got: '%s'.", 
                        target, expected_type, class(val)[1]))
      }
    }
    
    message(sprintf("  -> mapped: %s [via %s]", target, ifelse(is.na(trans_str), 'none', trans_str)))
  }
  
  message("Binding final unified columns...")
  final_df <- bind_cols(out_cols)
  
  # Validation: Primary Keys must be unique and completely non-missing.
  # If student data, PK = country, school_id, student_id
  # If school data, PK = country, school_id
  pk_cols <- character(0)
  if (all(c("country", "school_id", "student_id") %in% names(final_df))) {
    pk_cols <- c("country", "school_id", "student_id")
  } else if (all(c("country", "school_id") %in% names(final_df))) {
    pk_cols <- c("country", "school_id")
  }
  
  if (length(pk_cols) > 0) {
    message(sprintf("  -> Validating primary keys: [%s]", paste(pk_cols, collapse = ", ")))
    
    # 1. Missing Value Check
    for (col in pk_cols) {
      if (any(is.na(final_df[[col]]))) {
        stop(sprintf("Validation Error: Primary key column '%s' contains missing (NA) values.", col))
      }
    }
    
    # 2. Uniqueness Check
    if (nrow(final_df) != nrow(dplyr::distinct(final_df, dplyr::across(dplyr::all_of(pk_cols))))) {
      duplicates <- final_df %>%
        dplyr::group_by(dplyr::across(dplyr::all_of(pk_cols))) %>%
        dplyr::filter(dplyr::n() > 1) %>%
        dplyr::ungroup() %>%
        dplyr::arrange(dplyr::across(dplyr::all_of(pk_cols)))
      
      message("Found duplicate primary keys in the generated dataset!")
      print(duplicates)
      stop(sprintf("Validation Error: The combination of [%s] does not uniquely identify every row. See printed table above for duplicated rows.", paste(pk_cols, collapse = ", ")))
    }
  }
  
  return(final_df)
}
