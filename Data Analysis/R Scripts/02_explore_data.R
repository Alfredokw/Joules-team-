source(file.path("R Scripts", "00_config.R"))
clean <- readRDS(file.path(RESULTS_DIR,"analysis_ready_data.rds"))
metrics <- c("total_energy_consumption_joules","execution_time_seconds","runtime_seconds",
             "average_power_watts","peak_power_watts","power_variability_watts","peak_rss_bytes")
# Fixed metric-specific scales are computed across both groups so matching plots are comparable.
COMMON_RANGES <- lapply(metrics,function(m) range(clean[[m]],finite=TRUE)); names(COMMON_RANGES)<-metrics
long <- clean %>% select(group,group_label,subject_id,family,workload,configuration,repetition,all_of(metrics)) %>%
  tidyr::pivot_longer(all_of(metrics),names_to="metric",values_to="value")
summary_runs <- long %>% group_by(group,subject_id,family,workload,configuration,metric) %>%
  summarise(n=n(),mean=mean(value),median=median(value),sd=sd(value),iqr=IQR(value),
            min=min(value),max=max(value),.groups="drop")
readr::write_csv(summary_runs,file.path(RESULTS_DIR,"descriptive_statistics_by_subject_treatment.csv"))
summary_group <- summary_runs %>% group_by(group,workload,configuration,metric) %>%
  summarise(n_subjects=n_distinct(subject_id),mean_of_subject_means=mean(mean),
            median_of_subject_means=median(mean),sd_of_subject_means=sd(mean),
            iqr_of_subject_means=IQR(mean),.groups="drop")
readr::write_csv(summary_group,file.path(RESULTS_DIR,"descriptive_statistics_group_level.csv"))

for (g in GROUPS) {
  label <- ifelse(g=="juliet","Juliet","Derived")
  gd <- file.path(PLOTS_DIR,label,"exploration")
  dir.create(gd,recursive=TRUE,showWarnings=FALSE)
  for (m in metrics) {
    dat <- filter(long,group==g,metric==m)
    lim <- COMMON_RANGES[[m]]
    lab <- metric_labels[[m]]
    p <- ggplot(dat,aes(configuration,value,fill=configuration))+
      geom_violin(trim=FALSE,alpha=.28,color=NA)+geom_boxplot(width=.13,outlier.alpha=.2)+
      facet_wrap(~workload,nrow=1,scales="fixed")+scale_y_log10()+coord_cartesian(ylim=lim)+
      labs(title=paste(label,lab,"by sanitizer and workload"),subtitle="Violin shows distribution shape; box shows median and quartiles. Shared log scale across both groups.",x="Configuration",y=paste(lab,"(log scale)"),fill="Configuration")+theme_bw()+
      theme(legend.position="bottom",axis.text.x=element_text(angle=25,hjust=1))
    ggsave(file.path(gd,paste0(m,"_violin_box.png")),p,width=11,height=5.5,dpi=160)
    p <- ggplot(dat,aes(value,color=configuration,fill=configuration))+geom_density(alpha=.10,na.rm=TRUE)+
      facet_wrap(~workload,nrow=1,scales="fixed")+scale_x_log10()+coord_cartesian(xlim=lim)+
      labs(title=paste(label,"Distribution shapes:",lab),subtitle="Density is a normalized curve, not a count. Shared log scale across groups.",x=paste(lab,"(log scale)"),y="Density")+theme_bw()
    ggsave(file.path(gd,paste0(m,"_density.png")),p,width=11,height=5.5,dpi=160)
  }
}

# Combined energy-density figure: one figure with group columns and workload rows
energy_metric <- "total_energy_consumption_joules"
energy_dat <- filter(long, metric == energy_metric) %>%
  mutate(
    group_label = factor(group_label, levels = c("Juliet", "Derived"))
  )

p <- ggplot(
  energy_dat,
  aes(x = value, color = configuration, fill = configuration)
) +
  geom_density(alpha = 0.10, na.rm = TRUE) +
  facet_grid(workload ~ group_label, scales = "fixed") +
  scale_x_log10() +
  coord_cartesian(xlim = COMMON_RANGES[[energy_metric]]) +
  labs(
    title = "Distribution of Total Energy Consumption by Sanitizer",
    subtitle = "Density is normalized; all panels share the same log scale.",
    x = "Total energy (J, log scale)",
    y = "Density",
    color = "Configuration",
    fill = "Configuration"
  ) +
  theme_bw() +
  theme(
    legend.position = "bottom",
    strip.placement = "outside",
    strip.background = element_rect(fill = "grey90"),
    panel.spacing = unit(0.8, "lines")
  )

plot_dir <- file.path(PLOTS_DIR, "combined")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

ggsave(
  file.path(plot_dir, "total_energy_density_combined.png"),
  p,
  width = 11,
  height = 7,
  dpi = 160
)

# Combined violin and boxplot: Juliet + Derived
energy_metric <- "total_energy_consumption_joules"

energy_dat <- filter(long, metric == energy_metric) %>%
  mutate(
    group_label = factor(group_label, levels = c("Juliet", "Derived")),
    workload = factor(workload, levels = c("small", "large"))
  )

p <- ggplot(
  energy_dat,
  aes(x = configuration, y = value, fill = configuration)
) +
  geom_violin(trim = FALSE, alpha = 0.28, color = NA) +
  geom_boxplot(width = 0.13, outlier.alpha = 0.2) +
  facet_grid(workload ~ group_label, scales = "fixed") +
  scale_y_log10() +
  coord_cartesian(ylim = COMMON_RANGES[[energy_metric]]) +
  labs(
    title = "Total Energy Consumption by Sanitizer and Workload",
    subtitle = "Violin shows distribution shape; box shows median and quartiles. Shared log scale across both groups.",
    x = "Configuration",
    y = "Total energy (J, log scale)",
    fill = "Configuration"
  ) +
  theme_bw() +
  theme(
    legend.position = "bottom",
    strip.placement = "outside",
    strip.background = element_rect(fill = "grey90"),
    axis.text.x = element_text(angle = 25, hjust = 1),
    panel.spacing = unit(0.8, "lines")
  )

plot_dir <- file.path(PLOTS_DIR, "combined")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

ggsave(
  file.path(plot_dir, "total_energy_violin_box_combined.png"),
  p,
  width = 13,
  height = 7,
  dpi = 160
)

# Stability by randomized repetition round: look for round-level drift after the longer cooldown.
trend_metrics<-c("total_energy_consumption_joules","execution_time_seconds","average_power_watts","peak_rss_bytes")
rep_trends<-clean %>% group_by(group,group_label,repetition,configuration,workload) %>%
  summarise(across(all_of(trend_metrics),\(x) median(x,na.rm=TRUE)),.groups="drop")
readr::write_csv(rep_trends,file.path(RESULTS_DIR,"repetition_round_stability.csv"))
for(g in GROUPS) for(m in trend_metrics) {
  label<-ifelse(g=="juliet","Juliet","Derived"); lab<-metric_labels[[m]]
  limits<-range(clean[[m]],finite=TRUE)
  p<-ggplot(filter(rep_trends,group==g),aes(repetition,.data[[m]],color=configuration,group=configuration))+geom_line()+geom_point(size=1.5)+
    facet_wrap(~workload,nrow=1,scales="fixed")+scale_y_log10(limits=limits)+
    labs(title=paste(label,lab,"by repetition round"),subtitle="Per-round median across program variants; diagnostic for drift after the cooldown change.",x="Repetition round",y=paste(lab,"(log scale)"))+theme_bw()
  ggsave(file.path(PLOTS_DIR,label,"exploration",paste0(m,"_by_repetition_round.png")),p,width=10,height=5.5,dpi=160)
}

# RQ2 overhead ratios matched at the same subject, workload, and repetition.
pair_runs <- clean %>% select(group,group_label,subject_id,family,workload,repetition,configuration,
  total_energy_consumption_joules,execution_time_seconds,runtime_seconds) %>%
  tidyr::pivot_wider(names_from=configuration,
    values_from=c(total_energy_consumption_joules,execution_time_seconds,runtime_seconds),names_sep="__")
for (cfg in SANITIZERS) {
  pair_runs[[paste0("energy_overhead_",cfg)]] <- pair_runs[[paste0("total_energy_consumption_joules__",cfg)]]/pair_runs[["total_energy_consumption_joules__baseline"]]
  pair_runs[[paste0("buildrun_time_overhead_",cfg)]] <- pair_runs[[paste0("execution_time_seconds__",cfg)]]/pair_runs[["execution_time_seconds__baseline"]]
  pair_runs[[paste0("runtime_only_overhead_",cfg)]] <- pair_runs[[paste0("runtime_seconds__",cfg)]]/pair_runs[["runtime_seconds__baseline"]]
}
ov <- pair_runs %>% select(group,group_label,subject_id,family,workload,repetition,
  starts_with("energy_overhead_"),starts_with("buildrun_time_overhead_"),starts_with("runtime_only_overhead_")) %>%
  tidyr::pivot_longer(cols=matches("^(energy|buildrun_time|runtime_only)_overhead_"),
    names_to=c("scope","configuration"),names_pattern="(energy|buildrun_time|runtime_only)_overhead_(.*)",values_to="factor") %>%
  tidyr::pivot_wider(names_from=scope,values_from=factor) %>% filter(is.finite(energy),is.finite(buildrun_time),is.finite(runtime_only))
readr::write_csv(ov,file.path(RESULTS_DIR,"overhead_factors_by_execution.csv"))
over_subject <- ov %>% group_by(group,group_label,subject_id,family,workload,configuration) %>%
  summarise(energy_overhead=mean(energy),buildrun_time_overhead=mean(buildrun_time),
            runtime_only_overhead=mean(runtime_only),.groups="drop")
readr::write_csv(over_subject,file.path(RESULTS_DIR,"overhead_factors_by_subject.csv"))

# Matched plots share the same x and y ranges across Juliet/Derived.
for (g in GROUPS) {
  label<-ifelse(g=="juliet","Juliet","Derived")
  dat<-filter(over_subject,group==g)
  gd<-file.path(PLOTS_DIR,label,"exploration"); dir.create(gd,recursive=TRUE,showWarnings=FALSE)
  energy_range<-range(over_subject$energy_overhead,finite=TRUE)
  time_range<-range(over_subject$buildrun_time_overhead,finite=TRUE)
  dat<-dat %>% mutate(log_time=log10(buildrun_time_overhead),log_energy=log10(energy_overhead))
  xloglim<-log10(time_range); yloglim<-log10(energy_range)
  p<-ggplot(dat,aes(log_time,log_energy,color=configuration))+geom_point(alpha=.75,size=2)+
    geom_smooth(aes(group=configuration,color=configuration),method="lm",formula=y~x,se=FALSE,linewidth=.7)+
    facet_wrap(~workload,nrow=1,scales="fixed")+
    scale_x_continuous(breaks=pretty(xloglim),labels=function(x) signif(10^x,2))+scale_y_continuous(breaks=pretty(yloglim),labels=function(x) signif(10^x,2))+coord_cartesian(xlim=xloglim,ylim=yloglim)+
    labs(title=paste(label,"Runtime and energy overhead"),subtitle="One point per subject, sanitizer, and workload; colored lines are log-log linear fits. Axes shared across groups.",x="Build-and-run time overhead factor (log scale)",y="Energy overhead factor (log scale)",color="Sanitizer")+theme_bw()
  ggsave(file.path(gd,"RQ2_runtime_vs_energy_overhead.png"),p,width=9,height=5.5,dpi=160)
}
message("Exploration outputs saved. Review IQR candidates and distributions before running hypothesis tests.")
