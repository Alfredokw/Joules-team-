source("00_config.R")

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("Install ggplot2 before generating the figures.")
}
suppressPackageStartupMessages(library(ggplot2))

overheads <- readRDS(file.path(RESULTS_DIR, "subject_overhead_factors.rds"))
means <- readRDS(file.path(RESULTS_DIR, "subject_treatment_means.rds"))
executions <- readRDS(file.path(RESULTS_DIR, "analysis_ready_data.rds"))
rq4_omnibus <- read.csv(
  file.path(RESULTS_DIR, "RQ4_omnibus_tests_v2.csv"),
  stringsAsFactors = FALSE
)

configuration_colours <- c(
  baseline = "#F8766D", asan = "#A3A500", msan = "#00BF7D",
  tsan = "#00B0F6", memcheck = "#E76BF3"
)
sanitizer_colours <- configuration_colours[SANITIZERS]
pretty_configuration <- c(
  baseline = "Baseline", asan = "ASan", msan = "MSan",
  tsan = "TSan", memcheck = "Memcheck"
)
pretty_sanitizer <- pretty_configuration[SANITIZERS]

review_theme <- function() {
  theme_bw(base_size = 11) +
    theme(
      plot.title.position = "plot",
      plot.title = element_text(hjust = 0, face = "plain", size = 15),
      plot.subtitle = element_text(hjust = 0, size = 10.5),
      strip.background = element_rect(fill = "grey82", colour = "grey35"),
      strip.text = element_text(size = 10.5),
      panel.grid.major = element_line(colour = "grey90", linewidth = 0.45),
      panel.grid.minor = element_line(colour = "grey94", linewidth = 0.35),
      legend.position = "bottom"
    )
}

mean_ci <- function(x) {
  n <- sum(is.finite(x))
  m <- mean(x, na.rm = TRUE)
  se <- stats::sd(x, na.rm = TRUE) / sqrt(n)
  crit <- stats::qt(0.975, df = n - 1)
  data.frame(y = m, ymin = m - crit * se, ymax = m + crit * se)
}

shared_execution_time_limits <- range(
  c(executions$execution_time_seconds, executions$runtime_seconds),
  finite = TRUE
)
shared_execution_time_limits <- c(
  shared_execution_time_limits[1] / 1.08,
  shared_execution_time_limits[2] * 1.08
)

rq4_outcome_labels <- c(
  energy_overhead = "Energy Overhead",
  buildrun_time_overhead = "Build-and-Run Time Overhead"
)
rq4_family_levels <- c(
  "data race", "lifetime/deallocation", "out-of-bounds access",
  "uninitialized memory"
)
rq4_family_labels <- c(
  "Data Race", "Lifetime /\nDeallocation", "Out-of-Bounds\nAccess",
  "Uninitialized\nMemory"
)
rq4_family_colours <- c(
  "data race" = "#E76BF3",
  "lifetime/deallocation" = "#F8766D",
  "out-of-bounds access" = "#00B0F6",
  "uninitialized memory" = "#00BF7D"
)

for (group_name in c("derived", "juliet")) {
  group_label <- if (group_name == "derived") "Derived" else "Juliet"
  figure_dir <- FIGURE_DIRS[[group_name]]
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

  group_overheads <- overheads[tolower(overheads$group) == group_name, , drop = FALSE]
  group_means <- means[tolower(means$group) == group_name, , drop = FALSE]
  group_executions <- executions[tolower(executions$group) == group_name, , drop = FALSE]

  rq1_energy <- transform(
    group_overheads, value = energy_overhead,
    outcome = "Total Energy Overhead"
  )
  rq1_time <- transform(
    group_overheads, value = buildrun_time_overhead,
    outcome = "Build-and-Run Time Overhead"
  )
  rq1 <- rbind(
    rq1_energy[, c("configuration", "workload", "subject_id", "value", "outcome")],
    rq1_time[, c("configuration", "workload", "subject_id", "value", "outcome")]
  )
  rq1$configuration <- factor(rq1$configuration, levels = SANITIZERS)
  rq1$workload <- factor(rq1$workload, levels = c("small", "large"))
  rq1$condition <- factor(
    paste(rq1$configuration, rq1$workload, sep = "\n"),
    levels = as.vector(t(outer(SANITIZERS, c("small", "large"), paste, sep = "\n"))),
    labels = as.vector(t(outer(pretty_sanitizer, c("Small", "Large"), paste, sep = "\n")))
  )
  p_rq1 <- ggplot(rq1, aes(condition, value, fill = configuration)) +
    geom_hline(yintercept = 1, linetype = "dashed", colour = "grey45") +
    geom_violin(trim = FALSE, alpha = 0.28, colour = NA, scale = "width") +
    geom_boxplot(width = 0.13, outlier.shape = NA, alpha = 0.78, colour = "grey20") +
    geom_point(position = position_jitter(width = 0.055, height = 0),
               size = 1.25, alpha = 0.50, colour = "grey25") +
    facet_wrap(~outcome, ncol = 2) +
    scale_y_log10(breaks = c(1, 3, 10, 30, 100)) +
    coord_cartesian(ylim = c(1, 100)) +
    scale_fill_manual(values = sanitizer_colours, labels = pretty_sanitizer) +
    labs(
      title = paste0(group_label, " — RQ1: Overhead Distributions"),
      subtitle = "Program-level sanitizer/baseline factors; dashed line = 1.",
      x = "Sanitizer configuration and workload",
      y = "Sanitizer / baseline factor (log scale)", fill = "Sanitizer"
    ) + review_theme() +
    theme(axis.text.x = element_text(angle = 25, hjust = 1, size = 8.5))
  ggsave(file.path(figure_dir, "RQ1_overhead_factors.png"), p_rq1,
         width = 13, height = 6.5, dpi = 200, bg = "white")

  rq2 <- group_overheads
  rq2$workload_label <- factor(
    ifelse(rq2$workload == "small", "Small", "Large"),
    levels = c("Small", "Large")
  )
  rq2$configuration <- factor(rq2$configuration, levels = SANITIZERS)
  p_rq2 <- ggplot(
    rq2, aes(buildrun_time_overhead, energy_overhead, colour = configuration)
  ) +
    geom_point(size = 1.9, alpha = 0.75) +
    facet_wrap(~workload_label, ncol = 2) +
    scale_x_log10() + scale_y_log10() +
    scale_colour_manual(values = sanitizer_colours, labels = pretty_sanitizer) +
    labs(
      title = paste0(group_label, " — RQ2: Time and Energy Overhead"),
      subtitle = "One point per program variant; inference uses Spearman rank correlation.",
      x = "Build-and-run time overhead factor (log scale)",
      y = "Energy overhead factor (log scale)", colour = "Sanitizer"
    ) + review_theme()
  ggsave(file.path(figure_dir, "RQ2_energy_time_scatter.png"), p_rq2,
         width = 11, height = 6.5, dpi = 200, bg = "white")

  rq2_exec <- group_executions
  rq2_exec$workload_label <- factor(
    ifelse(rq2_exec$workload == "small", "Small", "Large"),
    levels = c("Small", "Large")
  )
  rq2_exec$configuration <- factor(rq2_exec$configuration, levels = CONFIGURATIONS)
  make_execution_plot <- function(time_variable, title, x_label) {
    ggplot(
      rq2_exec,
      aes(.data[[time_variable]], total_energy_consumption_joules,
          colour = configuration)
    ) +
      geom_point(size = 0.65, alpha = 0.16) +
      geom_smooth(aes(group = configuration), method = "lm", formula = y ~ x,
                  se = FALSE, linewidth = 0.9) +
      facet_wrap(~workload_label, ncol = 2) +
      scale_x_log10() + scale_y_log10() +
      coord_cartesian(xlim = shared_execution_time_limits) +
      scale_colour_manual(values = configuration_colours, labels = pretty_configuration) +
      labs(
        title = paste0(group_label, " — ", title),
        subtitle = "All valid executions; coloured lines are configuration-specific log-log fits.",
        x = paste0(x_label, " (s; log scale)"),
        y = "Total energy consumption (J; log scale)", colour = "Configuration"
      ) + review_theme()
  }
  p_buildrun <- make_execution_plot(
    "execution_time_seconds", "Energy Versus Build-and-Run Time",
    "Build-and-run time"
  )
  p_runtime <- make_execution_plot(
    "runtime_seconds", "Energy Versus Application Runtime",
    "Application runtime"
  )
  ggsave(file.path(figure_dir, "RQ2_energy_vs_buildrun_all_executions.png"),
         p_buildrun, width = 11, height = 6.5, dpi = 200, bg = "white")
  ggsave(file.path(figure_dir, "RQ2_energy_vs_runtime_all_executions.png"),
         p_runtime, width = 11, height = 6.5, dpi = 200, bg = "white")

  rq3 <- group_means
  rq3$configuration <- factor(
    rq3$configuration, levels = CONFIGURATIONS,
    labels = unname(pretty_configuration[CONFIGURATIONS])
  )
  rq3$workload <- factor(rq3$workload, levels = c("small", "large"),
                         labels = c("Small", "Large"))
  make_rq3_plot <- function(metric, title, y_label) {
    ggplot(rq3, aes(workload, .data[[metric]])) +
      geom_line(aes(group = interaction(subject_id, configuration)),
                colour = "grey70", alpha = 0.55, linewidth = 0.45) +
      geom_point(colour = "grey50", size = 1.25, alpha = 0.70) +
      stat_summary(aes(group = configuration), fun = mean, geom = "line",
                   colour = "#0072B2", linewidth = 1) +
      stat_summary(aes(group = configuration), fun.data = mean_ci,
                   geom = "errorbar", width = 0.10, colour = "#0072B2") +
      stat_summary(fun = mean, geom = "point", colour = "#0072B2",
                   shape = 18, size = 2.8) +
      facet_wrap(~configuration, nrow = 1) + scale_y_log10() +
      labs(
        title = paste0(group_label, " — ", title),
        subtitle = "Grey lines pair program variants; blue diamonds and bars show means and 95% CIs.",
        x = "Workload size", y = paste0(y_label, " (log scale)")
      ) + review_theme() + theme(legend.position = "none")
  }
  p_rss <- make_rq3_plot("peak_rss_bytes", "RQ3: Peak RSS by Workload",
                         "Peak RSS memory (bytes)")
  p_variability <- make_rq3_plot(
    "power_variability_watts", "RQ3: Power Variability by Workload",
    "Power variability (W)"
  )
  png(file.path(figure_dir, "RQ3_rss_variability_paired.png"),
      width = 2600, height = 2200, res = 200)
  grid::grid.newpage()
  grid::pushViewport(grid::viewport(layout = grid::grid.layout(2, 1)))
  print(p_rss, vp = grid::viewport(layout.pos.row = 1, layout.pos.col = 1))
  print(p_variability, vp = grid::viewport(layout.pos.row = 2, layout.pos.col = 1))
  dev.off()

  density_data <- group_executions
  density_data$workload_label <- factor(
    ifelse(density_data$workload == "small", "Small", "Large"),
    levels = c("Small", "Large")
  )
  density_data$configuration <- factor(
    density_data$configuration, levels = CONFIGURATIONS
  )
  p_density <- ggplot(
    density_data,
    aes(average_power_watts, colour = configuration, fill = configuration)
  ) +
    geom_density(alpha = 0.08, linewidth = 0.75, adjust = 1) +
    facet_wrap(~workload_label, ncol = 2) + scale_x_log10() +
    scale_colour_manual(values = configuration_colours, labels = pretty_configuration) +
    scale_fill_manual(values = configuration_colours, labels = pretty_configuration) +
    labs(
      title = paste0(group_label, " — RQ3: Average-Power Distributions"),
      subtitle = "All valid executions; density is normalized rather than a count.",
      x = "Average power (W; log scale)", y = "Density",
      colour = "Configuration", fill = "Configuration"
    ) + review_theme()
  ggsave(file.path(figure_dir, "RQ3_average_power_density.png"), p_density,
         width = 11, height = 6.5, dpi = 200, bg = "white")

  group_significant <- subset(
    rq4_omnibus,
    tolower(group) == group_name & analysis_role == "primary" & p_holm < ALPHA
  )
  rq4_rows <- lapply(seq_len(nrow(group_significant)), function(i) {
    condition <- group_significant[i, ]
    values <- group_overheads[
      group_overheads$configuration == condition$sanitizer &
        group_overheads$workload == condition$workload, , drop = FALSE
    ]
    values$value <- values[[condition$outcome]]
    values$condition_label <- paste(
      rq4_outcome_labels[condition$outcome],
      pretty_sanitizer[condition$sanitizer],
      ifelse(condition$workload == "small", "Small", "Large"), sep = " — "
    )
    values
  })
  if (length(rq4_rows)) {
    rq4_data <- do.call(rbind, rq4_rows)
    rq4_data$family <- factor(rq4_data$family, levels = rq4_family_levels)
    rq4_simple <- aggregate(value ~ condition_label + family, rq4_data, median)
    names(rq4_simple)[3] <- "median_overhead"
    p_rq4 <- ggplot(
      rq4_simple,
      aes(median_overhead, condition_label, colour = family, shape = family)
    ) +
      geom_vline(xintercept = 1, linetype = "dashed", colour = "grey45") +
      geom_point(size = 3.4, stroke = 0.9, position = position_dodge(width = 0.62)) +
      scale_colour_manual(values = rq4_family_colours, labels = rq4_family_labels,
                          name = "Memory-Error Family") +
      scale_shape_manual(values = c(16, 17, 15, 18), labels = rq4_family_labels,
                         name = "Memory-Error Family") +
      labs(
        title = paste0(group_label, " — RQ4: Significant Primary Conditions"),
        subtitle = "Each point is the median of three program variants; significance applies to each row overall.",
        x = "Median sanitizer / baseline overhead factor", y = NULL
      ) + review_theme() + theme(panel.grid.minor = element_blank())
  } else {
    p_rq4 <- ggplot() +
      annotate("text", x = 0, y = 0,
               label = "No primary RQ4 condition is significant after Holm correction.") +
      xlim(-1, 1) + ylim(-1, 1) + theme_void() +
      labs(title = paste0(group_label, " — RQ4"))
  }
  ggsave(file.path(figure_dir, "RQ4_significant_conditions.png"), p_rq4,
         width = 11, height = 6.5, dpi = 200, bg = "white")
}

message("Group-specific figures written under ", FIGURE_ROOT)
