
setGeneric("toICM", signature="x",
           function(x, pseudocounts=NULL, schneider=FALSE,
                    bg_probabilities=c(A=0.25, C=0.25, G=0.25, T=0.25))
             standardGeneric("toICM")
           )

setGeneric("toPWM", signature="x",
           function(x, pseudocounts=NULL,
                    bg_probabilities=c(A=0.25, C=0.25, G=0.25, T=0.25))
             standardGeneric("toPWM")
           )

setGeneric("plotLogo", signature="x",
           function(x, ic.scale = TRUE, xaxis = TRUE, yaxis = TRUE,
                    xfontsize = 15, yfontsize = 15) standardGeneric("plotLogo")
           )

setGeneric("searchSeq", signature="x",
           function(x, subject, seqname="Unknown", strand="*", min.score="80%")
             standardGeneric("searchSeq"))

setGeneric("searchAln", signature="x",
           function(x, subject, min.score="80%", windowSize=50L, cutoff="70%",
                    conservation=NULL)
             standardGeneric("searchAln")
           )
setGeneric("doSiteSearch", signature="x",
           function(pwm, x, min.score="80%", windowSize=50L, cutoff="70%",
                    conservation=NULL)
             standardGeneric("doSiteSearch")
           )

setGeneric("calConservation", signature="x",
           function(x, windowSize, which=c("1", "2"))
             standardGeneric("calConservation")
           )

setGeneric("clone", signature="x", function(x, ...) standardGeneric("clone"))
setGeneric("revcom", signature="x", function(x) standardGeneric("revcom"))
setGeneric("writeGFF3", signature="x", function(x) standardGeneric("writeGFF3"))
setGeneric("writeGFF2", signature="x", function(x) standardGeneric("writeGFF2"))
setGeneric("relScore", signature="x", function(x) standardGeneric("relScore"))

## Accessors
setGeneric("ID", signature="x", function(x) standardGeneric("ID"))
setGeneric("ID<-", signature="x", function(x, value) standardGeneric("ID<-"))
setGeneric("name", signature="x", function(x) standardGeneric("name"))
setGeneric("name<-", signature="x", function(x, value) standardGeneric("name<-"))
setGeneric("matrixClass", signature="x", function(x) standardGeneric("matrixClass"))
setGeneric("matrixClass<-", signature="x", function(x, value) standardGeneric("matrixClass<-"))
setGeneric("Matrix", signature="x", function(x) standardGeneric("Matrix"))
setGeneric("Matrix<-", signature="x", function(x, value) standardGeneric("Matrix<-"))
setGeneric("bg", signature="x", function(x) standardGeneric("bg"))
setGeneric("bg<-", signature="x", function(x, value) standardGeneric("bg<-"))
setGeneric("matrixType", signature="x", function(x) standardGeneric("matrixType"))
setGeneric("pseudocounts", signature="x", function(x) standardGeneric("pseudocounts"))
setGeneric("pseudocounts<-", signature="x", function(x, value) standardGeneric("pseudocounts<-"))
setGeneric("schneider", signature="x", function(x) standardGeneric("schneider"))
setGeneric("schneider<-", signature="x", function(x, value) standardGeneric("schneider<-"))
setGeneric("views", signature="x", function(x) standardGeneric("views"))
setGeneric("seqname", signature="x", function(x) standardGeneric("seqname"))
setGeneric("sitesource", signature="x", function(x) standardGeneric("sitesource"))
setGeneric("primary", signature="x", function(x) standardGeneric("primary"))
setGeneric("pattern", signature="x", function(x) standardGeneric("pattern"))
setGeneric("site1", signature="x", function(x) standardGeneric("site1"))
setGeneric("site2", signature="x", function(x) standardGeneric("site2"))
setGeneric("alignments", signature="x", function(x) standardGeneric("alignments"))

setGeneric("XMatrixList", signature="x",
           function(x, use.names=TRUE, ...)
             standardGeneric("XMatrixList")
           )

