source(file.path("R Scripts", "00_config.R"))
ov<-readr::read_csv(file.path(RESULTS_DIR,"overhead_factors_by_subject.csv"),show_col_types=FALSE)
scopes<-c(energy_overhead="energy overhead",buildrun_time_overhead="build-and-run time overhead",
          runtime_only_overhead="runtime-only time overhead (sensitivity)")
omnibus_rows<-list(); posthoc_rows<-list(); diag_rows<-list(); kk<-1; pp<-1; dd<-1
for(g in GROUPS) for(scope in names(scopes)) for(cfg in SANITIZERS) for(wl in c("small","large")) {
  q<-ov %>% filter(group==g,configuration==cfg,workload==wl) %>% mutate(family=factor(family))
  if(nrow(q)==0) next
  y<-q[[scope]]; fit<-lm(y~family,data=q); resid<-residuals(fit)
  label<-paste(ifelse(g=="juliet","Juliet","Derived"),scopes[[scope]],cfg,wl,sep=" | ")
  stub<-safe_name(label)
  norm<-normality_check(resid,label,file.path(RESULTS_DIR,"statistics",ifelse(g=="juliet","Juliet","Derived"),"RQ4","qq",paste0(stub,"_residuals.png")))
  bart<-tryCatch(bartlett.test(y~family,data=q)$p.value,error=function(e) NA_real_)
  family_n<-q %>% count(family)
  diag_rows[[dd]]<-tibble::tibble(group=ifelse(g=="juliet","Juliet","Derived"),scope=scopes[[scope]],configuration=cfg,workload=wl,
     residual_n=norm$n_valid,residual_shapiro_w=norm$shapiro_w,residual_shapiro_p=norm$shapiro_p,
     bartlett_p=bart,min_subjects_per_family=min(family_n$n),max_subjects_per_family=max(family_n$n)); dd<-dd+1
  normal_ok<-!is.na(norm$shapiro_p)&&norm$shapiro_p>=ALPHA
  equal_var_ok<-!is.na(bart)&&bart>=ALPHA
  if(normal_ok&&equal_var_ok) {
    aov_fit<-aov(y~family,data=q); tab<-summary(aov_fit)[[1]]; pval<-tab[["Pr(>F)"]][1]
    eta<-tab[["Sum Sq"]][1]/sum(tab[["Sum Sq"]])
    omnibus_rows[[kk]]<-tibble::tibble(group=ifelse(g=="juliet","Juliet","Derived"),scope=scopes[[scope]],configuration=cfg,workload=wl,
       outcome=scope,test="one-way ANOVA",n=nrow(q),statistic=tab[["F value"]][1],p_value=pval,effect_size=eta,effect_size_type="eta squared",
       residual_shapiro_p=norm$shapiro_p,bartlett_p=bart,subjects_per_family=paste(family_n$n,collapse="/")); kk<-kk+1
    if(is.finite(pval)&&pval<ALPHA) {
      tk<-TukeyHSD(aov_fit)$family
      for(i in seq_len(nrow(tk))) {
        pair<-rownames(tk)[i]; combos<-combn(levels(q$family),2,simplify=FALSE); fams<-Filter(function(f) pair %in% c(paste(f[1],f[2],sep="-"),paste(f[2],f[1],sep="-")),combos)[[1]]; x<-q[[scope]][q$family==fams[1]]; z<-q[[scope]][q$family==fams[2]]
        posthoc_rows[[pp]]<-tibble::tibble(group=ifelse(g=="juliet","Juliet","Derived"),scope=scopes[[scope]],configuration=cfg,workload=wl,
          outcome=scope,pair=pair,method="Tukey HSD",p_adjustment="Tukey",p_adjusted=tk[i,"p adj"],cliffs_delta=cliffs_delta(x,z)); pp<-pp+1
      }
    }
  } else {
    kw<-kruskal.test(y~family,data=q); h<-unname(kw$statistic); kfam=nlevels(q$family)
    eps<-max(0,(h-kfam+1)/(nrow(q)-kfam))
    omnibus_rows[[kk]]<-tibble::tibble(group=ifelse(g=="juliet","Juliet","Derived"),scope=scopes[[scope]],configuration=cfg,workload=wl,
       outcome=scope,test="Kruskal-Wallis",n=nrow(q),statistic=h,p_value=kw$p.value,effect_size=eps,effect_size_type="epsilon squared",
       residual_shapiro_p=norm$shapiro_p,bartlett_p=bart,subjects_per_family=paste(family_n$n,collapse="/")); kk<-kk+1
    if(kw$p.value<ALPHA) {
      pw<-pairwise.wilcox.test(q[[scope]],q$family,p.adjust.method="holm",exact=FALSE)$p.value
      ij<-which(!is.na(pw),arr.ind=TRUE)
      for(i in seq_len(nrow(ij))) {
        r<-ij[i,1]; c<-ij[i,2]; fa<-rownames(pw)[r]; fb<-colnames(pw)[c]
        x<-q[[scope]][q$family==fa]; z<-q[[scope]][q$family==fb]
        posthoc_rows[[pp]]<-tibble::tibble(group=ifelse(g=="juliet","Juliet","Derived"),scope=scopes[[scope]],configuration=cfg,workload=wl,
          outcome=scope,pair=paste(fa,"vs",fb),method="pairwise Wilcoxon",p_adjustment="Holm",p_adjusted=pw[r,c],cliffs_delta=cliffs_delta(x,z)); pp<-pp+1
      }
    }
  }
}
omnibus<-bind_rows(omnibus_rows) %>% group_by(group,scope) %>% mutate(p_holm=p.adjust(p_value,"holm")) %>% ungroup()
posthoc<-bind_rows(posthoc_rows)
# Only interpret post-hoc tests after an omnibus result survives Holm correction.
if(nrow(posthoc)>0) {
  significant_omnibus<-omnibus %>% filter(p_holm<ALPHA) %>% select(group,scope,configuration,workload)
  posthoc<-posthoc %>% semi_join(significant_omnibus,by=c("group","scope","configuration","workload"))
}
readr::write_csv(omnibus,file.path(RESULTS_DIR,"RQ4_omnibus_tests.csv"))
readr::write_csv(posthoc,file.path(RESULTS_DIR,"RQ4_pairwise_tests.csv"))
readr::write_csv(bind_rows(diag_rows),file.path(RESULTS_DIR,"RQ4_assumption_checks.csv"))

# Show all observed program-subject points. Three variants per family/group are expected.
readr::write_csv(ov %>% group_by(group,configuration,workload,family) %>%
  summarise(n_subjects=n(),energy_mean=mean(energy_overhead),energy_median=median(energy_overhead),
            buildrun_time_mean=mean(buildrun_time_overhead),runtime_only_mean=mean(runtime_only_overhead),.groups="drop"),
  file.path(RESULTS_DIR,"RQ4_family_descriptives.csv"))
for(scope in names(scopes)) {
  vals<-if(scope=="energy_overhead") ov$energy_overhead else ov[[scope]]
  limits<-range(vals,finite=TRUE)
  for(g in GROUPS) {
    label<-ifelse(g=="juliet","Juliet","Derived")
    q<-ov %>% filter(group==g)
    p<-ggplot(q,aes(family,.data[[scope]],color=family))+geom_boxplot(aes(group=family),outlier.shape=NA,width=.55)+
      geom_jitter(width=.10,size=2,alpha=.85)+facet_grid(workload~configuration,scales="fixed")+
      scale_y_log10()+coord_cartesian(ylim=limits)+labs(title=paste(label,scopes[[scope]],"by error family"),
        subtitle="Each dot is a program-variant mean across 30 repetitions; common log scale across groups.",
        x="Memory-error family",y=paste(scopes[[scope]],"factor (log scale)"),color="Memory-error family")+theme_bw()+
      theme(legend.position="bottom",axis.text.x=element_text(angle=30,hjust=1))
    ggsave(file.path(PLOTS_DIR,label,"RQ4",paste0(scope,"_by_error_family.png")),p,width=14,height=7,dpi=160)
  }
}
message("RQ4 omnibus, post-hoc, effect-size and assumption tables are ready. Inspect the n-per-family column closely.")
