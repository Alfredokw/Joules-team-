source("00_config.R")
means <- readRDS(file.path(RESULTS_DIR, "subject_treatment_means.rds"))
metrics <- c("average_power_watts", "peak_power_watts", "power_variability_watts", "peak_rss_bytes")
rows <- list(); index <- 1L
for (g in GROUPS) for (metric in metrics) for (cfg in CONFIGURATIONS) {
  q <- means[means$group == g & means$configuration == cfg, ]
  small <- q[q$workload == "small", c("subject_id", metric)]
  large <- q[q$workload == "large", c("subject_id", metric)]
  names(small)[2] <- "small"; names(large)[2] <- "large"
  wide <- merge(small, large, by = "subject_id"); wide <- wide[order(wide$subject_id), ]
  result <- paired_wilcoxon_summary(wide$small, wide$large, alternative = "two.sided")
  result$group <- g; result$metric <- metric; result$configuration <- cfg
  result$test <- "Wilcoxon signed-rank, paired, two-sided"
  rows[[index]] <- result; index <- index + 1L
}
rq3 <- do.call(rbind, rows)
family_key <- interaction(rq3$group, rq3$metric, drop = TRUE)
rq3$p_holm <- ave(rq3$p_value, family_key, FUN = function(x) p.adjust(x, method = "holm"))
front <- c("group", "metric", "configuration", "test")
rq3 <- rq3[c(front, setdiff(names(rq3), front))]
write.csv(rq3, file.path(RESULTS_DIR, "RQ3_small_large_tests_v2.csv"), row.names = FALSE)

inputs <- unique(means[c("group", "subject_id", "workload", "input_n")])
inputs_wide <- reshape(inputs, idvar = c("group", "subject_id"), timevar = "workload", direction = "wide")
names(inputs_wide) <- sub("input_n\\.", "input_", names(inputs_wide))
memory_long <- means[c("group", "subject_id", "base_application", "family", "configuration", "workload", "peak_rss_bytes")]
memory <- reshape(memory_long, idvar = c("group", "subject_id", "base_application", "family", "configuration"), timevar = "workload", direction = "wide")
names(memory) <- sub("peak_rss_bytes\\.", "rss_", names(memory))
memory <- merge(memory, inputs_wide, by = c("group", "subject_id"), all.x = TRUE)
memory$memory_ratio <- memory$rss_large / memory$rss_small
memory$input_ratio <- memory$input_large / memory$input_small
memory$log_ratio_departure <- log(memory$memory_ratio / memory$input_ratio)
write.csv(memory, file.path(RESULTS_DIR, "RQ3_memory_scaling_values_v2.csv"), row.names = FALSE)

scale_rows <- list(); index <- 1L
for (g in GROUPS) for (cfg in CONFIGURATIONS) {
  q <- memory[memory$group == g & memory$configuration == cfg, ]
  result <- paired_wilcoxon_summary(rep(0, nrow(q)), q$log_ratio_departure, alternative = "two.sided")
  result$group <- g; result$configuration <- cfg
  result$median_memory_ratio <- median(q$memory_ratio); result$median_input_ratio <- median(q$input_ratio)
  result$test <- "Wilcoxon signed-rank against zero, two-sided"
  scale_rows[[index]] <- result; index <- index + 1L
}
scaling <- do.call(rbind, scale_rows)
scaling$p_holm <- ave(scaling$p_value, scaling$group, FUN = function(x) p.adjust(x, method = "holm"))
front <- c("group", "configuration", "test")
scaling <- scaling[c(front, setdiff(names(scaling), front))]
write.csv(scaling, file.path(RESULTS_DIR, "RQ3_memory_scaling_tests_v2.csv"), row.names = FALSE)
message("RQ3 complete: 40 workload contrasts and 10 memory-scaling tests.")
