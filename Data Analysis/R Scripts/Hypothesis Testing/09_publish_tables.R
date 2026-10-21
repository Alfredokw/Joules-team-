source("00_config.R")

# Only compact diagnostic and hypothesis-test tables are published. Execution
# rows, RDS caches, and other generated intermediates remain temporary.
publish_files <- c(
  "execution_status_report.csv",
  "treatment_cell_counts.csv",
  "detection_counts.csv",
  "RQ1_paired_baseline_tests_v2.csv",
  "RQ2_spearman_tests_v2.csv",
  "RQ3_small_large_tests_v2.csv",
  "RQ3_memory_scaling_values_v2.csv",
  "RQ3_memory_scaling_tests_v2.csv",
  "RQ4_omnibus_tests_v2.csv",
  "RQ4_posthoc_tests_v2.csv"
)

for (file_name in publish_files) {
  source_file <- file.path(RESULTS_DIR, file_name)
  if (!file.exists(source_file)) stop("Expected table not found: ", source_file)
  table_data <- read.csv(source_file, stringsAsFactors = FALSE, check.names = FALSE)
  if (!"group" %in% names(table_data)) {
    stop("Published table has no group column: ", file_name)
  }
  normalized_group <- tolower(as.character(table_data$group))
  for (group_name in names(TABLE_DIRS)) {
    group_table <- table_data[normalized_group == group_name, , drop = FALSE]
    write.csv(
      group_table,
      file.path(TABLE_DIRS[[group_name]], file_name),
      row.names = FALSE
    )
  }
}

message("Published group-specific tables under ", DIAGNOSTIC_ROOT)
