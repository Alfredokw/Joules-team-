source(file.path("R Scripts", "00_config.R"))
clean <- readRDS(file.path(RESULTS_DIR,"analysis_ready_data.rds"))
metrics_primary <- c("total_energy_consumption_joules","execution_time_seconds")
# runtime_seconds is retained as an execution-only sensitivity analysis; protocol energy scope is build-and-run.
metrics_sensitivity <- "runtime_seconds"
subject_means <- clean %>% group_by(group,group_label,subject_id,family,workload,configuration) %>%
  summarise(across(all_of(c(metrics_primary,metrics_sensitivity)),~mean(.x,na.rm=TRUE)),.groups="drop")
readr::write_csv(subject_means,file.path(RESULTS_DIR,"subject_mean_measurements.csv"))
all_rows<-list(); kk<-1; norm_rows<-list(); nn<-1
for (g in GROUPS) {
  label<-ifelse(g=="juliet","Juliet","Derived")
  gd<-file.path(RESULTS_DIR,"statistics",label,"RQ1"); dir.create(file.path(gd,"qq"),recursive=TRUE,showWarnings=FALSE)
  for (m in c(metrics_primary,metrics_sensitivity)) for (cfg in SANITIZERS) for (wl in c("small","large")) {
    wide<-subject_means %>% filter(group==g,workload==wl,configuration%in%c("baseline",cfg)) %>%
      select(subject_id,configuration,value=all_of(m)) %>% pivot_wider(names_from=configuration,values_from=value)
    lab<-paste(label,m,cfg,wl,sep=" | ")
    res<-paired_test(wide$baseline,wide[[cfg]],lab,alternative="greater",
      qq_file=file.path(gd,"qq",paste0(safe_name(lab),".png")))
    res$group<-label; res$measure<-m; res$sanitizer<-cfg; res$workload<-wl
    res$analysis_role<-if(m=="runtime_seconds") "runtime-only sensitivity" else "primary build-and-run analysis"
    all_rows[[kk]]<-res; kk<-kk+1
    norm_rows[[nn]]<-tibble::tibble(group=label,contrast=lab,n=res$n,shapiro_w=res$shapiro_w,shapiro_p=res$shapiro_p); nn<-nn+1
  }
}
results<-bind_rows(all_rows) %>% group_by(group,measure,analysis_role) %>% mutate(p_holm=p.adjust(p_value,method="holm")) %>% ungroup()
readr::write_csv(results,file.path(RESULTS_DIR,"RQ1_paired_baseline_tests.csv"))
readr::write_csv(bind_rows(norm_rows),file.path(RESULTS_DIR,"RQ1_normality_diagnostics.csv"))

# Paired subject-level overhead-factor plots. Baseline is the reference value 1.
# Grey lines connect each program variant's sanitizer ratios; colored points identify treatments.
for (g in GROUPS) {
 label<-ifelse(g=="juliet","Juliet","Derived")
 for (m in c(metrics_primary,metrics_sensitivity)) {
  base<-subject_means %>% filter(group==g,configuration=="baseline") %>% select(subject_id,workload,baseline=all_of(m))
  dat<-subject_means %>% filter(group==g,configuration%in%SANITIZERS) %>%
    left_join(base,by=c("subject_id","workload")) %>%
    mutate(overhead=.data[[m]]/baseline,configuration=factor(configuration,levels=SANITIZERS))
  all_base<-subject_means %>% filter(configuration=="baseline") %>% select(subject_id,workload,group,baseline=all_of(m))
  all_dat<-subject_means %>% filter(configuration%in%SANITIZERS) %>%
    left_join(all_base,by=c("subject_id","workload","group")) %>% mutate(overhead=.data[[m]]/baseline)
  all_summ<-all_dat %>% group_by(group,workload,configuration) %>% summarise(n=n(),log_mean=mean(log(overhead)),
    log_sd=sd(log(overhead)),crit=qt(.975,n-1),lo=exp(log_mean-crit*log_sd/sqrt(n)),hi=exp(log_mean+crit*log_sd/sqrt(n)),.groups="drop")
  summ<-all_summ %>% filter(group==g) %>% mutate(mean=exp(log_mean))
  ylim<-range(c(all_dat$overhead,all_summ$lo,all_summ$hi,1),finite=TRUE)
  p<-ggplot(dat,aes(configuration,overhead))+geom_hline(yintercept=1,linetype="dashed",color="grey45")+
    geom_line(aes(group=subject_id),color="grey70",alpha=.55,linewidth=.45)+
    geom_point(aes(color=configuration),position=position_jitter(width=.06,height=0),size=1.7,alpha=.7)+
    geom_line(data=summ,aes(configuration,mean,group=1),inherit.aes=FALSE,color="black",linewidth=.9)+
    geom_errorbar(data=summ,aes(configuration,ymin=lo,ymax=hi),inherit.aes=FALSE,width=.12,color="black")+
    geom_point(data=summ,aes(configuration,mean,color=configuration),inherit.aes=FALSE,shape=18,size=3.2)+
    facet_wrap(~workload,nrow=1,scales="fixed")+scale_y_log10()+coord_cartesian(ylim=ylim)+
    labs(title=paste(label,metric_labels[[m]],"overhead relative to baseline"),
      subtitle="Points = variant ratios (n=12); grey links pair variants; black diamond/bar = geometric mean and 95% CI; dashed = 1.",
      x="Sanitizer configuration",y=paste("Sanitizer / baseline",metric_labels[[m]],"ratio (log scale)"),color="Sanitizer")+
    theme_bw()+theme(legend.position="bottom",axis.text.x=element_text(angle=25,hjust=1))
  ggsave(file.path(PLOTS_DIR,label,"RQ1",paste0(m,"_paired_baseline.png")),p,width=10,height=5.5,dpi=160)
 }
}
message("RQ1 tables and paired plots are ready. Primary measures follow the report's build-and-run measurement scope; runtime_seconds is explicitly supplementary.")
