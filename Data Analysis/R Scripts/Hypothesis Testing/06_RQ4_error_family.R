source("00_config.R")
overheads <- readRDS(file.path(RESULTS_DIR, "subject_overhead_factors.rds"))
outcomes <- c(energy_overhead = "primary", buildrun_time_overhead = "primary", runtime_only_overhead = "runtime-only sensitivity")
rows <- list(); index <- 1L; condition_id <- 0L
for (g in GROUPS) for (outcome in names(outcomes)) for (cfg in SANITIZERS) for (wl in c("small", "large")) {
  condition_id <- condition_id + 1L
  q <- overheads[overheads$group == g & overheads$configuration == cfg & overheads$workload == wl, ]
  if (g == "juliet") {
    result <- permutation_kw(q[[outcome]], q$family, seed = 20261018L + condition_id)
    test_name <- paste0("Monte Carlo permutation Kruskal-Wallis (B=", PERMUTATIONS, ")")
    effect_name <- "epsilon squared"
  } else {
    result <- exact_blocked_friedman(q, outcome)
    test_name <- "Exact blocked Friedman permutation test"
    effect_name <- "Kendall W"
  }
  rows[[index]] <- data.frame(
    group = g, outcome = outcome, sanitizer = cfg, workload = wl,
    analysis_role = unname(outcomes[[outcome]]), test = test_name,
    n_subjects = nrow(q), subjects_per_family = paste(sort(as.integer(table(q$family))), collapse = "/"),
    statistic = result$statistic, p_value = result$p_value,
    effect_size = result$effect_size, effect_size_type = effect_name,
    stringsAsFactors = FALSE
  )
  index <- index + 1L
}
omnibus <- do.call(rbind, rows)
family_key <- interaction(omnibus$group, omnibus$outcome, omnibus$analysis_role, drop = TRUE)
omnibus$p_holm <- ave(omnibus$p_value, family_key, FUN = function(x) p.adjust(x, method = "holm"))
write.csv(omnibus, file.path(RESULTS_DIR, "RQ4_omnibus_tests_v2.csv"), row.names = FALSE)

significant <- omnibus[omnibus$p_holm < ALPHA, , drop = FALSE]
posthoc_rows <- list(); index <- 1L
if (nrow(significant)) {
  for (i in seq_len(nrow(significant))) {
    s <- significant[i, ]
    q <- overheads[overheads$group == s$group & overheads$configuration == s$sanitizer & overheads$workload == s$workload, ]
    families <- sort(unique(q$family)); pairs <- combn(families, 2, simplify = FALSE)
    local_rows <- list()
    for (j in seq_along(pairs)) {
      pair <- pairs[[j]]
      if (s$group == "juliet") {
        x <- q[[s$outcome]][q$family == pair[1]]; y <- q[[s$outcome]][q$family == pair[2]]
        wt <- suppressWarnings(wilcox.test(x, y, paired = FALSE, exact = TRUE))
        effect <- cliffs_delta(x, y); effect_type <- "Cliff delta"; method <- "Wilcoxon rank-sum, two-sided"
      } else {
        qq <- q[q$family %in% pair, c("base_application", "family", s$outcome)]
        wide <- reshape(qq, idvar = "base_application", timevar = "family", direction = "wide")
        wide <- wide[order(wide$base_application), ]
        xname <- paste(s$outcome, pair[1], sep = "."); yname <- paste(s$outcome, pair[2], sep = ".")
        x <- wide[[xname]]; y <- wide[[yname]]
        wt <- suppressWarnings(wilcox.test(x, y, paired = TRUE, exact = TRUE))
        effect <- paired_rank_biserial(x - y); effect_type <- "paired rank-biserial"; method <- "Wilcoxon signed-rank, paired, two-sided"
      }
      local_rows[[j]] <- data.frame(
        group = s$group, outcome = s$outcome, sanitizer = s$sanitizer, workload = s$workload,
        family_1 = pair[1], family_2 = pair[2], method = method, p_value = wt$p.value,
        effect_size = effect, effect_size_type = effect_type, stringsAsFactors = FALSE
      )
    }
    local <- do.call(rbind, local_rows)
    local$p_holm_within_omnibus <- p.adjust(local$p_value, "holm")
    posthoc_rows[[index]] <- local; index <- index + 1L
  }
}
if (length(posthoc_rows)) {
  posthoc <- do.call(rbind, posthoc_rows)
} else {
  posthoc <- data.frame(
    group = character(), outcome = character(), sanitizer = character(), workload = character(),
    family_1 = character(), family_2 = character(), method = character(), p_value = double(),
    effect_size = double(), effect_size_type = character(), p_holm_within_omnibus = double(),
    stringsAsFactors = FALSE
  )
}
write.csv(posthoc, file.path(RESULTS_DIR, "RQ4_posthoc_tests_v2.csv"), row.names = FALSE)
message("RQ4 complete: ", nrow(omnibus), " omnibus tests; ", nrow(posthoc), " gated post-hoc tests.")
