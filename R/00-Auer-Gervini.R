#######################################################
# INTERNAL
# functions based on descriptions in Auer-Gervini, 2008

fhat <- function(d, Lambda) {
  m <- length(Lambda)
  use <- Lambda[(d+1):m]
  geo <- exp(mean(log(use)))
  ari <- mean(use)
  (m-d)*log(geo/ari)
}

dhat <- function(theta, Lambda) {
  ds <- seq(0, length(Lambda)-1)
  vals <- sapply(ds, function(d, theta, Lambda) {
    fhat(d, Lambda) + theta*(length(Lambda)-1-d)
  }, theta=theta, Lambda=Lambda)
  max(ds[which(vals==max(vals))])
}

thetaLower <- function(d, Lambda) {
  m <- length(Lambda)
  if(d == m - 1) return(0)
  fd <- fhat(d, Lambda)
  kset <- (d+1):(m-1)
  temp <- sapply(kset, function(k) {
    (fhat(k, Lambda) - fd) / (k - d)
  })
  max(temp)
}

thetaUpper <- function(d, Lambda) {
  if (d == 0) return(Inf)
  m <- length(Lambda)
  fd <- fhat(d, Lambda)
  kset <- 0:(d-1)
  temp <- sapply(kset, function(k) {
    (fhat(k, Lambda) - fd) / (k - d)
  })
  min(temp)
}

#######################################################
# EXTERNAL

# broken-stick model
brokenStick <- function(k, n) {
    if (any(n < k)) stop('bad values')
    x <- 1/(1:n)
    sapply(k, function(k0) sum(x[k0:n])/n)
}

# broken stick to get dimension
bsDimension <- function(lambda, FUZZ=0.005) {
  if(inherits(lambda, "SamplePCA")) {
    lambda <- lambda@variances
  }
  N <- length(lambda)
  bs  <- brokenStick(1:N, N)
  fracVar <- lambda/sum(lambda)
  which(fracVar - bs < FUZZ)[1] - 1
}

# randomization based model
matPermutate <- function(data) {
  n <- nrow(data)
  m <- ncol(data)
  permat <- data
  for (i in 1:m) {
    new <- sample(n, n, replace=FALSE)
    permat[,i] <- data[,i][new]
  }
  permat
}

# randomization based model to get dimension
# B is total repeat times for randomization, alpha is significance
# level for p-values
rndLambdaF <- function(data, B=1000, alpha=0.05) {
  if (!inherits(data[1,1], "numeric")) {
    stop('data elements are not numeric')
  }
  if (sum(is.na(data)) > 0) {
    stop('data contains missing values')
  }
  m <- ncol(data)
  Lambda <- F <- matrix(1e-6, B, m)   
  spca <- SamplePCA(t(data))
  lambda <- sqrt(spca@variances)
  if (length(lambda) < m) {
    lambda <- c(lambda, rep(1e-6, m - length(lambda)))
  }
  rescum <- cumsum(sort(lambda, decreasing=FALSE))[1:(m-1)]
  Lambda[1, ] <- lambda
  F[1,1:(m-1)] <- lambda[1:(m-1)]/sort(rescum, decreasing=TRUE)
  for (i in 1:(B-1)) {
    rndmat <- matPermutate(data)
    spca <- SamplePCA(t(rndmat))
    lambda <- sqrt(spca@variances)
    if (length(lambda) < m) {
      lambda <- c(lambda, rep(1e-6, m - length(lambda)))
    }
    rescum <- cumsum(sort(lambda, decreasing=FALSE))[1:(m-1)]
    Lambda[i+1, ] <- lambda
    F[i+1, 1:(m-1)] <- lambda[1:(m-1)]/sort(rescum, decreasing=TRUE)
  }
  p1 <- apply(Lambda, 2, function(v) {sum(v >= v[1])/length(v)})
  p2 <- apply(F, 2, function(v) {sum(v >= v[1])/length(v)})
  res <- c(rndLambda=which(p1 > alpha)[1] - 1, rndF=which(p2 > alpha)[1] - 1)
  return(res)
}


#######################################################
# S4 interface

setClass("AuerGervini",
         slots = c(Lambda="numeric",
                   dimensions="numeric",
                   dLevels="numeric",
                   changePoints="numeric"
                   ))

AuerGervini <- function(Lambda, dd=NULL, epsilon=2e-16) {
  if (inherits(Lambda, "SamplePCA")) {
    dd <- dim(Lambda@scores)
    Lambda <- Lambda@variances
  }
  if (epsilon > 0) {
    Lambda <- Lambda[Lambda > epsilon]
  }
  Lambda <- rev(sort(Lambda))
  rg <- (1:length(Lambda)) - 1
  lowerBounds <- sapply(rg, thetaLower, Lambda=Lambda)
  upperBounds <- sapply(rg, thetaUpper, Lambda=Lambda)
  dLevels <- rev(rg[lowerBounds <= upperBounds])
  changePoints <- rev(lowerBounds[lowerBounds <= upperBounds])[-1]
  new("AuerGervini", Lambda=Lambda, dimensions = dd,
      dLevels=dLevels, changePoints=changePoints)
}

estimateTop <- function(object) {
  n <- object@dimensions[1] # nrows
  m <- object@dimensions[2] # ncolumns
  oldAndCrude <- -2*log(0.01)/n # in case we want to revert
  delta <- 1 # why do we do it this way?
  magic <- 18.8402+1.9523*m-0.0005*m^2 # from a linear model fit on simulated data
  modelBased <- ifelse(n >= m,
                       magic/n,
                       magic*n/m^2) # please explain why
  max(oldAndCrude,
      modelBased,
      1.03*object@changePoints)
}

setMethod("plot", c("AuerGervini", "missing"), function(x, y, ...) {
  plot(x, list(), ...)
})

# y is an optional argument containing a list of "agDimension"
# computing functions
setMethod("plot", c("AuerGervini", "list"), function(x, y,
        main="Bayesian Sensitivity Analysis",
        ...) {
  top <-estimateTop(x)
  fun <- stepfun(x@changePoints, x@dLevels)
  plot(fun, xlab="Prior Theta", ylab="Number of Components",
     main=main, xlim=c(0, top), ...)
  if (!missing(y)) {
    lapply(y, function(agfun) {
      abline(h=agDimension(x, agfun), lty=2, lwd=2, col='pink')
    })
  }
  invisible(x)
})

setMethod("summary", "AuerGervini", function(object, ...) {
  cat("An '", class(object), "' object that estimates the number of ",
      "principal components to be ", agDimension(object), ".\n", sep="")
})

compareAgDimMethods <- function(object, agfuns) {
  unlist(lapply(agfuns, function(f) agDimension(object, f)))
}

agDimension <- function(object, agfun=agDimTwiceMean) {
  stepLength <- diff(c(object@changePoints, estimateTop(object)))
  if (length(stepLength) > 4) {
    magic <- agfun(stepLength)
  } else {
    magic <- (stepLength == max(stepLength))
  }
  ifelse(any(magic),
         object@dLevels[1+which(magic)[1]],
         0)
}

agDimTwiceMean <- function(stepLength) {
  (stepLength > 2*mean(stepLength))
}

# k-means criterion (3 different versions)
# version 1: centers are max. and min. (select highest in large group)
agDimKmeans <- function(stepLength) {
  kmeanfit <- kmeans(stepLength, centers=c(min(stepLength), 
                                           max(stepLength)))
  i <- which.max(kmeanfit$centers)
  kmeanfit$cluster == i
}

# version 3: choose k=3 if more features (select highest largest)
agDimKmeans3 <- function(stepLength) {
  # choose k = 3 if there are many features (extra center is median)
  if (ceiling(log(length(stepLength))/2)>2) {
    kcenters <- c(min(stepLength), 
                  median(stepLength),
                  max(stepLength))
  } else {
    kcenters <- c(min(stepLength), 
                  max(stepLength))
  }
  kmeanfit <- kmeans(stepLength, centers=kcenters)
  # treats intermediate as long and says "don't include short"
  i <- which.min(kmeanfit$centers)
  kmeanfit$cluster != i
}

#-------------------------------------------------------------------------
# spectral clustering criterion
agDimSpectral <- function(stepLength) {
  # project 1D step length sequence onto a 2D line (y=x)
  dat <- cbind(X1=stepLength, X2=stepLength)
  scfit <- specc(dat, centers=2, mod.sample=1)
  scmean1 <- mean(stepLength[scfit==1])
  scmean2 <- mean(stepLength[scfit==2])
  scnum <- ifelse(scmean1>scmean2, 1, 2)
  scfit == scnum
}

#------------------------------------------------------------------------
# naive t-test criterion (2 different versions)
# version 1: naive idea to detect the significant change point in  
# difference of sorted step lengths (t-based method)
# TO DO: include significance level alpha in arguments, currently
# set significance level to be 0.01
# for version 2, set extra=1
agDimTtest <- function(stepLength, extra=0) {
  sort1 <- sort(stepLength, decreasing=FALSE, method="qu", 
                index.return=TRUE)
  diffsl <- diff(sort1$x)
  meanlist <- cumsum(diffsl)[3:length(diffsl)]/(3:length(diffsl))
  meannum <- length(meanlist)
  iter <- 0
  pvec <- NULL
  repeat {
    if (iter == meannum-1) break
    b0 <- iter + 1 + extra
    b1 <- b0 + 2
    sdvalue <- sd(diffsl[1:(b0 + 2)] - meanlist[b0])
    pvalue <- 1 - pt((meanlist[iter + 2] - meanlist[iter + 1]) / (sdvalue/sqrt(b1)),
                     b1 - 1)
    pvec <- c(pvec, pvalue)
    if (pvalue < 0.01) break
    iter <- iter + 1
  }
  if (iter < meannum - 1) {
    slset <- sort1$ix[(iter+4):length(stepLength)]
    magic <- (1:length(stepLength) %in% slset)
  }  else { 
    pt <- which.min(pvec) 
    slset <- sort1$ix[(pt+4):length(stepLength)]
    magic <- (1:length(stepLength) %in% slset)
  }
  magic
}

agDimTtest2 <- function(stepLength) {
  agDimTtest(stepLength, extra=1)
}

#-------------------------------------------------------------------------
# changepoint criterion (cpt.mean in changepoint package)
agDimCPT <- function(stepLength) {
  sort1 <- sort(stepLength, decreasing=FALSE, method="qu",
                index.return=TRUE)
  fit <- cpt.mean(sort1$x, Q=2)
  cp <- cpts(fit)
  if (length(cp) != 0) {
    slset <- sort1$ix[(cp+1):length(stepLength)]
    magic <- (1:length(stepLength) %in% slset)
  } else {
    magic <- (stepLength == max(stepLength))
  }
  magic
}

#------------------------------------------------------------------------
# cpm criterion (use detectChangePointBatch function in cpm package)
# use detectChangePointBatch function to detect the significant change 
# point in sorted step lengths, cpmethod is cpmType in the function
agDimCPM <- function(stepLength, cpmethod) {
  sort1 <- sort(stepLength, decreasing=FALSE, method="qu", 
                index.return=TRUE)
  fit <- detectChangePointBatch(sort1$x, cpmethod, alpha=0.05,
                                lambda=NA)
  cp <- fit$changePoint
  if (fit$changeDetected) {
    slset <- sort1$ix[(cp+1):length(stepLength)]
    magic <- (1:length(stepLength) %in% slset)
  } else {
    magic <- (stepLength == max(stepLength))
  }
  magic
}

makeAgCpmFun <- function(method) {
  function(stepLength) {
    agDimCPM(stepLength, method)
  }
}

#------------------------------------------------------------------------
# another novel method
# agDimLeap <- function(stepLength) {
#   N <- length(stepLength)
#   sorted <- sort(stepLength)
#   cummean <- cumsum(sorted)/(1:N)
#   cumsd <- sapply(1:N, function(i) sd(sorted[1:i]))
#   p <- 1 - pnorm(sorted[4:N], cummean[3:(N-1)], cumsd[3:(N-1)])
#   p <- (N-3)*p # Bonferroni
#   if (any( p < 0.01)) { # magic number
#     w <- 3 + which(p < 0.01)[1]
#     magic <- stepLength >= sorted[w]
#   } else {
#     magic <- (stepLength == max(stepLength))
#   }
#   magic
# }

if(0) {
  plot(sorted, type='b')
  lines(cummean, col='red', type='b')
  lines(cummean+3*cumsd, col='blue', type='b')
  points(4:20, p, pch=16)
}
