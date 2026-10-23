# Reproduce the Curiango report with an explicit candidate family.
# Run from the repository root: Rscript dev/benchmarks/curiango.R [DATA_DIR OUTPUT_DIR]
# This is the historical benchmark; native automatic-family verification is
# in dev/benchmarks/curiango-native.R. No network access during vignette builds.
# Dependencies: sheepdog >= 3.1.0 (or devtools for a local checkout), dplyr,
# readr, tibble, lme4, pROC, ggplot2, jsonlite.
args <- commandArgs(trailingOnly = TRUE)
data_dir <- if (length(args)) args[1] else 'dev/benchmarks/data/curiango'
out <- if (length(args)>1) args[2] else 'dev/benchmarks/results/curiango'
devtools::load_all(if(length(args)>2)args[3]else'.',quiet=TRUE)
stopifnot(packageVersion('sheepdog') >= '3.1.0')
suppressPackageStartupMessages({library(dplyr); library(readr); library(tibble); library(ggplot2)})
dir.create(out, recursive=TRUE, showWarnings=FALSE)
writeLines(capture.output(sessionInfo()), file.path(out,'session-info.txt'))
file.copy('inst/benchmarks/curiango-source-manifest.json', file.path(out,'source_manifest.json'), overwrite=TRUE)
manifest <- jsonlite::fromJSON(file.path(out,'source_manifest.json'))
for (i in seq_len(nrow(manifest$files))) {
  f <- manifest$files[i,]; path <- file.path(data_dir,f$file)
  if (!file.exists(path)) {dir.create(data_dir, recursive=TRUE,showWarnings=FALSE); download.file(f$url,path,mode='wb',method='libcurl')}
  stopifnot(paste0('md5:',tools::md5sum(path)) == f$checksum)
}
logfile <- file.path(out,'progress.log'); writeLines('Benchmark sheepdog 3.0.0; seed 2026; 5 folds',logfile)
progress <- function(...) {s <- paste(...,collapse=' '); cat(s,'\n'); cat(s,'\n',file=logfile,append=TRUE)}
issues <- list()
quiet_fit <- function(formula,d,context='') {
  withCallingHandlers(tryCatch(sheepdog::fit_calibration(d,formula),error=function(e){
    issues[[length(issues)+1L]] <<- tibble(context=context,type='error',text=conditionMessage(e)); NULL
  }),warning=function(w){issues[[length(issues)+1L]] <<- tibble(context=context,type='warning',text=conditionMessage(w)); invokeRestart('muffleWarning')},message=function(m) invokeRestart('muffleMessage'))
}
predict_p <- function(fit,d) {
  if (inherits(fit,'merMod')) as.numeric(predict(fit,newdata=d,type='response',allow.new.levels=TRUE)) else as.numeric(predict(fit,newdata=d,type='response'))
}
metrics <- function(y,p) {
  z <- pmin(pmax(p,1e-6),1-1e-6); lp <- qlogis(z)
  cal <- suppressWarnings(glm(y~lp,family=binomial()))
  # Joint intercept and slope; also output offset calibration-in-the-large.
  citl <- suppressWarnings(glm(y~1+offset(lp),family=binomial()))
  tibble(n=length(y),logloss=-mean(y*log(z)+(1-y)*log1p(-z)),
         brier=mean((p-y)^2),auc=if(length(unique(y))==2) as.numeric(pROC::auc(pROC::roc(y,p,levels=c(0,1),direction='<',quiet=TRUE))) else NA_real_,
         cal_intercept=unname(coef(citl)[1]),cal_slope=unname(coef(cal)[2]))
}
models <- list(m0_global=tp~logit_conf,
               m1_site_intercept=tp~logit_conf+(1|site),
               m2_site_slope=tp~logit_conf+(logit_conf|site))
rules <- c('best_auc','one_se_logloss')
make_folds <- function(d,mode,seed,k=5) {
  # Group whole recordings/nights, stratified by physical site. Never split
  # one group between train/test. Identical assignment for all candidates.
  d$.group <- if(mode=='night') d$night_id else d$filename
  groups <- d |> distinct(site,.group) |> arrange(site,.group)
  groups <- withr::with_seed(seed,groups |> group_by(site) |> mutate(fold=sample(rep_len(seq_len(k),n()))) |> ungroup())
  left_join(d |> mutate(.row=seq_len(n())),groups,by=c('site','.group')) |> arrange(.row) |> pull(fold)
}
compare_grouped <- function(d,mode,seed,context) {
  folds <- make_folds(d,mode,seed)
  bind_rows(lapply(seq_along(models),function(i) {
    nm <- names(models)[i]
    m <- bind_rows(lapply(1:5,function(k) {
      fit <- quiet_fit(models[[i]],d[folds!=k,],paste(context,nm,k))
      if(is.null(fit)) return(tibble(fold=k,logloss=NA_real_,brier=NA_real_,auc=NA_real_,cal_intercept=NA_real_,cal_slope=NA_real_,singular=NA_real_))
      bind_cols(tibble(fold=k),metrics(d$tp[folds==k],predict_p(fit,d[folds==k,]))) |>
        mutate(singular=as.numeric(inherits(fit,'merMod') && lme4::isSingular(fit)))
    }))
    tibble(model=nm,formula=deparse1(models[[i]]),auc_mean=mean(m$auc,na.rm=TRUE),auc_sd=sd(m$auc,na.rm=TRUE),
           logloss_mean=mean(m$logloss,na.rm=TRUE),logloss_sd=sd(m$logloss,na.rm=TRUE),
           brier_mean=mean(m$brier,na.rm=TRUE),brier_sd=sd(m$brier,na.rm=TRUE),
           cal_intercept=mean(m$cal_intercept,na.rm=TRUE),cal_slope=mean(m$cal_slope,na.rm=TRUE),
           prop_singular=mean(m$singular,na.rm=TRUE),n_failed=sum(is.na(m$logloss)),complexity=i)
  })) |> arrange(desc(auc_mean))
}
raw <- list(BirdNET=read_csv(file.path(data_dir,'CM-BirdNet.txt'),show_col_types=FALSE),
            Custom=read_csv(file.path(data_dir,'CM-Custom.txt'),show_col_types=FALSE))
full <- read_tsv(file.path(data_dir,'df_night_clean.txt'),show_col_types=FALSE)
# The deposited table has multiple rows per minute, with no window offset.
# Aggregate scores at minute resolution before counting reliable minutes.
minutes <- full |> group_by(Site,DataHora_Formatada,night) |>
  summarise(conf_preb=max(conf_preb,na.rm=TRUE),conf_div=max(conf_div,na.rm=TRUE),.groups='drop')
write_csv(tibble(full_rows=nrow(full),unique_minutes=nrow(minutes),site_nights=n_distinct(paste(minutes$Site,minutes$night))),file.path(out,'full_data_audit.csv'))
rm(full); gc()
cv_all <- list(); selections <- list(); oof_all <- list(); fold_results <- list(); audits <- list(); counts <- list(); histories <- list(); shifts <- list(); fitdiag <- list(); thresholds <- list(); finalfits <- list()
for (classifier in names(raw)) {
  cm <- raw[[classifier]]
  stopifnot(!anyDuplicated(cm$id),all(cm$compau_annotation %in% 0:1),all(is.finite(cm$compau_confidence)),all(cm$compau_confidence>=0 & cm$compau_confidence<=1))
  d0 <- cm |> mutate(site=factor(Site),species=factor('Nyctidromus_albicollis'),confidence=compau_confidence,tp=as.integer(compau_annotation),
                      stamp=sub('.*_([0-9]{8}_[0-9]{6})$','\\1',filename),
                      date=as.Date(substr(stamp,1,8),'%Y%m%d'),
                      night=date-as.integer(as.integer(substr(stamp,10,11))<12),
                      night_id=paste(Site,night),logit_conf=qlogis(pmin(pmax(confidence,1e-4),1-1e-4)))
  stopifnot(!anyNA(d0$night),!anyNA(d0$tp))
  d <- filter(d0,confidence>=.1)
  counts[[classifier]] <- d0 |> group_by(site) |> summarise(classifier=classifier,windows=n(),recordings=n_distinct(filename),tp=sum(tp),
                     calibration_windows=sum(confidence>=.1),calibration_tp=sum(compau_annotation[compau_confidence>=.1]),calibration_recordings=n_distinct(filename[confidence>=.1]),calibration_nights=n_distinct(night_id[confidence>=.1]),.groups='drop')
  # Explicit audit of the unmodified default multispecies family.
  audits[[classifier]] <- bind_rows(lapply(names(calibration_models()),function(nm){
    f <- quiet_fit(calibration_models()[[nm]],d,paste('default-audit',classifier,nm))
    tibble(classifier=classifier,model=nm,estimable=!is.null(f))
  }))
  progress(classifier,nrow(d),'calibration windows; nested cross-validation')
  for(mode in c('night','recording')) {
    outer <- make_folds(d,mode,2026)
    for(k in 1:5) {
      train <- d[outer!=k,]; test <- d[outer==k,]
      stopifnot(!any((if(mode=='night')train$night_id else train$filename) %in% (if(mode=='night')test$night_id else test$filename)))
      cv <- compare_grouped(train,mode,2026+k,paste('inner',classifier,mode,k))
      cv_all[[length(cv_all)+1L]] <- mutate(cv,classifier=classifier,scheme=mode,outer_fold=k)
      for(rule in rules) {
        nm <- select_calibration_model(cv,rule,k_folds=5)
        f <- quiet_fit(models[[nm]],train,paste('outer',classifier,mode,k,rule))
        stopifnot(!is.null(f)); p <- predict_p(f,test)
        oof_all[[length(oof_all)+1L]] <- test |> select(id,filename,site,night,night_id,tp,confidence) |>
          mutate(classifier=classifier,scheme=mode,fold=k,rule=rule,model=nm,p=p)
        fold_results[[length(fold_results)+1L]] <- bind_cols(tibble(classifier=classifier,scheme=mode,fold=k,rule=rule,model=nm),metrics(test$tp,p))
      }
      progress(classifier,mode,'outer fold',k,'complete')
    }
  }
  # Exact production CV (clip folds), repeated seeds: descriptive stability,
  # not used as an unbiased estimate of selected-rule performance.
  for(seed in 2026:2030) {
    cv <- withCallingHandlers(compare_calibration_models(d,models,k_folds=5,seed=seed),warning=function(w) invokeRestart('muffleWarning'),message=function(m) invokeRestart('muffleMessage'))
    cv_all[[length(cv_all)+1L]] <- mutate(cv,classifier=classifier,scheme='clip_production',outer_fold=NA_integer_,seed=seed)
    for(rule in rules) selections[[length(selections)+1L]] <- tibble(classifier=classifier,scheme='clip_production',seed=seed,rule=rule,model=select_calibration_model(cv,rule,5))
  }
  progress(classifier,'fitting full-data models and scoring survey')
  for(mode in c('night','clip_production')) {
    cv <- if(mode=='night') compare_grouped(d,mode,2026,paste('full',classifier)) else withCallingHandlers(compare_calibration_models(d,models,5,2026),warning=function(w)invokeRestart('muffleWarning'),message=function(m)invokeRestart('muffleMessage'))
    cv_all[[length(cv_all)+1L]] <- mutate(cv,classifier=classifier,scheme=paste0(mode,'_full'),outer_fold=NA_integer_)
    for(rule in rules) {
      nm <- select_calibration_model(cv,rule,5)
      f <- quiet_fit(models[[nm]],d,paste('final',classifier,mode,rule)); stopifnot(!is.null(f))
      finalfits[[paste(classifier,mode,rule,sep='_')]] <- f
      fitdiag[[length(fitdiag)+1L]] <- tibble(classifier=classifier,scheme=mode,rule=rule,model=nm,singular=inherits(f,'merMod') && lme4::isSingular(f),
         convergence=if(inherits(f,'merMod'))paste(f@optinfo$conv$lme4$messages,collapse='; ') else '')
      sc <- minutes |> transmute(site=factor(Site,levels=levels(d$site)),night,stamp=DataHora_Formatada,
               species=factor('Nyctidromus_albicollis',levels=levels(d$species)),confidence=if(classifier=='BirdNET')conf_preb else conf_div) |>
        mutate(logit_conf=qlogis(pmin(pmax(confidence,1e-4),1-1e-4)),eligible=confidence>=.1)
      sc$p <- predict_p(f,sc)
      sc <- sc |> mutate(reliable=eligible & p>=.95,
          reviewed_recording=paste(site,stamp) %in% paste(d0$site,d0$stamp))
      h <- sc |> group_by(site,night) |> summarise(minutes=n(),eligible_minutes=sum(eligible),reliable_minutes=sum(reliable),
          reliable_minutes_unreviewed=sum(reliable & !reviewed_recording),.groups='drop') |>
        mutate(classifier=classifier,scheme=mode,rule=rule,model=nm,present=reliable_minutes>=1,present_unreviewed=reliable_minutes_unreviewed>=1)
      histories[[length(histories)+1L]] <- h
      pred <- data.frame(site=d$site,logit_conf=d$logit_conf,species=d$species)
      grid <- expand.grid(site=levels(d$site),confidence=seq(.1,1,by=.0001)) |>
        mutate(site=factor(site,levels=levels(d$site)),species=factor('Nyctidromus_albicollis',levels=levels(d$species)),logit_conf=qlogis(pmin(pmax(confidence,1e-4),1-1e-4)))
      grid$p <- predict_p(f,grid)
      thresholds[[length(thresholds)+1L]] <- grid |> group_by(site) |> summarise(score_at_p95=if(any(p>=.95))min(confidence[p>=.95])else NA_real_,.groups='drop') |>
        mutate(classifier=classifier,scheme=mode,rule=rule,model=nm)
      shifts[[length(shifts)+1L]] <- sc |> select(site,night,stamp,confidence,p,eligible,reliable) |> mutate(classifier=classifier,scheme=mode,rule=rule)
    }
  }
}
oof <- bind_rows(oof_all); folds <- bind_rows(fold_results); cv <- bind_rows(cv_all); sel <- bind_rows(selections)
summary <- oof |> group_by(classifier,scheme,rule) |> group_modify(~metrics(.x$tp,.x$p)) |> ungroup()
paired <- oof |> select(classifier,scheme,id,filename,site,night_id,tp,rule,p) |> tidyr::pivot_wider(names_from=rule,values_from=p)
# Paired bootstrap of entire site-nights, conditional on the stored OOF
# predictions. Does not include uncertainty from refitting the CV models.
boot <- paired |> group_by(classifier,scheme) |> group_modify(function(z,key){
  cl <- z |> mutate(delta_logloss=-(tp*log(pmax(one_se_logloss,1e-6))+(1-tp)*log(pmax(1-one_se_logloss,1e-6)))+
                    (tp*log(pmax(best_auc,1e-6))+(1-tp)*log(pmax(1-best_auc,1e-6))),
                    delta_brier=(one_se_logloss-tp)^2-(best_auc-tp)^2) |>
    group_by(night_id) |> summarise(n=n(),dll=sum(delta_logloss),db=sum(delta_brier),.groups='drop')
  b <- withr::with_seed(2026,replicate(2000,{i<-sample.int(nrow(cl),nrow(cl),replace=TRUE);c(logloss=sum(cl$dll[i])/sum(cl$n[i]),brier=sum(cl$db[i])/sum(cl$n[i]))}))
  tibble(delta_logloss=sum(cl$dll)/sum(cl$n),logloss_low=quantile(b[1,],.025),logloss_high=quantile(b[1,],.975),
         delta_brier=sum(cl$db)/sum(cl$n),brier_low=quantile(b[2,],.025),brier_high=quantile(b[2,],.975),n_site_nights=nrow(cl))
}) |> ungroup()
history <- bind_rows(histories)
hpair <- history |> select(classifier,scheme,site,night,rule,reliable_minutes,present,present_unreviewed) |> tidyr::pivot_wider(names_from=rule,values_from=c(reliable_minutes,present,present_unreviewed)) |>
 mutate(changed=present_one_se_logloss!=present_best_auc,changed_unreviewed=present_unreviewed_one_se_logloss!=present_unreviewed_best_auc)
hsummary <- hpair |> group_by(classifier,scheme) |> summarise(site_nights=n(),presences_auc=sum(present_best_auc),presences_logloss=sum(present_one_se_logloss),changed=sum(changed),
    gained=sum(present_one_se_logloss & !present_best_auc),lost=sum(present_best_auc & !present_one_se_logloss),
    presences_auc_unreviewed=sum(present_unreviewed_best_auc),presences_logloss_unreviewed=sum(present_unreviewed_one_se_logloss),changed_unreviewed=sum(changed_unreviewed),.groups='drop')
pwide <- bind_rows(shifts) |> tidyr::pivot_wider(names_from=rule,values_from=c(p,reliable)) |>
 mutate(delta_p=p_one_se_logloss-p_best_auc)
psummary <- pwide |> filter(eligible) |> group_by(classifier,scheme) |> summarise(n=n(),mean_abs_shift=mean(abs(delta_p)),max_abs_shift=max(abs(delta_p)),reliable_auc=sum(reliable_best_auc),reliable_logloss=sum(reliable_one_se_logloss),.groups='drop')
files <- list(data_counts=bind_rows(counts),default_family_audit=bind_rows(audits),cv_comparisons=cv,production_seed_selections=sel,nested_fold_metrics=folds,
 nested_oof_predictions=oof,nested_metrics=summary,paired_bootstrap=boot,final_model_diagnostics=bind_rows(fitdiag),score_thresholds=bind_rows(thresholds),
 nightly_histories=history,nightly_changes=hpair,nightly_summary=hsummary,probability_shifts=psummary,fit_issues=bind_rows(issues))
for(nm in names(files)) write_csv(files[[nm]],file.path(out,paste0(nm,'.csv')))
saveRDS(finalfits,file.path(out,'final_calibration_models.rds'))
# Publication-style static plots, based on held-out predictions.
p1 <- summary |> filter(scheme=='night') |> select(classifier,rule,logloss,brier,auc) |> tidyr::pivot_longer(c(logloss,brier,auc)) |>
 ggplot(aes(x=classifier,y=value,colour=rule,group=rule))+geom_point(position=position_dodge(width=.35),size=3)+facet_wrap(~name,scales='free_y')+
 labs(x=NULL,y='Desempenho em dados de teste',colour='Regra',title='Curiango: validação cruzada aninhada',subtitle='Cinco folds externos e internos; noites inteiras separadas entre treino e teste')+theme_bw(base_size=11)+theme(legend.position='bottom')
ggsave(file.path(out,'nested-performance.png'),p1,width=9,height=4,dpi=180)
bins <- oof |> filter(scheme=='night') |> mutate(bin=cut(p,breaks=seq(0,1,.1),include.lowest=TRUE)) |> group_by(classifier,rule,bin) |>
 summarise(predicted=mean(p),observed=mean(tp),n=n(),.groups='drop')
p2 <- ggplot(bins,aes(predicted,observed,colour=rule))+geom_abline(slope=1,intercept=0,linetype=2,colour='grey50')+geom_line()+geom_point(aes(size=n))+facet_wrap(~classifier)+coord_equal(xlim=c(0,1),ylim=c(0,1))+
 labs(x='Probabilidade prevista (fora do treino)',y='Fração de positivos revisados',colour='Regra',size='Janelas',title='Confiabilidade das probabilidades calibradas')+theme_bw(base_size=11)+theme(legend.position='bottom')
ggsave(file.path(out,'reliability.png'),p2,width=8,height=4.8,dpi=180)
p3 <- history |> filter(scheme=='night') |> group_by(classifier,rule,site) |> summarise(presences=sum(present),.groups='drop') |>
 ggplot(aes(site,presences,fill=rule))+geom_col(position='dodge')+facet_wrap(~classifier)+labs(x='Local',y='Noites com detecção confiável',fill='Regra',title='Impacto na série completa',subtitle='P(TP) ≥ 0,95; ao menos uma gravação elegível por noite')+theme_bw(base_size=11)+theme(legend.position='bottom')
ggsave(file.path(out,'nightly-impact.png'),p3,width=9,height=4.5,dpi=180)
progress('COMPLETE');print(summary); print(boot);print(hsummary);print(bind_rows(fitdiag))
