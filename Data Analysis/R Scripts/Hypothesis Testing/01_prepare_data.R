source("00_config.R")
if (!file.exists(DATA_FILE)) stop("Data file not found: ", DATA_FILE)

raw <- read.csv(DATA_FILE, na.strings = c("", "NA"), check.names = FALSE, stringsAsFactors = FALSE)
required <- c(
  "run_id", "phase", "repetition", "subject_id", "group", "base_application",
  "family", "workload", "input_n", "configuration", "build_seconds",
  "runtime_seconds", "execution_time_seconds", "total_energy_consumption_joules",
  "average_power_watts", "peak_power_watts", "power_variability_watts",
  "peak_rss_bytes", "termination_status", "workload_complete", "valid",
  "compile_return_code", "runtime_return_code", "measurement_return_code", "detected"
)
missing_columns <- setdiff(required, names(raw))
if (length(missing_columns)) stop("Missing columns: ", paste(missing_columns, collapse = ", "))

raw$group <- tolower(raw$group)
raw$workload <- tolower(raw$workload)
raw$configuration <- tolower(raw$configuration)
raw$phase <- tolower(raw$phase)

status <- aggregate(
  rep(1L, nrow(raw)),
  raw[c("group", "phase", "termination_status", "workload_complete", "valid",
        "compile_return_code", "runtime_return_code", "measurement_return_code")],
  sum
)
names(status)[ncol(status)] <- "runs"
write.csv(status, file.path(RESULTS_DIR, "execution_status_report.csv"), row.names = FALSE)

keep <- raw$phase != "warmup" & raw$valid == 1 & raw$workload_complete == 1 &
  raw$termination_status == "completed" & raw$group %in% GROUPS &
  raw$configuration %in% CONFIGURATIONS & raw$workload %in% c("small", "large")
clean <- raw[keep, , drop = FALSE]

if (anyDuplicated(clean$run_id)) stop("Duplicate run_id values found.")

cell_counts <- aggregate(
  rep(1L, nrow(clean)),
  clean[c("group", "subject_id", "family", "base_application", "workload", "configuration")],
  sum
)
names(cell_counts)[ncol(cell_counts)] <- "runs"
write.csv(cell_counts, file.path(RESULTS_DIR, "treatment_cell_counts.csv"), row.names = FALSE)
if (nrow(cell_counts) != 240 || any(cell_counts$runs != 30)) {
  stop("The expected balanced structure (240 cells x 30 runs) is not satisfied.")
}

time_error <- clean$execution_time_seconds - clean$build_seconds - clean$runtime_seconds
time_check <- data.frame(
  n = length(time_error),
  max_abs_difference = max(abs(time_error)),
  mean_abs_difference = mean(abs(time_error))
)
write.csv(time_check, file.path(RESULTS_DIR, "execution_time_definition_check.csv"), row.names = FALSE)

detection <- aggregate(rep(1L, nrow(clean)), clean[c("group", "family", "configuration", "detected")], sum)
names(detection)[ncol(detection)] <- "runs"
write.csv(detection, file.path(RESULTS_DIR, "detection_counts.csv"), row.names = FALSE)
write.csv(clean, file.path(RESULTS_DIR, "analysis_ready_data.csv"), row.names = FALSE)
saveRDS(clean, file.path(RESULTS_DIR, "analysis_ready_data.rds"))
message("Prepared ", nrow(clean), " valid measured executions.")
