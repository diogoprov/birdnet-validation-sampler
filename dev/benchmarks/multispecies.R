# Run from the repository root: Rscript dev/benchmarks/multispecies.R
# Deliberately not run during vignette or site builds. Cached CSVs are rendered.
devtools::load_all(quiet=TRUE)
suppressPackageStartupMessages({library(dplyr);library(tidyr);library(readr)})
output <- 'inst/benchmarks'
dir.create(output,recursive=TRUE,showWarnings=FALSE)
seeds <- 2026:2045
scenarios <- c('global','species','site_species')
model_set <- calibration_models()
issues <- list()
record_issue <- function(type,text,context) {
 issues[[length(issues)+1L]] <<- tibble(context=context,type=type,text=text)
}
quiet <- function(expr,context) withCallingHandlers(expr,
 warning=function(w){record_issue('warning',conditionMessage(w),context);invokeRestart('muffleWarning')},
 message=function(m)invokeRestart('muffleMessage'))
simulate_data <- function(seed,scenario) withr::with_seed(seed, {
 sites <- sprintf('site%02d',1:6); species_levels <- sprintf('sp%02d',1:8)
 a <- rnorm(8,0,1); z <- rnorm(8); b <- pmax(.3,1.3+.35*(.25*a+sqrt(1-.25^2)*z))
 site_a <- rnorm(6,0,.35); cell_a <- matrix(rnorm(48,0,.8),6,8)
 if(scenario=='global'){a[]<-0;b[]<-1.3}
 if(scenario!='site_species'){site_a[]<-0;cell_a[]<-0}
 nights <- format(as.Date('2024-01-01')+0:35,'%Y%m%d')
 night_a <- matrix(rnorm(6*36,0,if(scenario=='global')0 else .25),6,36)
 d <- expand_grid(site=sites,species=species_levels,night=nights,clip=1:2) |>
   mutate(site=factor(site,levels=sites),species=factor(species,levels=species_levels),
    source_audio=paste(site,night,'220000.wav',sep='_'),confidence=runif(n(),.1,.9995),
    logit_conf=qlogis(confidence),si=as.integer(site),sp=as.integer(species),ni=match(night,nights),
    p_truth=plogis(-.8+a[sp]+b[sp]*logit_conf+site_a[si]+cell_a[cbind(si,sp)]+night_a[cbind(si,ni)]),
    tp=rbinom(n(),1,p_truth),phase=if_else(ni<=24,'train','test'))
 d
})
score_metrics <- function(tp,p) {
 p<-pmin(pmax(p,1e-6),1-1e-6)
 tibble(logloss=-mean(tp*log(p)+(1-tp)*log1p(-p)),brier=mean((p-tp)^2),
 auc=as.numeric(pROC::auc(pROC::roc(tp,p,levels=c(0,1),direction='<',quiet=TRUE))))
}
results <- list(); comparisons <- list(); cells <- list(); designs <- list(); pairwise <- list()
start <- proc.time()[['elapsed']]
for(scenario in scenarios)for(seed in seeds){
 context <- paste(scenario,seed)
 d <- simulate_data(seed,scenario)
 tr <- filter(d,phase=='train'); te <- filter(d,phase=='test')
 # Acoustic groups span species; no night in the external test is reviewed.
 stopifnot(!any(paste(tr$site,tr$night)%in%paste(te$site,te$night)))
 folds <- calibration_folds(tr,k_folds=5,seed=seed,fold_group='night')
 stopifnot(all(vapply(split(folds,paste(tr$site,tr$night)),function(f)length(unique(f))==1L,logical(1))))
 t0 <- proc.time()[['elapsed']]
 cv <- quiet(compare_calibration_models(tr,model_set,k_folds=5,seed=seed,fold_group='night'),context)
 cv_seconds <- proc.time()[['elapsed']]-t0
 comparisons[[length(comparisons)+1L]] <- mutate(cv,scenario=scenario,seed=seed)
 designs[[length(designs)+1L]] <- tibble(scenario=scenario,seed=seed,sites=n_distinct(d$site),species=n_distinct(d$species),
   train_nights=24L,test_nights=12L,train_windows=nrow(tr),test_windows=nrow(te),cv_seconds=cv_seconds)
 true_scored <- transmute(te,site,species,night,p_tp=as.numeric(tp))
 true_h <- detection_history(true_scored,p_min=.95)
 truth_matrix <- community_matrices(true_h,levels(te$species),k_min=1,min_nights_month=1)$frequency
 histories <- list(); cores <- list()
 for(rule in c('best_auc','one_se_logloss')){
   nm <- select_calibration_model(cv,rule,k_folds=5)
   t0 <- proc.time()[['elapsed']]
   fit <- quiet(fit_calibration(tr,model_set[[nm]]),paste(context,rule,'final'))
   fit_seconds <- proc.time()[['elapsed']]-t0
   p <- if(inherits(fit,'merMod'))as.numeric(predict(fit,newdata=te,type='response',allow.new.levels=TRUE)) else as.numeric(predict(fit,newdata=te,type='response'))
   stopifnot(length(p)==nrow(te),all(is.finite(p)))
   sc <- transmute(te,site,species,night,p_tp=p)
   h <- detection_history(sc,p_min=.95)
   s <- cell_status(fit,tr,p_min=.95,min_n=15)
   core <- suggest_core_species(s)
   histories[[rule]]<-h;cores[[rule]]<-core
   cells[[length(cells)+1L]] <- mutate(s,scenario=scenario,seed=seed,rule=rule)
   hm <- left_join(h |> select(site,species,night,predicted=detection),true_h |> select(site,species,night,truth=detection),by=c('site','species','night'))
   mat <- community_matrices(h,levels(te$species),k_min=1,min_nights_month=1)$frequency
   ids <- c('site','month','n_nights_recorded'); sp <- levels(te$species)
   stopifnot(identical(mat[ids],truth_matrix[ids]))
   n_tp <- sum(hm$predicted==1&hm$truth==1);n_fp<-sum(hm$predicted==1&hm$truth==0)
   results[[length(results)+1L]] <- bind_cols(tibble(scenario=scenario,seed=seed,rule=rule,model=nm,
      singular=inherits(fit,'merMod')&&lme4::isSingular(fit),fit_seconds=fit_seconds,core_species=length(core),core_codes=paste(core,collapse=';'),
      detected_nights=sum(hm$predicted),true_detection_nights=sum(hm$truth),night_precision=if(n_tp+n_fp>0)n_tp/(n_tp+n_fp)else NA_real_,
      night_sensitivity=n_tp/sum(hm$truth),matrix_mae=mean(abs(as.matrix(mat[sp])-as.matrix(truth_matrix[sp])))),score_metrics(te$tp,p))
 }
 a<-histories$best_auc;b<-histories$one_se_logloss
 stopifnot(identical(a[c('site','species','night')],b[c('site','species','night')]))
 pairwise[[length(pairwise)+1L]] <- tibble(scenario=scenario,seed=seed,changed_nights=sum(a$detection!=b$detection),
   total_site_species_nights=nrow(a),core_jaccard=if(length(union(cores$best_auc,cores$one_se_logloss)))length(intersect(cores$best_auc,cores$one_se_logloss))/length(union(cores$best_auc,cores$one_se_logloss)) else 1)
 # Checkpoint each completed replicate so interrupted runs remain inspectable.
 write_csv(bind_rows(results),file.path(output,'multispecies-results.csv'))
 write_csv(bind_rows(comparisons),file.path(output,'multispecies-cv.csv'))
 write_csv(bind_rows(cells),file.path(output,'multispecies-cells.csv'))
 write_csv(bind_rows(designs),file.path(output,'multispecies-design.csv'))
 write_csv(bind_rows(pairwise),file.path(output,'multispecies-changes.csv'))
 cat(context,'complete;',round(proc.time()[['elapsed']]-start,1),'seconds elapsed\n')
}
write_csv(bind_rows(issues),file.path(output,'multispecies-fit-issues.csv'))
writeLines(capture.output(sessionInfo()),file.path(output,'multispecies-session.txt'))
# Twenty replicates per scenario quantify simulation variability; use paired deltas.
r<-bind_rows(results)
summary<-r |> group_by(scenario,rule) |> summarise(replicates=n(),across(c(logloss,brier,auc,matrix_mae,core_species,night_precision,night_sensitivity),list(mean=~mean(.x,na.rm=TRUE),sd=~sd(.x,na.rm=TRUE))),.groups='drop')
write_csv(summary,file.path(output,'multispecies-summary.csv'))
pairs<-r |> select(scenario,seed,rule,logloss,brier,matrix_mae) |> pivot_wider(names_from=rule,values_from=c(logloss,brier,matrix_mae)) |>
 mutate(delta_logloss=logloss_one_se_logloss-logloss_best_auc,delta_brier=brier_one_se_logloss-brier_best_auc,delta_matrix_mae=matrix_mae_one_se_logloss-matrix_mae_best_auc)
write_csv(pairs,file.path(output,'multispecies-paired.csv'))
print(summary)
