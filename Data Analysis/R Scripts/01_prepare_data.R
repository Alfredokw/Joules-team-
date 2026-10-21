source(file.path("R Scripts", "00_config.R"))
if (!file.exists(DATA_FILE)) stop("CSV not found. Edit DATA_FILE in 00_config.R: ", DATA_FILE)
raw <- readr::read_csv(DATA_FILE, show_col_types=FALSE, na=c("", "NA"))
required <- c("run_id","phase","repetition","subject_id","group","family","workload","input_n","configuration","cooldown_seconds","build_seconds","runtime_seconds","execution_time_seconds","total_energy_consumption_joules","average_power_watts","peak_power_watts","power_variability_watts","peak_rss_bytes","termination_status","workload_complete","valid","compile_return_code","runtime_return_code","measurement_return_code")
missing_cols <- setdiff(required, names(raw))
if (length(missing_cols)) stop("Missing expected columns: ", paste(missing_cols, collapse=", "))
raw <- raw %>% mutate(group=tolower(group), workload=tolower(workload), configuration=tolower(configuration))

# Execution status and exclusions are retained for transparent reporting.
status <- raw %>% count(group, phase, termination_status, workload_complete, valid,
                         compile_return_code, runtime_return_code, measurement_return_code, name="runs")
readr::write_csv(status, file.path(RESULTS_DIR,"execution_status_report.csv"))
warmups <- raw %>% filter(tolower(phase)=="warmup")
readr::write_csv(warmups, file.path(RESULTS_DIR,"warmup_rows_excluded.csv"))
noncomparable <- raw %>% filter(valid != 1 | workload_complete != 1 | termination_status != "completed")
readr::write_csv(noncomparable, file.path(RESULTS_DIR,"invalid_or_noncompleted_rows.csv"))

clean <- raw %>% filter(tolower(phase)!="warmup", valid==1, workload_complete==1,
                         termination_status=="completed", group %in% GROUPS,
                         configuration %in% CONFIGURATIONS, workload %in% c("small","large")) %>%
  mutate(group_label=if_else(group=="juliet","Juliet","Derived"),
         group=factor(group, levels=GROUPS),
         configuration=factor(configuration, levels=CONFIGURATIONS),
         workload=factor(workload, levels=c("small","large")),
         memory_mib=peak_rss_bytes/(1024^2))

# Verify the designed balanced repeated-measures structure (24 subjects x 10 cells x 30 repetitions).
cell_counts <- clean %>% count(group, subject_id, family, workload, configuration, name="runs") %>%
  mutate(across(c(group,workload,configuration),as.character))
readr::write_csv(cell_counts, file.path(RESULTS_DIR,"treatment_cell_counts.csv"))
subject_cells <- clean %>% distinct(group,subject_id,family) %>%
  mutate(group=as.character(group)) %>% tidyr::crossing(configuration=CONFIGURATIONS,workload=c("small","large"))
cell_counts <- subject_cells %>% left_join(cell_counts,by=c("group","subject_id","family","configuration","workload")) %>% mutate(runs=tidyr::replace_na(runs,0L))
missing_cells <- cell_counts %>% filter(runs != 30)
if (nrow(missing_cells)) warning("Some subject-treatment cells do not contain exactly 30 valid measured runs. Inspect treatment_cell_counts.csv before inference.")
if (anyDuplicated(clean$run_id)) warning("Duplicate run_id values detected.")

# Verify that recorded time columns match the report's build-and-run measurement scope.
if (all(c("build_seconds","runtime_seconds","execution_time_seconds") %in% names(clean))) {
  time_check <- clean %>% mutate(build_plus_runtime=build_seconds+runtime_seconds,
                                 difference=execution_time_seconds-build_plus_runtime) %>%
    summarise(n=n(),max_abs_difference=max(abs(difference),na.rm=TRUE),
              mean_abs_difference=mean(abs(difference),na.rm=TRUE))
  readr::write_csv(time_check, file.path(RESULTS_DIR,"execution_time_definition_check.csv"))
}
readr::write_csv(clean, file.path(RESULTS_DIR,"analysis_ready_data.csv"))
saveRDS(clean, file.path(RESULTS_DIR,"analysis_ready_data.rds"))

# Preserve outlier candidates for inspection; never remove IQR-flagged valid runs automatically.
measure_cols <- c("total_energy_consumption_joules","execution_time_seconds","runtime_seconds",
                  "average_power_watts","peak_power_watts","power_variability_watts","peak_rss_bytes")
long <- clean %>% select(run_id,group,group_label,subject_id,family,workload,configuration,repetition,all_of(measure_cols)) %>%
  tidyr::pivot_longer(cols=all_of(measure_cols), names_to="metric", values_to="value")
outlier_flags <- long %>% group_by(group,subject_id,workload,configuration,metric) %>%
  mutate(q1=quantile(value,.25,na.rm=TRUE),q3=quantile(value,.75,na.rm=TRUE),iqr=q3-q1,
         lower=q1-1.5*iqr,upper=q3+1.5*iqr,outlier_iqr=value<lower|value>upper) %>%
  ungroup() %>% filter(outlier_iqr) %>%
  select(run_id,group,subject_id,family,workload,configuration,repetition,metric,value,q1,q3,lower,upper)
readr::write_csv(outlier_flags,file.path(RESULTS_DIR,"iqr_outlier_candidates.csv"))
outlier_counts <- outlier_flags %>% count(group,metric,configuration,workload,name="flagged_runs")
readr::write_csv(outlier_counts,file.path(RESULTS_DIR,"iqr_outlier_counts.csv"))

cooldown_summary <- clean %>% distinct(group,subject_id,cooldown_seconds) %>%
  group_by(group) %>% summarise(subjects=n_distinct(subject_id),cooldown_min=min(cooldown_seconds),
                                cooldown_max=max(cooldown_seconds),.groups="drop")
readr::write_csv(cooldown_summary,file.path(RESULTS_DIR,"cooldown_by_group.csv"))
message("Prepared ",nrow(clean)," valid comparable executions. Outlier candidates remain included.")
