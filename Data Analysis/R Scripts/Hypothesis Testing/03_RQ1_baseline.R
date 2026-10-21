source("00_config.R")
means <- readRDS(file.path(RESULTS_DIR, "subject_treatment_means.rds"))
outcomes <- c(total_energy_consumption_joules = "primary", execution_time_seconds = "primary", runtime_seconds = "runtime-only sensitivity")
rows <- list(); index <- 1L
for (g in GROUPS) for (outcome in names(outcomes)) for (cfg in SANITIZERS) for (wl in c("small", "large")) {
  q <- means[means$group == g & means$workload == wl & means$configuration %in% c("baseline", cfg), ]
  base <- q[q$configuration == "baseline", c("subject_id", outcome)]
  treated <- q[q$configuration == cfg, c("subject_id", outcome)]
  names(base)[2] <- "baseline"; names(treated)[2] <- "treated"
  wide <- merge(base, treated, by = "subject_id"); wide <- wide[order(wide$subject_id), ]
  result <- paired_wilcoxon_summary(wide$baseline, wide$treated, alternative = "greater")
  result$median_overhead_factor <- median(wide$treated / wide$baseline)
  result$group <- g; result$outcome <- outcome; result$sanitizer <- cfg; result$workload <- wl
  result$analysis_role <- unname(outcomes[[outcome]])
  result$test <- "Wilcoxon signed-rank, paired, one-sided"
  rows[[index]] <- result; index <- index + 1L
}
rq1 <- do.call(rbind, rows)
family_key <- interaction(rq1$group, rq1$outcome, rq1$analysis_role, drop = TRUE)
rq1$p_holm <- ave(rq1$p_value, family_key, FUN = function(x) p.adjust(x, method = "holm"))
front <- c("group", "outcome", "sanitizer", "workload", "analysis_role", "test")
rq1 <- rq1[c(front, setdiff(names(rq1), front))]
write.csv(rq1, file.path(RESULTS_DIR, "RQ1_paired_baseline_tests_v2.csv"), row.names = FALSE)
message("RQ1 complete: ", nrow(rq1), " contrasts; 32 are primary.")
