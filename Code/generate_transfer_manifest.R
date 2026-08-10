#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(digest)
  library(jsonlite)
  library(dplyr)
})

transfer_dir <- "/Users/kevinwang/projects/learningtower_masonry/Data/Output/Transfer"
output_manifest_path <- file.path(transfer_dir, "checksums.json")

if (!dir.exists(transfer_dir)) {
  stop("Transfer directory does not exist: ", transfer_dir)
}

cat("Scanning transfer files in:", transfer_dir, "\n")

all_files <- list.files(transfer_dir, recursive = TRUE, full.names = FALSE)
# Exclude checksums.json itself and hidden files
all_files <- all_files[!basename(all_files) %in% c("checksums.json", ".DS_Store")]

files_metadata <- list()

for (rel_path in all_files) {
  full_path <- file.path(transfer_dir, rel_path)
  
  # Determine destination relative path in learningtower
  dest_rel <- case_when(
    grepl("^data/", rel_path) ~ rel_path,
    grepl("^student_full_data/", rel_path) ~ rel_path,
    grepl("\\.png$", rel_path) ~ file.path("man", "figures", basename(rel_path)),
    TRUE ~ rel_path
  )
  
  md5_hash <- digest::digest(full_path, algo = "md5", file = TRUE)
  file_size <- file.info(full_path)$size
  
  files_metadata[[rel_path]] <- list(
    md5 = md5_hash,
    size_bytes = file_size,
    destination_relative = dest_rel
  )
}

manifest <- list(
  version = "1.0.0",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  algorithm = "md5",
  total_files = length(files_metadata),
  files = files_metadata
)

jsonlite::write_json(manifest, output_manifest_path, auto_unbox = TRUE, pretty = TRUE)
cat("Successfully generated transfer manifest with", length(files_metadata), "files at:", output_manifest_path, "\n")
