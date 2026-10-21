# Repository layout expected by this package:
# Data Analysis/
#   Data/executions.csv
#   R Scripts/Hypothesis Testing/   <- these scripts
#   Plots/Hypothesis Testing/{Derived,Juliet}/
#   Analyzed Data/Diagnostic/Diagnostic Hypothesis/{Derived,Juliet}/Tables/
#
# run_all.R changes the working directory to the script directory before
# sourcing this file. All persistent paths are repository-relative.
PROJECT_DIR <- normalizePath(getwd(), mustWork = TRUE)
ANALYSIS_DIR <- normalizePath(file.path(PROJECT_DIR, "..", ".."), mustWork = TRUE)
DATA_FILE <- Sys.getenv(
  "GREENLAB_DATA",
  unset = file.path(ANALYSIS_DIR, "Data", "executions.csv")
)
RESULTS_DIR <- Sys.getenv(
  "GREENLAB_CACHE",
  unset = file.path(tempdir(), paste0("greenlab_hypothesis_testing_", Sys.getpid()))
)
FIGURE_ROOT <- file.path(ANALYSIS_DIR, "Plots", "Hypothesis Testing")
DIAGNOSTIC_ROOT <- file.path(
  ANALYSIS_DIR, "Analyzed Data", "Diagnostic", "Diagnostic Hypothesis"
)
FIGURE_DIRS <- c(
  derived = file.path(FIGURE_ROOT, "Derived"),
  juliet = file.path(FIGURE_ROOT, "Juliet")
)
TABLE_DIRS <- c(
  derived = file.path(DIAGNOSTIC_ROOT, "Derived", "Tables"),
  juliet = file.path(DIAGNOSTIC_ROOT, "Juliet", "Tables")
)
ALPHA <- 0.05
PERMUTATIONS <- as.integer(Sys.getenv("GREENLAB_PERMUTATIONS", unset = "49999"))
GROUPS <- c("juliet", "derived")
SANITIZERS <- c("asan", "msan", "tsan", "memcheck")
CONFIGURATIONS <- c("baseline", SANITIZERS)

dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
invisible(lapply(c(FIGURE_DIRS, TABLE_DIRS), dir.create,
                 recursive = TRUE, showWarnings = FALSE))

safe_shapiro <- function(x) {
  x <- x[is.finite(x)]
  if (length(x) < 3 || length(x) > 5000 || length(unique(x)) < 2) {
    return(c(w = NA_real_, p = NA_real_))
  }
  z <- shapiro.test(x)
  c(w = unname(z$statistic), p = z$p.value)
}

paired_rank_biserial <- function(delta) {
  delta <- delta[is.finite(delta) & delta != 0]
  if (!length(delta)) return(NA_real_)
  ranks <- rank(abs(delta), ties.method = "average")
  (sum(ranks[delta > 0]) - sum(ranks[delta < 0])) / sum(ranks)
}

paired_wilcoxon_summary <- function(x, y, alternative = "two.sided") {
  ok <- is.finite(x) & is.finite(y)
  x <- x[ok]
  y <- y[ok]
  delta <- y - x
  nonzero <- delta[delta != 0]
  wt <- tryCatch(
    suppressWarnings(wilcox.test(y, x, paired = TRUE, alternative = alternative, exact = TRUE)),
    error = function(e) suppressWarnings(wilcox.test(y, x, paired = TRUE, alternative = alternative, exact = FALSE))
  )
  positive <- sum(nonzero > 0)
  sign_p <- if (length(nonzero)) {
    binom.test(positive, length(nonzero), p = 0.5, alternative = alternative)$p.value
  } else NA_real_
  shp <- safe_shapiro(delta)
  data.frame(
    n = length(delta),
    nonzero_pairs = length(nonzero),
    median_difference = median(delta),
    mean_difference = mean(delta),
    statistic = unname(wt$statistic),
    p_value = wt$p.value,
    effect_size = paired_rank_biserial(delta),
    effect_size_type = "paired rank-biserial",
    sign_test_p = sign_p,
    shapiro_w = shp[["w"]],
    shapiro_p = shp[["p"]],
    stringsAsFactors = FALSE
  )
}

cliffs_delta <- function(x, y) {
  x <- x[is.finite(x)]
  y <- y[is.finite(y)]
  if (!length(x) || !length(y)) return(NA_real_)
  cmp <- outer(x, y, "-")
  (sum(cmp > 0) - sum(cmp < 0)) / length(cmp)
}

kw_statistic <- function(y, group) {
  ok <- is.finite(y) & !is.na(group)
  y <- y[ok]
  group <- factor(group[ok])
  n <- length(y)
  ranks <- rank(y, ties.method = "average")
  ns <- table(group)
  sums <- tapply(ranks, group, sum)
  h <- 12 / (n * (n + 1)) * sum((sums^2) / ns) - 3 * (n + 1)
  ties <- table(y)
  correction <- 1 - sum(ties^3 - ties) / (n^3 - n)
  if (correction > 0) h / correction else 0
}

permutation_kw <- function(y, group, permutations = PERMUTATIONS, seed = 20261018L) {
  observed <- kw_statistic(y, group)
  set.seed(seed)
  exceed <- 0L
  for (i in seq_len(permutations)) {
    candidate <- kw_statistic(y, sample(group, replace = FALSE))
    if (candidate >= observed - 1e-12) exceed <- exceed + 1L
  }
  list(
    statistic = observed,
    p_value = (exceed + 1) / (permutations + 1),
    effect_size = max(0, (observed - nlevels(factor(group)) + 1) /
      (length(y) - nlevels(factor(group))))
  )
}

all_permutations <- function(x) {
  if (length(x) == 1) return(matrix(x, nrow = 1))
  do.call(rbind, lapply(seq_along(x), function(i) {
    rest <- all_permutations(x[-i])
    cbind(x[i], rest)
  }))
}

exact_blocked_friedman <- function(data, value_col) {
  wide <- reshape(
    data[c("base_application", "family", value_col)],
    idvar = "base_application", timevar = "family", direction = "wide"
  )
  wide <- wide[order(wide$base_application), ]
  value_matrix <- as.matrix(wide[, setdiff(names(wide), "base_application"), drop = FALSE])
  if (anyNA(value_matrix) || nrow(value_matrix) != 3 || ncol(value_matrix) != 4) {
    stop("Derived RQ4 requires exactly 3 base applications x 4 error families.")
  }
  rank_matrix <- t(apply(value_matrix, 1, rank, ties.method = "average"))
  b <- nrow(rank_matrix)
  k <- ncol(rank_matrix)
  q_stat <- function(column_sums) {
    12 / (b * k * (k + 1)) * sum((column_sums - b * (k + 1) / 2)^2)
  }
  observed <- q_stat(colSums(rank_matrix))
  perms <- all_permutations(seq_len(k))
  exceed <- 0L
  total <- nrow(perms)^b
  for (a in seq_len(nrow(perms))) {
    for (bb in seq_len(nrow(perms))) {
      for (cc in seq_len(nrow(perms))) {
        sums <- rank_matrix[1, perms[a, ]] + rank_matrix[2, perms[bb, ]] + rank_matrix[3, perms[cc, ]]
        if (q_stat(sums) >= observed - 1e-12) exceed <- exceed + 1L
      }
    }
  }
  list(statistic = observed, p_value = exceed / total, effect_size = observed / (b * (k - 1)))
}

message("Project: ", PROJECT_DIR)
message("Analysis root: ", ANALYSIS_DIR)
message("Data: ", DATA_FILE)
message("Temporary cache: ", RESULTS_DIR)
message("Figure root: ", FIGURE_ROOT)
message("Diagnostic root: ", DIAGNOSTIC_ROOT)
