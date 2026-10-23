devtools::load_all(quiet=TRUE)
suppressPackageStartupMessages({library(dplyr);library(tidyr);library(readr)})
b<-function(f)read_csv(file.path('inst/benchmarks',f),show_col_types=FALSE)
r<-b('multispecies-results.csv');cv<-b('multispecies-cv.csv');d<-b('multispecies-design.csv')
p<-b('multispecies-paired.csv');s<-b('multispecies-summary.csv');ch<-b('multispecies-changes.csv')
stopifnot(nrow(r)==120L,nrow(d)==60L,nrow(cv)==300L,nrow(p)==60L,nrow(ch)==60L)
stopifnot(nrow(distinct(r,scenario,seed,rule))==nrow(r),nrow(distinct(d,scenario,seed))==60L,
 all(d$train_windows==2304),all(d$test_windows==1152),all(ch$total_site_species_nights==576),
 all(is.finite(r$logloss)),all(is.finite(r$brier)),all(r$brier>=0&r$brier<=1),all(r$matrix_mae>=0&r$matrix_mae<=1),sum(cv$n_failed)==0)
# Independent checks from saved comparisons, not just displayed summaries.
for(i in seq_len(nrow(r))){
 c<-filter(cv,scenario==r$scenario[i],seed==r$seed[i])
 stopifnot(select_calibration_model(c,r$rule[i],5)==r$model[i])
}
calc<-r |> group_by(scenario,rule) |> summarise(logloss=mean(logloss),brier=mean(brier),.groups='drop')
j<-left_join(calc,s,by=c('scenario','rule'))
stopifnot(max(abs(j$logloss-j$logloss_mean))<1e-12,max(abs(j$brier-j$brier_mean))<1e-12)
calc<-r |> select(scenario,seed,rule,logloss) |> pivot_wider(names_from=rule,values_from=logloss) |>
 mutate(delta=one_se_logloss-best_auc) |> left_join(p,by=c('scenario','seed'))
stopifnot(max(abs(calc$delta-calc$delta_logloss))<1e-12)
c<-b('curiango-native.csv');stopifnot(nrow(c)==4L,all(c$failed_fits==0),max(c$max_logloss_difference)<1e-12)
reg<-b('curiango-cell-status-after-fix.csv')
stopifnot(nrow(reg)==56L,sum(reg$status_before!=reg$status)==12L,all(reg$status==reg$status_endpoint))
cat('PASS: 60 simulation datasets, 1500 successful CV fits, 120 rule outcomes;\n')
cat('cached selections and paired losses independently checked; native Curiango\n')
cat('comparison matches, and all 12 cell-status regressions remain fixed.\n')
