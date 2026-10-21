# Shared setup and helper functions. Open this folder as a Positron project/workspace first.
if (!exists("PROJECT_DIR", inherits = FALSE)) PROJECT_DIR <- normalizePath(getwd(), mustWork = TRUE)
DATA_FILE <- file.path(PROJECT_DIR, "Data", "executions.csv")
RESULTS_DIR <- file.path(PROJECT_DIR, "Analyzed Data")
PLOTS_DIR <- file.path(PROJECT_DIR, "Plots")
ALPHA <- 0.05
GROUPS <- c("juliet", "derived")
SANITIZERS <- c("asan", "msan", "tsan", "memcheck")
CONFIGURATIONS <- c("baseline", SANITIZERS)

required_packages <- c("readr", "dplyr", "tidyr", "ggplot2")
missing_packages <- required_packages[!vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_packages)) {
  stop("Install these packages once in Positron: ", paste(missing_packages, collapse = ", "))
}
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(tidyr); library(ggplot2)
})
dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
for (group_label in c("Juliet","Derived")) {
  for (part in c("exploration","RQ1","RQ2","RQ3","RQ4")) dir.create(file.path(PLOTS_DIR,group_label,part),recursive=TRUE,showWarnings=FALSE)
  #dir.create(file.path(RESULTS_DIR,"statistics",group_label),recursive=TRUE,showWarnings=FALSE)
}

metric_labels <- c(
  total_energy_consumption_joules = "Total energy (J)",
  execution_time_seconds = "Build-and-run time (s)",
  runtime_seconds = "Application runtime (s; sensitivity endpoint)",
  average_power_watts = "Average power (W)",
  peak_power_watts = "Peak interval power (W)",
  power_variability_watts = "Power variability (W)",
  peak_rss_bytes = "Peak RSS memory (bytes)"
)

safe_name <- function(x) gsub("[^A-Za-z0-9]+", "_", x)

normality_check <- function(x, label, qq_file = NULL) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (!is.null(qq_file) && n >= 3) {
    dir.create(dirname(qq_file), recursive = TRUE, showWarnings = FALSE)
    png(qq_file, width = 900, height = 700)
    qqnorm(x, main = paste("Q-Q plot:", label)); qqline(x, col = "red", lwd = 2)
    dev.off()
    hist_file <- sub("\\.png$", "_hist.png", qq_file)
    png(hist_file, width=900, height=700)
    hist(x, main=paste("Difference distribution:", label), xlab="Difference", col="grey80", border="white")
    dev.off()
  }
  p <- if (n >= 3 && n <= 5000 && length(unique(x)) > 1) {
    tryCatch(shapiro.test(x)$p.value, error = function(e) NA_real_)
  } else NA_real_
  w <- if (!is.na(p)) tryCatch(unname(shapiro.test(x)$statistic), error = function(e) NA_real_) else NA_real_
  tibble::tibble(n_valid=n, shapiro_w = w, shapiro_p = p)
}

# Paired comparison: y is the second treatment, x is the reference treatment.
paired_test <- function(x, y, label, alternative = "two.sided", qq_file = NULL) {
  ok <- is.finite(x) & is.finite(y); x <- x[ok]; y <- y[ok]; delta <- y - x
  nd <- normality_check(delta, label, qq_file)
  n <- length(delta); mu <- if (n) mean(delta) else NA_real_
  skew <- if (n >= 3 && sd(delta) > 0) mean((delta - mean(delta))^3) / sd(delta)^3 else NA_real_
  if (n < 2) return(dplyr::bind_cols(tibble::tibble(contrast=label,n=n,mean_difference=mu,test="insufficient pairs",statistic=NA_real_,p_value=NA_real_,effect_size=NA_real_,effect_size_type=NA_character_,ci_low=NA_real_,ci_high=NA_real_,difference_skewness=skew,sign_test_p=NA_real_,symmetry_review_required=!is.na(skew)&&abs(skew)>1), nd %>% select(shapiro_w,shapiro_p)))
  normal <- !is.na(nd$shapiro_p[[1]]) && nd$shapiro_p[[1]] >= ALPHA
  if (normal && sd(delta) > 0) {
    tt <- tryCatch(t.test(y, x, paired=TRUE, alternative=alternative), error=function(e) NULL)
    if (!is.null(tt)) return(dplyr::bind_cols(tibble::tibble(contrast=label,n=n,mean_difference=mu,test="paired t-test",statistic=unname(tt$statistic),p_value=tt$p.value,effect_size=mu/sd(delta),effect_size_type="Cohen dz",ci_low=unname(tt$conf.int[1]),ci_high=unname(tt$conf.int[2]),difference_skewness=skew,sign_test_p=NA_real_,symmetry_review_required=!is.na(skew)&&abs(skew)>1),nd %>% select(shapiro_w,shapiro_p)))
  }
  nonzero <- delta[delta != 0]
  sign_p <- if (length(nonzero)) tryCatch(binom.test(sum(nonzero > 0), length(nonzero), p=.5, alternative=alternative)$p.value, error=function(e) NA_real_) else NA_real_
  # The sign-test result is included as a robustness check when paired differences are skewed.
  {
    wt <- if (length(nonzero)) tryCatch(suppressWarnings(wilcox.test(y, x, paired=TRUE, alternative=alternative, exact=FALSE)), error=function(e) NULL) else NULL
    nz <- delta != 0; ranks <- rank(abs(delta[nz])); d_nz <- delta[nz]; den <- sum(ranks)
    rbc <- if (den > 0) (sum(ranks[d_nz > 0]) - sum(ranks[d_nz < 0])) / den else NA_real_
    tibble::tibble(contrast=label,n=n,mean_difference=mu,test="Wilcoxon signed-rank",statistic=if(is.null(wt)) NA_real_ else unname(wt$statistic),p_value=if(is.null(wt)) NA_real_ else wt$p.value,effect_size=rbc,effect_size_type="paired rank-biserial",ci_low=NA_real_,ci_high=NA_real_,difference_skewness=skew,sign_test_p=sign_p,symmetry_review_required=!is.na(skew)&&abs(skew)>1,shapiro_w=nd$shapiro_w,shapiro_p=nd$shapiro_p)
  }
}

cliffs_delta <- function(x, y) {
  x <- x[is.finite(x)]; y <- y[is.finite(y)]
  if (!length(x) || !length(y)) return(NA_real_)
  cmp <- outer(x, y, "-")
  (sum(cmp > 0) - sum(cmp < 0)) / length(cmp)
}

message("Project folder: ", PROJECT_DIR, " | data: ", DATA_FILE, " | tables: ", RESULTS_DIR, " | plots: ", PLOTS_DIR)

