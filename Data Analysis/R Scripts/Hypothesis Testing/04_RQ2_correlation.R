source("00_config.R")
overheads <- readRDS(file.path(RESULTS_DIR, "subject_overhead_factors.rds"))
time_scopes <- c(buildrun_time_overhead = "primary", runtime_only_overhead = "runtime-only sensitivity")
rows <- list(); index <- 1L
for (g in GROUPS) for (time_scope in names(time_scopes)) for (cfg in SANITIZERS) for (wl in c("small", "large")) {
  q <- overheads[overheads$group == g & overheads$configuration == cfg & overheads$workload == wl, ]
  test <- suppressWarnings(cor.test(q[[time_scope]], q$energy_overhead, method = "spearman", alternative = "greater", exact = FALSE))
  rows[[index]] <- data.frame(
    group = g, time_scope = time_scope, sanitizer = cfg, workload = wl,
    analysis_role = unname(time_scopes[[time_scope]]), test = "Spearman rank correlation, one-sided",
    n = sum(is.finite(q[[time_scope]]) & is.finite(q$energy_overhead)),
    correlation = unname(test$estimate), p_value = test$p.value, stringsAsFactors = FALSE
  )
  index <- index + 1L
}
rq2 <- do.call(rbind, rows)
family_key <- interaction(rq2$group, rq2$analysis_role, drop = TRUE)
rq2$p_holm <- ave(rq2$p_value, family_key, FUN = function(x) p.adjust(x, method = "holm"))
write.csv(rq2, file.path(RESULTS_DIR, "RQ2_spearman_tests_v2.csv"), row.names = FALSE)
message("RQ2 complete: ", nrow(rq2), " correlations; 16 are primary.")
