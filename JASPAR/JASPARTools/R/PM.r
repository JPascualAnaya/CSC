library(Biostrings) ##consensusMatrix,
library(seqLogo)  ## plot SeqLogo

### ------------------------------------------------------------------------
### The generic position matrix objects.
#setClass("XMatrix", contains=c("matrix"),
#         slots=c(ID="character",
#                 name="character",
#                 matrixClass="character",
#                 strand="character",
#                 bg="numeric"
#                 ))
#
### -----------------------------------------------------------------------
### XMatrix subclasses without additional slots
###
setClass("PFMatrix", 
         slots=c(ID="character",
                 name="character",
                 matrixClass="character",
                 strand="character",
                 bg="numeric",
                 matrix="matrix")
         )
setClass("PWMatrix", contains="PFMatrix",
         slots=c(pseudocounts="numeric")
         )
setClass("ICMatrix", contains="PWMatrix",
         slots=c(
                 schneider="logical"
                 )
         )
#setClass("ICMatrix", contains="matrix",
#         slots=c(ID="character",
#                 name="character",
#                 matrixClass="character",
#                 strand="character",
#                 pseudocounts="numeric",
#                 schneider="logical",
#                 bg="numeric"
#                 ))
#setClass("PWMatrix", contains="matrix",
#         slots=c(ID="character",
#                 name="character",
#                 matrixClass="character",
#                 strand="character",
#                 pseudocounts="numeric",
#                 bg="numeric"
#                 )
#         )
setClassUnion("XMatrix", c("PFMatrix", "ICMatrix", "PWMatrix"))

### ------------------------------------------------------------------------
### The generic position matrix objects.
### 
setClass("JASPAR", contains=c("XMatrix"),
         slots=c(ID="character",
                 collection="character",
                 version="character",
                 name="character",
                 species="Rle",
                 TFClass="character",
                 medline="character",
                 family="character"
                 )
         )

### ----------------------------------------------------------------------
### The accessor-like method
setGeneric("ID", signature="x", function(x) standardGeneric("ID"))
setGeneric("ID<-", signature="x", function(x, value) standardGeneric("ID<-"))
setMethod("ID", "XMatrix", function(x) x@ID)

setGeneric("name", signature="x", function(x) standardGeneric("name"))
setGeneric("name<-", signature="x", function(x, value) standardGeneric("name<-"))
setMethod("name", "XMatrix", function(x) x@name)

setGeneric("matrixClass", signature="x", function(x) standardGeneric("matrixClass"))
setGeneric("matrixClass<-", signature="x", function(x, value) standardGeneric("matrixClass<-"))
setMethod("matrixClass", "XMatrix", function(x) x@matrixClass)

setGeneric("Matrix", signature="x", function(x) standardGeneric("Matrix"))
setGeneric("Matrix<-", signature="x", function(x, value) standardGeneric("Matrix<-"))
setMethod("Matrix", "XMatrix", function(x) x@matrix)

#setGeneric("strand<-", signature="x", function(x, value) standardGeneric("strand<-"))
setMethod("strand", "XMatrix", function(x) x@strand)

setGeneric("bg", signature="x", function(x) standardGeneric("bg"))
setGeneric("bg<-", signature="x", function(x, value) standardGeneric("bg<-"))
setMethod("bg", "XMatrix", function(x) x@bg)

setGeneric("matrixType", signature="x", function(x) standardGeneric("matrixType"))
setMethod("matrixType", "PFMatrix", function(x) "PFM")
setMethod("matrixType", "ICMatrix", function(x) "ICM")
setMethod("matrixType", "PWMatrix", function(x) "PWM")

setGeneric("pseudocounts", signature="x", function(x) standardGeneric("pseudocounts"))
setGeneric("pseudocounts<-", signature="x", function(x, value) standardGeneric("pseudocounts<-"))
setMethod("pseudocounts", "PWMatrix", function(x) x@pseudocounts)

setGeneric("schneider", signature="x", function(x) standardGeneric("schneider"))
setGeneric("schneider<-", signature="x", function(x, value) standardGeneric("schneider<-"))
setMethod("schneider", "ICMatrix", function(x) x@schneider)

setReplaceMethod("ID", "XMatrix", 
                 function(x, value){
                   x@ID = value
                   return(x)
                 }
                 )
setReplaceMethod("name", "XMatrix",
                 function(x, value){
                   x@name = value
                   return(x)
                 }
                 )
setReplaceMethod("matrixClass", "XMatrix",
                 function(x, value){
                   x@matrixClass = value
                   return(x)
                 }
                 )
setReplaceMethod("strand", "XMatrix",
                 function(x, value){
                   x@strand = value
                   return(x)
                 }
                 )
setReplaceMethod("bg", "XMatrix",
                 function(x, value){
                   x@bg = value
                   return(x)
                 }
                 )
setReplaceMethod("Matrix", "XMatrix",
                 function(x, value){
                   x@matrix = value
                   return(x)
                 }
                 )
setReplaceMethod("pseudocounts", "PWMatrix",
                 function(x, value){
                   x@pseudocounts = value
                   return(x)
                 }
                 )
setReplaceMethod("schneider", "ICMatrix",
                 function(x, value){
                   x@schneider = value
                   return(x)
                 }
                 )
### ----------------------------------------------------------------------
### The constructor
###
ICMatrix = function(ID=character(), name=character(), matrixClass=character(),
                    strand=character(), bg=numeric(), matrix=matrix(),
                    pseudocounts=numeric(), schneider=logical()){
  new("ICMatrix", ID=ID, name=name, matrixClass=matrixClass, strand=strand, bg=bg,
      matrix=matrix, pseudocounts=pseudocounts, schneider=schneider)
}
PFMatrix = function(ID=character(), name=character(), matrixClass=character(),
                    strand=character(), bg=numeric(), matrix=matrix()){
  new("PFMatrix", ID=ID, name=name, matrixClass=matrixClass, strand=strand, bg=bg,
      matrix=matrix)
}
PWMatrix = function(ID=character(), name=character(), matrixClass=character(),
                    strand=character(), bg=numeric(), matrix=matrix(),
                    pseudocounts=numeric()){
  new("PWMatrix", ID=ID, name=name, matrixClass=matrixClass, strand=strand, bg=bg,
      matrix=matrix, pseudocounts=pseudocounts)
}
# 
# pfm = PFMatrix(ID="M0001", name="MyProfile", bg=c(A=0.25, C=0.25, G=0.25, T=0.25), matrix=matrix(as.integer(c(12, 3, 0, 0, 4, 0, 0, 0, 0, 11, 7, 0, 0, 9, 12, 0, 0, 0, 0, 0, 0, 1, 1, 12)), byrow=TRUE, nrow=4, dimnames=list(c("A", "C", "G", "T"))))
# pwm = PWMatrix(ID="M0001", name="MyProfile2", bg=c(A=0.25, C=0.25, G=0.25, T=0.25), matrix=matrix(as.integer(c(12, 3, 0, 0, 4, 0, 0, 0, 0, 11, 7, 0, 0, 9, 12, 0, 0, 0, 0, 0, 0, 1, 1, 12)), byrow=TRUE, nrow=4, dimnames=list(c("A", "C", "G", "T"))), pseudocounts=0.8)
# icm = ICMatrix(ID="M0001", name="MyProfile3", bg=c(A=0.25, C=0.25, G=0.25, T=0.25), matrix=matrix(as.integer(c(12, 3, 0, 0, 4, 0, 0, 0, 0, 11, 7, 0, 0, 9, 12, 0, 0, 0, 0, 0, 0, 1, 1, 12)), byrow=TRUE, nrow=4, dimnames=list(c("A", "C", "G", "T"))), pseudocounts=0.8, schneider=TRUE)

### -----------------------------------------------------------------------
### The "show" method.
###

setMethod("show", "XMatrix",
          function(object){
            cat("An object of class ", class(object), "\n", sep="") 
            cat("ID:", ID(object), "\n")
            cat("Name:", name(object), "\n")
            cat("Matrix class:", matrixClass(object), "\n")
            cat("Strand:", strand(object), "\n")
            cat("Background:", bg(object), "\n")
            cat("Matrix:", "\n") 
            print(Matrix(object))
            if(class(object) != "PFMatrix")
              cat("Pseudocounts:", pseudocounts(object), "\n")
            if(class(object) == "ICMatrix")
              cat("Schneider correction:", schneider(object), "\n")
          }
          )

