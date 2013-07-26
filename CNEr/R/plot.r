CNEAnnotate = function(CNE, whichAssembly=c(1,2), chr, CNEstart, CNEend, windowSize, min_length, name){
  # name should include the information of winsize, minCount,.. more?
  # This is the pipeline of doing the density plot
  # The windowSize is in kb.
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
  ranges = get_cne_ranges_in_region(CNE, whichAssembly, chr, context_start, context_end, min_length)
  # Implement get_cne_ranges_in_region_partitioned_by_other_chr later!!!
  ranges = reduce(ranges)
  covAll = coverage(ranges, width=context_end)
  runMeanAll = runmean(covAll, k=windowSize, "constant")
  resStart = max(CNEstart, (windowSize-1)/2+1)
  resEnd = min(CNEend, computeEnd-(windowSize-1)/2)
  resCoords = seq(resStart, resEnd, by=step_size)
  runMeanRes = runMeanAll[resCoords]*100
  res = cbind(resCoords, as.vector(runMeanRes))
  colnames(res) = c("coordinates", name)
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

#resToPlot = list(a=res, b=res)

plotCNE = function(listToPlot){
  mergedDf = as.data.frame(do.call(rbind, listToPlot))
  mergedDf$grouping = rep(names(listToPlot), sapply(listToPlot, nrow))
  mergedDf = mergedDf[ ,c("coordinates", "grouping", "values")]
  horizon.panel.ggplot(mergedDf)
}

horizon.panel.ggplot = function(mergedDf, horizonscale=2){
  origin = 0
  nbands = 3
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
    opts(legend.position = "none",
         strip.text.y = theme_text(),
         axis.text.y = theme_blank(),
         axis.ticks = theme_blank(),
         axis.title.y = theme_blank(),
         axis.title.x = theme_blank(),
         title = title,
         plot.title = theme_text(size=16, face="bold", hjust=0))


}


