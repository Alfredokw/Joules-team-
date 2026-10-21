source("00_config.R")
clean <- readRDS(file.path(RESULTS_DIR, "analysis_ready_data.rds"))

outcomes <- c(
  "total_energy_consumption_joules", "execution_time_seconds", "runtime_seconds",
  "average_power_watts", "peak_power_watts", "power_variability_watts", "peak_rss_bytes"
)

subject_means <- aggregate(
  clean[outcomes],
  clean[c("group", "subject_id", "base_application", "family", "workload", "input_n", "configuration")],
  mean, na.rm = TRUE
)
write.csv(subject_means, file.path(RESULTS_DIR, "subject_treatment_means.csv"), row.names = FALSE)

baseline <- subject_means[subject_means$configuration == "baseline",
  c("group", "subject_id", "base_application", "family", "workload",
    "total_energy_consumption_joules", "execution_time_seconds", "runtime_seconds")]
names(baseline)[6:8] <- c("baseline_energy", "baseline_buildrun", "baseline_runtime")

overheads <- merge(
  subject_means[subject_means$configuration %in% SANITIZERS, ], baseline,
  by = c("group", "subject_id", "base_application", "family", "workload"), all.x = TRUE
)
overheads$energy_overhead <- overheads$total_energy_consumption_joules / overheads$baseline_energy
overheads$buildrun_time_overhead <- overheads$execution_time_seconds / overheads$baseline_buildrun
overheads$runtime_only_overhead <- overheads$runtime_seconds / overheads$baseline_runtime

if (any(!is.finite(overheads$energy_overhead)) ||
    any(!is.finite(overheads$buildrun_time_overhead)) ||
    any(!is.finite(overheads$runtime_only_overhead))) {
  stop("Non-finite subject-level overhead factors found.")
}
write.csv(overheads, file.path(RESULTS_DIR, "subject_overhead_factors.csv"), row.names = FALSE)
saveRDS(subject_means, file.path(RESULTS_DIR, "subject_treatment_means.rds"))
saveRDS(overheads, file.path(RESULTS_DIR, "subject_overhead_factors.rds"))
message("Created subject-level means and ratio-of-means overhead factors.")
