CNEAnnotate = function(dbName, tableName, whichAssembly=c("1","2"), chr, CNEstart, CNEend, windowSize, minLength=NULL, nrGraphs=1){
  # This is the pipeline of doing the density plot
  # The windowSize is in kb.
  whichAssembly = match.arg(whichAssembly)
  windowSize = windowSize * 1000
  CNElength = CNEend - CNEstart + 1
  pixel_width = 800
  if(CNElength <= pixel_width) {
    step_size = 1
  }else{
    step_size = as.integer(CNElength/pixel_width)
    if(step_size > windowSize/10)
      step_size = windowSize/10
    while(windowSize %% step_size){
      step_size = step_size - 1
    }
  }
  # make things easier
  if(windowSize %% 2 == 0)
    windowSize = windowSize - 1
  context_start = max(CNEstart - (windowSize-1)/2, 1)
  context_end = CNEend + (windowSize-1)/2 
  #win_nr_steps = windowSize / step_size
  #context_start = CNEstart - as.integer(((win_nr_steps-1)*step_size)/2+0.5)
  #if(context_start < 1)
  #  context_start = 1
  #context_end = CNEend + as.integer(((win_nr_steps-1)*step_size)/2+step_size+0.5)
  ranges = readCNERangesFromSQLite(dbName, tableName, chr, context_start, context_end, whichAssembly, minLength, nrGraphs)
  # Implement get_cne_ranges_in_region_partitioned_by_other_chr later!!!
  ranges = reduce(ranges)
  covAll = coverage(ranges, width=context_end)
  runMeanAll = runmean(covAll, k=windowSize, "constant")
  resStart = max(CNEstart, (windowSize-1)/2+1)
  resEnd = min(CNEend, context_end-(windowSize-1)/2)
  resCoords = seq(resStart, resEnd, by=step_size)
  runMeanRes = runMeanAll[resCoords]*100
  res = cbind(resCoords, as.vector(runMeanRes))
  colnames(res) = c("coordinates", "y")
  return(res)
}


#calc_window_scores = function(CNEstart, CNEend, ranges, win_nr_steps, step_size){
#  ## Here the starts and ends are 1-based.
#  CNElength = CNEend - CNEstart + 1
#  win_size = win_nr_steps * step_size
#  offsetBlk = as.integer(((win_nr_steps-1)*step_size)/2+0.5)
#  context_start = CNEstart - offsetBlk
#  if(context_start < 1)
#    context_start = 1
#  context_end = CNEend + offsetBlk
#  context_size = context_end - context_start + 1
#  #nr_blocks = as.integer(context_size/step_size) + ifelse(context_size%%step_size, 1, 0)
#  #blk_scores = numeric(ifelse(nr_blocks>win_nr_steps, nr_blocks, win_nr_steps+1))
#
#  covAll = coverage(ranges, width=context_end)
#   
#  #runMeanAll = runmean(covAll, k=windowSize, "constant")
#  #resStart = max(CNEstart, (windowSize-1)/2+1)
#  #resEnd = min(CNEend, computeEnd-(windowSize-1)/2)
#  #height = runMeanAll[resStart:resEnd]*100
#}

#listToPlot = list(a=res, b=res)

plotCNE = function(listToPlot){
  mergedDf = as.data.frame(do.call(rbind, listToPlot))
  mergedDf$grouping = rep(names(listToPlot), sapply(listToPlot, nrow))
  mergedDf = mergedDf[ ,c("coordinates", "grouping", "y")]
  p = horizon.panel.ggplot(mergedDf)
}

horizon.panel.ggplot = function(mergedDf, horizonscale=2, my.title="fun"){
  require(ggplot2)
  require(reshape2)
  origin = 0
  nbands = 3
  #require(RColorBrewer)
  #col.brew = brewer.pal(name="RdBu",n=10)
  col.brew = c("#67001F", "#B2182B", "#D6604D", "#F4A582", "#FDDBC7", "#D1E5F0", "#92C5DE", "#4393C3", "#2166AC", "#053061")
  colnames(mergedDf) = c("coordinates", "grouping", "y")
  for(i in 1:nbands){
    #do positive
    mergedDf[ ,paste("ypos",i,sep="")] = ifelse(mergedDf$y > origin,
                                          ifelse(abs(mergedDf$y) > horizonscale * i,
                                                 horizonscale,
                                                 ifelse(abs(mergedDf$y) - (horizonscale * (i - 1) - origin) > origin, abs(mergedDf$y) - (horizonscale * (i - 1) - origin), origin)),
                                          origin)
  }
  mergedDf.melt = melt(mergedDf[,c(1,2,4:6)],id.vars=1:2)
  colnames(mergedDf.melt) = c("coordinates","grouping","band","value")
  p = ggplot(data=mergedDf.melt) +
    geom_area(aes(x = coordinates, y = value, fill=band),
                position="identity") +
    scale_fill_manual(values=c("ypos1"=col.brew[7],
                               "ypos2"=col.brew[8],
                               "ypos3"=col.brew[9]))+
    ylim(origin,horizonscale) +
    facet_grid(grouping ~ .) +
    theme_bw() +
    theme(legend.position = "none",
         strip.text.y = element_text(),
         #axis.text.y = element_blank(), ## remove the y lables
         axis.ticks = element_blank(),
         axis.title.y = element_blank(),
         axis.title.x = element_blank(),
         plot.title = element_text(size=16, face="bold", hjust=0))+
    ggtitle(my.title)
    return(p)
}

