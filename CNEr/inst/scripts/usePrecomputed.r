## import the precomputed cnes from old pipeline

dbName = "/mnt/biggley/home/gtan/work/projects/CNEr/CNErData/cne.sqlite"

cneTables = list.files("/export/data/CNEs/blatFiltered_19-07-2013", 
                       pattern=".*canFam3.*hg19.*", 
                       full.names=TRUE)

cneTable = cneTables[1]
for(cneTable in cneTables){
  df = read.table(cneTable, header=FALSE, sep="\t", as.is=TRUE)
  df = df[ ,1:9]
  colnames(df) = c("chr1", "start1", "end1", "chr2", "start2", "end2", "strand", "similarity", "cigar")
  df = transform(df, start1=start1+1, start2=start2+1)
  saveCNEToSQLite(df, dbName, basename(cneTable))
}


