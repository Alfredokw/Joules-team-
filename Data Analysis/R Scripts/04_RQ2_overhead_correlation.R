source(file.path("R Scripts", "00_config.R"))
ov <- readr::read_csv(file.path(RESULTS_DIR,"overhead_factors_by_subject.csv"),show_col_types=FALSE)
# Primary analysis follows build-and-run time and energy measurement scope; runtime-only is supplementary.
analysis_scopes<-c(buildrun_time_overhead="primary build-and-run time",runtime_only_overhead="runtime-only sensitivity")
rows<-list(); kk<-1; diagnostics<-list(); dd<-1
for (g in GROUPS) for (scope in names(analysis_scopes)) for (cfg in SANITIZERS) for (wl in c("small","large")) {
  q<-ov %>% filter(group==g,configuration==cfg,workload==wl)
  x<-q[[scope]]; y<-q$energy_overhead
  stub<-safe_name(paste(g,scope,cfg,wl))
  nx<-normality_check(x,paste(scope,"x"),file.path(RESULTS_DIR,"statistics",ifelse(g=="juliet","Juliet","Derived"),"RQ2","qq",paste0(stub,"_time.png")))
  ny<-normality_check(y,paste(scope,"y"),file.path(RESULTS_DIR,"statistics",ifelse(g=="juliet","Juliet","Derived"),"RQ2","qq",paste0(stub,"_energy.png")))
  diagnostics[[dd]]<-tibble::tibble(group=ifelse(g=="juliet","Juliet","Derived"),scope=analysis_scopes[[scope]],configuration=cfg,workload=wl,variable=c("time_overhead","energy_overhead"),n=c(nx$n_valid,ny$n_valid),shapiro_w=c(nx$shapiro_w,ny$shapiro_w),shapiro_p=c(nx$shapiro_p,ny$shapiro_p)); dd<-dd+1
  normal<-!is.na(nx$shapiro_p)&&!is.na(ny$shapiro_p)&&nx$shapiro_p>=ALPHA&&ny$shapiro_p>=ALPHA
  method<-if(normal) "pearson" else "spearman"
  ct<-tryCatch(cor.test(x,y,method=method,alternative="greater",exact=FALSE),error=function(e) NULL)
  rows[[kk]]<-tibble::tibble(group=ifelse(g=="juliet","Juliet","Derived"),scope=analysis_scopes[[scope]],configuration=cfg,workload=wl,n=sum(is.finite(x)&is.finite(y)),method=method,correlation=if(is.null(ct)) NA_real_ else unname(ct$estimate),p_value=if(is.null(ct)) NA_real_ else ct$p.value); kk<-kk+1
}
results<-bind_rows(rows) %>% group_by(group,scope) %>% mutate(p_holm=p.adjust(p_value,"holm")) %>% ungroup()
readr::write_csv(results,file.path(RESULTS_DIR,"RQ2_correlation_tests.csv"))
readr::write_csv(bind_rows(diagnostics),file.path(RESULTS_DIR,"RQ2_normality_diagnostics.csv"))

# Subject-level scatterplots; axis limits are identical across Juliet and Derived.
for (scope in names(analysis_scopes)) {
  xlim<-log10(range(ov[[scope]],finite=TRUE)); ylim<-log10(range(ov$energy_overhead,finite=TRUE))
  xlab<-if(scope=="buildrun_time_overhead") "Build-and-run time overhead factor" else "Application runtime overhead factor"
  for (g in GROUPS) {
    label<-ifelse(g=="juliet","Juliet","Derived")
    q<-ov %>% filter(group==g) %>% mutate(log_time=log10(.data[[scope]]),log_energy=log10(energy_overhead))
    p<-ggplot(q,aes(log_time,log_energy,color=configuration))+geom_point(size=2,alpha=.75)+
      geom_smooth(aes(group=configuration,color=configuration),method="lm",formula=y~x,se=FALSE,linewidth=.7)+
      facet_wrap(~workload,nrow=1,scales="fixed")+
      scale_x_continuous(breaks=pretty(xlim),labels=function(x) signif(10^x,2))+scale_y_continuous(breaks=pretty(ylim),labels=function(x) signif(10^x,2))+coord_cartesian(xlim=xlim,ylim=ylim)+
      labs(title=paste(label,"Runtime and energy overhead"),subtitle=paste(analysis_scopes[[scope]],"; one point per subject; colored lines are log-log linear fits. Axes shared across groups."),x=paste0(xlab," (log scale)"),y="Energy overhead factor (log scale)",color="Sanitizer")+theme_bw()
    ggsave(file.path(PLOTS_DIR,label,"RQ2",paste0(scope,"_vs_energy_scatter.png")),p,width=9,height=5.5,dpi=160)
  }
}
message("RQ2 correlation tables and subject-level scatterplots are ready.")
