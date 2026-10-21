source(file.path("R Scripts", "00_config.R"))
clean<-readRDS(file.path(RESULTS_DIR,"analysis_ready_data.rds"))
subject_means<-clean %>% group_by(group,group_label,subject_id,family,workload,configuration) %>%
  summarise(average_power_watts=mean(average_power_watts),peak_power_watts=mean(peak_power_watts),
            power_variability_watts=mean(power_variability_watts),peak_rss_bytes=mean(peak_rss_bytes),.groups="drop")
metrics<-c("average_power_watts","peak_power_watts","power_variability_watts","peak_rss_bytes")
rows<-list(); kk<-1; diag_rows<-list(); dd<-1
for(g in GROUPS) for(m in metrics) for(cfg in CONFIGURATIONS) {
  w<-subject_means %>% filter(group==g,configuration==cfg) %>%
    select(subject_id,workload,value=all_of(m)) %>% pivot_wider(names_from=workload,values_from=value)
  label<-paste(ifelse(g=="juliet","Juliet","Derived"),m,cfg,"large minus small",sep=" | ")
  stub<-safe_name(label)
  res<-paired_test(w$small,w$large,label,alternative="two.sided",
                   qq_file=file.path(RESULTS_DIR,"statistics",ifelse(g=="juliet","Juliet","Derived"),"RQ3","qq",paste0(stub,".png")))
  rows[[kk]]<-res %>% mutate(group=ifelse(g=="juliet","Juliet","Derived"),measure=m,configuration=cfg,contrast_type="Large minus Small"); kk<-kk+1
  diag_rows[[dd]]<-tibble::tibble(group=ifelse(g=="juliet","Juliet","Derived"),contrast=label,n=res$n,shapiro_w=res$shapiro_w,shapiro_p=res$shapiro_p); dd<-dd+1
}
results<-bind_rows(rows) %>% group_by(group,measure) %>% mutate(p_holm=p.adjust(p_value,"holm")) %>% ungroup()

# Memory scaling: compare measured Large/Small peak-RSS ratio with subject-specific input_n ratio.
inputs<-clean %>% distinct(group,subject_id,workload,input_n) %>% pivot_wider(names_from=workload,values_from=input_n) %>%
  mutate(input_size_ratio=large/small) %>% select(group,subject_id,input_size_ratio)
mem<-subject_means %>% filter(configuration %in% CONFIGURATIONS) %>%
  select(group,subject_id,family,configuration,workload,peak_rss_bytes) %>%
  pivot_wider(names_from=workload,values_from=peak_rss_bytes) %>% left_join(inputs,by=c("group","subject_id")) %>%
  mutate(memory_ratio=large/small,log_ratio_departure=log(memory_ratio/input_size_ratio),
         relative_memory_change=memory_ratio-1)
readr::write_csv(mem,file.path(RESULTS_DIR,"RQ3_memory_and_input_scaling_ratios.csv"))
scale_rows<-list(); kk<-1
for(g in GROUPS) for(cfg in CONFIGURATIONS) {
  q<-mem %>% filter(group==g,configuration==cfg)
  label<-paste(ifelse(g=="juliet","Juliet","Derived"),"memory scaling ratio vs input-size ratio",cfg,sep=" | ")
  stub<-safe_name(label)
  res<-paired_test(rep(0,nrow(q)),q$log_ratio_departure,label,alternative="two.sided",
                   qq_file=file.path(RESULTS_DIR,"statistics",ifelse(g=="juliet","Juliet","Derived"),"RQ3","qq",paste0(stub,".png")))
  scale_rows[[kk]]<-res %>% mutate(group=ifelse(g=="juliet","Juliet","Derived"),measure="memory scaling",configuration=cfg,contrast_type="log[(RSS Large/Small)/(input_n Large/Small)] vs 0"); kk<-kk+1
}
scale_results<-bind_rows(scale_rows) %>% group_by(group) %>% mutate(p_holm=p.adjust(p_value,"holm")) %>% ungroup()
readr::write_csv(results,file.path(RESULTS_DIR,"RQ3_paired_workload_tests.csv"))
readr::write_csv(scale_results,file.path(RESULTS_DIR,"RQ3_memory_scaling_tests.csv"))
readr::write_csv(bind_rows(diag_rows),file.path(RESULTS_DIR,"RQ3_normality_diagnostics.csv"))

# Paired line plots show each program variant at both workloads.
for (m in metrics) {
  limits<-range(clean[[m]],finite=TRUE)
  for(g in GROUPS) {
    label<-ifelse(g=="juliet","Juliet","Derived")
    dat<-filter(subject_means,group==g)
    summ<-dat %>% group_by(configuration,workload) %>% summarise(n=n(),mean=mean(.data[[m]]),sd=sd(.data[[m]]),
      se=sd/sqrt(n),crit=qt(.975,n-1),lo=mean-crit*se,hi=mean+crit*se,.groups="drop")
    p<-ggplot(dat,aes(workload,.data[[m]]))+geom_line(aes(group=subject_id),color="grey70",alpha=.55)+
      geom_point(color="grey50",size=1.4,alpha=.7)+
      geom_line(data=summ,aes(workload,mean,group=1),inherit.aes=FALSE,color="#0072B2",linewidth=1)+
      geom_errorbar(data=summ,aes(workload,ymin=lo,ymax=hi),inherit.aes=FALSE,width=.10,color="#0072B2")+
      geom_point(data=summ,aes(workload,mean),inherit.aes=FALSE,color="#0072B2",shape=18,size=2.8)+
      facet_wrap(~configuration,nrow=1,scales="fixed")+scale_y_log10(limits=limits)+
      labs(title=paste(label,metric_labels[[m]],"by workload"),subtitle="Grey lines link each program variant. Blue line, diamonds, and 95% CIs summarize the 12 variant means. Shared scale across groups.",x="Workload size",y=paste(metric_labels[[m]],"(log scale)"))+theme_bw()
    ggsave(file.path(PLOTS_DIR,label,"RQ3",paste0(m,"_paired_workload.png")),p,width=13,height=5.5,dpi=160)
  }
}
message("RQ3 paired workload and memory scaling analyses are ready.")
