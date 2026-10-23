# Run from repo root: Rscript dev/benchmarks/curiango-native.R [DATA_DIR]
# Missing evaluation tables are downloaded with pinned Zenodo MD5 checksums.
devtools::load_all(quiet=TRUE)
suppressPackageStartupMessages({library(dplyr);library(readr)})
a<-commandArgs(trailingOnly=TRUE)
data_dir<-if(length(a))a[1]else'dev/benchmarks/data/curiango'
out<-'inst/benchmarks'
manifest<-jsonlite::fromJSON(file.path(out,'curiango-source-manifest.json'))
dir.create(data_dir,recursive=TRUE,showWarnings=FALSE)
ref<-read_csv(file.path(out,'curiango-cv-comparisons.csv'),show_col_types=FALSE)
result<-list();comparisons<-list();timings<-list()
for(cl in c('BirdNET','Custom')){
 name<-if(cl=='BirdNET')'CM-BirdNet.txt'else'CM-Custom.txt'
 meta<-manifest$files[manifest$files$file==name,]
 path<-file.path(data_dir,name)
 if(!file.exists(path))download.file(meta$url,path,mode='wb',method='libcurl')
 stopifnot(paste0('md5:',tools::md5sum(path))==meta$checksum)
 d<-read_csv(path,show_col_types=FALSE) |> filter(compau_confidence>=.1) |>
  mutate(site=factor(Site),species=factor('Nyctidromus_albicollis'),confidence=compau_confidence,
    tp=as.integer(compau_annotation),logit_conf=qlogis(pmin(pmax(confidence,1e-4),1-1e-4)),
    stamp=sub('.*_([0-9]{8}_[0-9]{6})$','\\1',filename),
    night=as.Date(substr(stamp,1,8),'%Y%m%d')-as.integer(as.integer(substr(stamp,10,11))<12),
    night_id=paste(Site,night))
 for(rep in 1:3){
  t0<-proc.time()[['elapsed']]
  cv<-suppressMessages(compare_calibration_models(d,k_folds=5,seed=2026,fold_group='night_id'))
  timings[[length(timings)+1L]]<-tibble(classifier=cl,replicate=rep,seconds=proc.time()[['elapsed']]-t0,windows=nrow(d),candidates=nrow(cv),folds=5L)
 }
 stopifnot(nrow(cv)==3L,all(cv$n_failed==0L))
 previous<-ref |> filter(classifier==cl,scheme=='night_full') |> arrange(model)
 current<-arrange(cv,model)
 stopifnot(identical(current$model,previous$model),max(abs(current$logloss_mean-previous$logloss_mean))<1e-10)
 for(rule in c('best_auc','one_se_logloss'))result[[length(result)+1L]]<-tibble(classifier=cl,rule=rule,
   selected=select_calibration_model(cv,rule,5),failed_fits=sum(cv$n_failed),max_logloss_difference=max(abs(current$logloss_mean-previous$logloss_mean)))
 comparisons[[cl]]<-mutate(cv,classifier=cl)
}
write_csv(bind_rows(result),file.path(out,'curiango-native.csv'))
write_csv(bind_rows(comparisons),file.path(out,'curiango-native-cv.csv'))
write_csv(bind_rows(timings),file.path(out,'curiango-timing.csv'))
writeLines(capture.output(sessionInfo()),file.path(out,'curiango-native-session.txt'))
print(bind_rows(result));print(bind_rows(timings))
