#### Alternate implementations

erf_alt <- function(a, y, x, family = gaussian(), offset = NULL, weights = NULL,
                    a.vals = seq(min(a), max(a), length.out = 100),
                    n.iter = 10000, n.adapt = 1000, thin = 10, 
                    span = NULL, span.seq = seq(0.05, 1, by = 0.05), k = 5){	
  
  
  if(is.null(weights))
    weights <- rep(1, times = length(y))
  
  if(is.null(offset))
    offset <- rep(0, times = length(y))
  
  n <- length(a)
  
  wrap <- np_est_alt(y = y, a = a, x = x, a.vals = a.vals, 
                     family = family, offset = offset, weights = weights,
                     n.iter = n.iter, n.adapt = n.adapt, thin = thin)
  
  muhat <- wrap$muhat
  mhat <- wrap$mhat
  pihat <- wrap$pihat
  phat <- wrap$phat
  int.mat <- wrap$int.mat
  
  y_ <- family$linkinv(family$linkfun(y) - offset)
  psi <- c((y_ - muhat) + mhat)
  
  if(is.null(span)) {
    
    idx <- sample(x = n, size = min(n, 1000), replace = FALSE)
    
    a.sub <- a[idx]
    psi.sub <- psi[idx]
    
    folds <- sample(x = k, size = min(n, 1000), replace = TRUE)
    
    cv.mat <- sapply(span.seq, function(h, ...) {
      
      cv.vec <- rep(NA, k)
      
      for(j in 1:k) {
        
        preds <- sapply(j, a.sub, dr_est, psi = psi.sub[folds != j], a = a.sub[folds != j], span = h, family = gaussian(), se.fit = FALSE)
        cv.vec[j] <- mean((psi.sub[folds == j] - preds)^2, na.rm = TRUE)
        
      }
      
      return(cv.vec)
      
    })
    
    cv.err <- colMeans(cv.mat)
    span <- span.seq[which.min(cv.err)]
    
  }
  
  dr_out <- sapply(a.vals, dr_est_alt, psi = psi, a = a,span = span, 
                   family = gaussian(), se.fit = TRUE, int.mat = int.mat)
  
  estimate <- dr_out[1,]
  variance <- dr_out[2,]
  
  names(estimate) <- names(variance) <- a.vals
  out <- list(estimate = estimate, variance = variance, span = span)	
  
  return(out)
  
}

# LOESS function
dr_est_alt <- function(newa, a, psi, span, family = gaussian(), se.fit = FALSE, int.mat = NULL) {

  a.std <- a - newa
  k <- floor(min(span, 1)*length(a))
  idx <- order(abs(a.std))[1:k]
  a.std <- a.std[idx]
  psi <- psi[idx]
  max.a.std <- max(abs(a.std))
  k.std <- c((1 - abs(a.std/max.a.std)^3)^3)
  gh <- cbind(1, a.std)
  bh <- optim(par = c(0,0), fn = opt_fun, k.std = k.std, psi = psi, gh = gh, family = family)
  mu <- family$linkinv(c(bh$par[1]))

  if (se.fit & !is.null(int.mat)){

    kern.mat <- matrix(rep(c((1 - abs((a.vals - newa)/max.a.std)^3)^3), k), byrow = T, nrow = k)
    kern.mat[matrix(rep(abs(a.vals - newa)/max.a.std, k), byrow = T, nrow = k) > 1] <- 0
    g2 <- matrix(rep(c(a.vals - newa), k), byrow = T, nrow = k)
    intfn1.mat <- kern.mat * int.mat[idx,]
    intfn2.mat <- g2 * kern.mat * int.mat[idx,]
    int1 <- apply(matrix(rep((a.vals[-1]-a.vals[-length(a.vals)]),k), byrow = T, nrow = k)*
                    (intfn1.mat[,-1] + intfn1.mat[,-length(a.vals)])/2, 1, sum)
    int2 <- apply(matrix(rep((a.vals[-1]-a.vals[-length(a.vals)]),k), byrow = T, nrow = k)*
                    (intfn2.mat[,-1] + intfn2.mat[,-length(a.vals)])/2, 1, sum)

    Dh <- solve(t(gh) %*% diag(k.std) %*% gh)
    V <- crossprod(cbind(k.std * c(psi - family$linkinv(c(gh%*%bh$par))) + int1,
                         a.std * k.std * c(psi - family$linkinv(c(gh%*%bh$par))) + int2))

    sig <- Dh%*%V%*%Dh

    return(c(mu = mu, sig = sig[1,1]))

  } else
    return(mu)

}

# Gaussian kernel
# dr_est_alt <- function(newa, a, psi, int, span, family = gaussian(), se.fit = FALSE, int.mat = NULL) {
#   
#   a.std <- c(a - newa)/span
#   k.std <- dnorm(a.std)/span
#   gh <- cbind(1, a.std)
#   bh <- optim(par = c(0,0), fn = opt_fun, k.std = k.std, psi = psi, gh = gh, family = family)
#   mu <- family$linkinv(c(bh$par[1]))
#   
#   if (se.fit & !is.null(int.mat)){
#     
#     kern.mat <- matrix(rep(dnorm(c(a.vals - newa)/span)/span, n), byrow = T, nrow = n)
#     g2 <- matrix(rep(c(a.vals - newa)/span, n), byrow = T, nrow = n)
#     intfn1.mat <- kern.mat * int.mat
#     intfn2.mat <- g2 * kern.mat * int.mat
#     int1 <- apply(matrix(rep((a.vals[-1]-a.vals[-length(a.vals)]),n), byrow = T, nrow = n)*
#                     (intfn1.mat[,-1] + intfn1.mat[,-length(a.vals)])/2, 1, sum)
#     int2 <- apply(matrix(rep((a.vals[-1]-a.vals[-length(a.vals)]),n), byrow = T, nrow = n)*
#                     (intfn2.mat[,-1] + intfn2.mat[,-length(a.vals)])/2, 1, sum)
#     
#     Dh <- solve(t(gh) %*% diag(k.std) %*% gh)
#     V <- crossprod(cbind(k.std * c(psi - family$linkinv(c(gh%*%bh$par))) + int1,
#                          a.std * k.std * c(psi - family$linkinv(c(gh%*%bh$par))) + int2))
#     
#     sig <- Dh%*%V%*%Dh
#     
#     return(c(mu = mu, sig = sig[1,1]))
#     
#   } else
#     return(mu)
#   
# }

np_est_alt <- function(a, y, x, a.vals, weights = NULL, offset = NULL, family = gaussian(),
                       n.iter = 1000, n.adapt = 1000, thin = 10) {
  
  if (is.null(weights))
    weights <- rep(1, nrow(x))
  
  if (is.null(offset))
    offset <- rep(1, nrow(x))
  
  # set up evaluation points & matrices for predictions
  n <- nrow(x)
  x <- data.frame(x)
  xa <- data.frame(x, a = a)
  colnames(xa) <- c(colnames(x), "a")
  y_ <- family$linkinv(family$linkfun(y) - offset)
  
  # estimate nuisance GPS functions via super learner
  pimod <- SuperLearner(Y = a, X = x, family = gaussian(), SL.library = "SL.ranger")
  pimod.vals <- c(pimod$SL.predict)
  pi2mod <- SuperLearner(Y = (a - pimod.vals)^2, X = x, family = gaussian(), SL.library = "SL.ranger")
  pi2mod.vals <- c(pi2mod$SL.predict)
  pi2mod.vals[pi2mod.vals <= 0] <- .Machine$double.eps
  
  # exposure models
  pihat <- dnorm(a, pimod.vals, sqrt(pi2mod.vals))
  phat.vals <- sapply(a.vals, function(a.tmp, ...) 
    mean(dnorm(a.tmp, pimod.vals, sqrt(pi2mod.vals))))
  phat <- predict(smooth.spline(a.vals, phat.vals), x = a)$y
  phat[which(phat < 0)] <- .Machine$double.eps
  phat.mat <- matrix(rep(phat.vals, n), byrow = T, nrow = n)
  
  # for accurate simulations
  mumod <- bart(y.train = y_, x.train = xa, weights = weights, keeptrees = TRUE, 
                ndpost = n.iter, nskip = n.adapt, keepevery = thin, verbose = FALSE)
  muhat <- mumod$yhat.train.mean
  
  # predict marginal outcomes given a.vals (or a.agg)
  muhat.mat <- sapply(a.vals, function(a.tmp, ...) {
    
    # for simulations
    xa.tmp <- data.frame(x = x, a = a.tmp)
    colnames(xa.tmp) <- colnames(xa)
    return(colMeans(predict(mumod, newdata = xa.tmp, type = "ev")))
    
  })
  
  # aggregate muhat.vals and integrate for influence function
  mhat.vals <- colMeans(muhat.mat)
  mhat <- predict(smooth.spline(a.vals, mhat.vals), x = a)$y
  mhat.mat <- matrix(rep(mhat.vals, n), byrow = T, nrow = n)
  
  int.mat <- (muhat.mat - mhat.mat)*phat.mat
  
  out <- list(muhat = muhat, mhat = mhat, pihat = pihat, phat = phat, int.mat = int.mat)
  
  return(out)
  
}