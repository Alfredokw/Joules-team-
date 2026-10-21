#!/usr/bin/env Rscript

# RQ3 descriptive power-over-time figure from raw Energibridge traces.
# Usage:
#   Rscript 08_power_over_time.R /path/to/execution_2_result
# The execution duration of every run is normalized to 0--100%, allowing
# temporal profile shapes to be compared without treating elapsed seconds from
# configurations with very different durations as directly equivalent.

suppressPackageStartupMessages(library(ggplot2))

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[1]) else "08_power_over_time.R"
script_path <- gsub("~\\+~", " ", script_path)
project_dir <- dirname(normalizePath(script_path, mustWork = FALSE))
analysis_dir <- normalizePath(file.path(project_dir, "..", ".."), mustWork = TRUE)
figure_root <- file.path(analysis_dir, "Plots", "Hypothesis Testing")
diagnostic_root <- file.path(
  analysis_dir, "Analyzed Data", "Diagnostic", "Diagnostic Hypothesis"
)
figure_dirs <- c(
  Derived = file.path(figure_root, "Derived"),
  Juliet = file.path(figure_root, "Juliet")
)
table_dirs <- c(
  Derived = file.path(diagnostic_root, "Derived", "Tables"),
  Juliet = file.path(diagnostic_root, "Juliet", "Tables")
)
invisible(lapply(c(figure_dirs, table_dirs), dir.create,
                 recursive = TRUE, showWarnings = FALSE))

args <- commandArgs(trailingOnly = TRUE)
data_root <- if (length(args)) args[1] else Sys.getenv("GREENLAB_EXECUTION_RESULT")
if (!nzchar(data_root)) {
  stop("Provide the execution_2_result directory as the first argument or set GREENLAB_EXECUTION_RESULT.")
}
data_root <- normalizePath(data_root, mustWork = TRUE)
execution_file <- file.path(data_root, "raw", "executions.csv")
trace_dir <- file.path(data_root, "raw", "energibridge")
if (!file.exists(execution_file) || !dir.exists(trace_dir)) {
  stop("Expected raw/executions.csv and raw/energibridge/ under: ", data_root)
}

executions <- read.csv(execution_file, stringsAsFactors = FALSE)
executions <- subset(
  executions,
  phase == "measured" & valid == 1 & workload_complete == 1 &
    termination_status == "completed" & energy_counter_wrap_count == 0
)
executions$group_label <- factor(
  ifelse(tolower(executions$group) == "juliet", "Juliet", "Derived"),
  levels = c("Juliet", "Derived")
)
executions$workload_label <- factor(
  ifelse(tolower(executions$workload) == "small", "Small", "Large"),
  levels = c("Small", "Large")
)
executions$configuration_label <- factor(
  tolower(executions$configuration),
  levels = c("baseline", "asan", "msan", "tsan", "memcheck"),
  labels = c("Baseline", "ASan", "MSan", "TSan", "Memcheck")
)

# Twenty equal-duration bins preserve broad execution phases while avoiding the
# changing-run-composition problem produced by pooling absolute elapsed times.
n_progress_bins <- 20L
minimum_bin_coverage <- 0.60
trace_rows <- vector("list", nrow(executions))
n_ok <- 0L

for (i in seq_len(nrow(executions))) {
  trace_file <- file.path(trace_dir, basename(executions$energibridge_csv[i]))
  trace <- tryCatch(
    read.csv(trace_file, check.names = FALSE),
    error = function(e) NULL
  )
  required <- c("Time", "PACKAGE_ENERGY (J)", "DRAM_ENERGY (J)")
  if (is.null(trace) || !all(required %in% names(trace))) next

  time <- as.numeric(trace$Time) / 1000
  energy <- as.numeric(trace[["PACKAGE_ENERGY (J)"]]) +
    as.numeric(trace[["DRAM_ENERGY (J)"]])
  finite <- is.finite(time) & is.finite(energy)
  time <- time[finite]
  energy <- energy[finite]
  if (length(time) < 3) next

  ordering <- order(time)
  time <- time[ordering]
  energy <- energy[ordering]
  keep <- !duplicated(time, fromLast = TRUE)
  time <- time[keep]
  energy <- energy[keep]
  elapsed <- time - time[1]
  duration <- max(elapsed, na.rm = TRUE)
  if (!is.finite(duration) || duration <= 0) next

  dt <- diff(elapsed)
  de <- diff(energy)
  midpoint <- (elapsed[-1] + elapsed[-length(elapsed)]) / 2
  good <- is.finite(dt) & is.finite(de) & dt > 0 & de >= 0 & dt <= 0.5
  if (!any(good)) next

  progress_bin <- pmin(
    n_progress_bins - 1L,
    floor(n_progress_bins * midpoint[good] / duration)
  )
  power <- de[good] / dt[good]
  weighted_energy <- tapply(power * dt[good], progress_bin, sum)
  coverage <- tapply(dt[good], progress_bin, sum)
  expected_coverage <- duration / n_progress_bins
  valid_names <- names(coverage)[
    coverage >= minimum_bin_coverage * expected_coverage
  ]
  if (length(valid_names) < 2) next

  n_ok <- n_ok + 1L
  trace_rows[[n_ok]] <- data.frame(
    run_id = executions$run_id[i],
    group = executions$group_label[i],
    workload = executions$workload_label[i],
    configuration = executions$configuration_label[i],
    progress_percent = (as.numeric(valid_names) + 0.5) *
      100 / n_progress_bins,
    power_watts = as.numeric(weighted_energy[valid_names]) /
      as.numeric(coverage[valid_names])
  )

  if (i %% 500 == 0) {
    message("Processed ", i, " / ", nrow(executions), " executions")
  }
}

trace_rows <- trace_rows[seq_len(n_ok)]
if (!length(trace_rows)) stop("No usable Energibridge traces were found.")
power_data <- do.call(rbind, trace_rows)
message("Usable power traces: ", length(unique(power_data$run_id)))

summary_parts <- lapply(
  split(
    power_data,
    interaction(
      power_data$group, power_data$workload,
      power_data$configuration, power_data$progress_percent,
      drop = TRUE
    )
  ),
  function(x) {
    if (nrow(x) < 10) return(NULL)
    data.frame(
      group = x$group[1],
      workload = x$workload[1],
      configuration = x$configuration[1],
      progress_percent = x$progress_percent[1],
      n_runs = nrow(x),
      q25 = quantile(x$power_watts, 0.25, names = FALSE),
      median_power = median(x$power_watts),
      q75 = quantile(x$power_watts, 0.75, names = FALSE),
      q95 = quantile(x$power_watts, 0.95, names = FALSE)
    )
  }
)
summary_data <- do.call(rbind, Filter(Negate(is.null), summary_parts))
summary_data$group <- as.character(summary_data$group)
summary_data$workload <- factor(summary_data$workload, levels = c("Small", "Large"))
summary_data$configuration <- factor(
  summary_data$configuration,
  levels = c("Baseline", "ASan", "MSan", "TSan", "Memcheck")
)

# Both workloads use one common, robust display range. Values remain in the
# summary CSV even when they fall beyond the plotted q25--q95 range.
power_limits <- range(c(summary_data$q25, summary_data$q95), finite = TRUE)
power_limits <- c(floor(power_limits[1]), ceiling(power_limits[2]))

for (group_name in c("Derived", "Juliet")) {
  group_summary <- summary_data[summary_data$group == group_name, , drop = FALSE]
  group_summary$row_label <- factor(
    as.character(group_summary$workload), levels = c("Small", "Large")
  )
  p <- ggplot(
    group_summary,
    aes(x = progress_percent, group = interaction(row_label, configuration))
  ) +
    geom_ribbon(
      aes(ymin = q25, ymax = q75),
      fill = "#56B4E9", alpha = 0.18, colour = NA
    ) +
    geom_line(aes(y = median_power, colour = "Median"), linewidth = 0.72) +
    geom_line(aes(y = q95, colour = "95th Percentile"),
              linewidth = 0.58, linetype = "dashed") +
    facet_grid(row_label ~ configuration) +
    scale_colour_manual(
      name = "Across-Run Statistic",
      values = c("Median" = "#0072B2", "95th Percentile" = "#D55E00")
    ) +
    scale_x_continuous(
      limits = c(0, 100), breaks = c(0, 25, 50, 75, 100),
      expand = expansion(mult = c(0, 0.01))
    ) +
    coord_cartesian(ylim = power_limits) +
    labs(
      title = paste0(group_name, " — RQ3: Power Over Time"),
      subtitle = paste0(
        "Build-and-run duration normalized to 0–100%; solid = median; ",
        "dashed = 95th percentile; shading = interquartile range."
      ),
      x = "Normalized Execution Progress (%)",
      y = "Window-Average Power (W)",
      caption = paste0(
        "Warm-ups, incomplete runs, and energy-counter wraps excluded. ",
        "Power is estimated from package + DRAM energy deltas."
      )
    ) +
    theme_bw(base_size = 10) +
    theme(
      plot.title.position = "plot",
      plot.title = element_text(hjust = 0, face = "plain", size = 14),
      plot.subtitle = element_text(hjust = 0, size = 8.5),
      plot.caption = element_text(hjust = 0, size = 7.0, colour = "grey35"),
      strip.background = element_rect(fill = "grey82", colour = "grey35"),
      strip.text = element_text(size = 8.5),
      axis.title = element_text(size = 9),
      axis.text = element_text(size = 7.5),
      panel.grid.major = element_line(colour = "grey90", linewidth = 0.4),
      panel.grid.minor = element_blank(),
      legend.position = "bottom"
    )
  output_file <- file.path(figure_dirs[[group_name]], "RQ3_power_over_time.png")
  ggsave(output_file, p, width = 13, height = 7.6, dpi = 220, bg = "white")
  write.csv(
    group_summary[, setdiff(names(group_summary), "row_label"), drop = FALSE],
    file.path(table_dirs[[group_name]], "RQ3_power_over_time_summary.csv"),
    row.names = FALSE
  )
  message("Figure written to ", output_file)
}

