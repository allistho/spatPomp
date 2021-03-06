library(spatPomp)
context("test methods on geometric Brownian motion")

doParallel::registerDoParallel(3)
# create the GBM object
# Do them parallel and do work at same time
set.seed(1)
U = 10; N = 30
gbm8 <- gbm(U = U, N = N, IVP_values = 35, delta.t = .0001, delta.obs = .001)

# compute distance matrix to compute true log-likelihood
dist <- function(u,v,n=U) min(abs(u-v),abs(u-v+U),abs(u-v-U))
dmat <- matrix(0,U,U)
for(u in 1:U) {
  for(v in 1:U) {
    dmat[u,v] <- dist(u,v)
  }
}

# compute the true log-likelihood
# rootQ = coef(gbm8)["rho"]^dmat * coef(gbm8)["sigma"]
# loglik_true <- pomp:::kalmanFilter(
#   t=1:N,
#   y= log(obs(gbm8)),
#   X0=log(rinit(gbm8)),
#   A= diag(length(unit_names(gbm8))),
#   Q=rootQ%*%rootQ,
#   C=diag(1,nrow=nrow(dmat)),
#   R=diag(coef(gbm8)["tau"]^2, nrow=nrow(dmat))
# )$loglik
#extract only loglik from kalman filter run

#Computing MLE
#fun_to_optim <- function(cf){
#  rootQ = cf["rho"]^dmat * cf["sigma"]
#  -pomp:::kalmanFilter(
#    t=1:N,
#    y=obs(bm_obj),
#   X0=rinit(bm_obj),
#    A=diag(length(unit_names(bm_obj))),
#    Q=rootQ%*%rootQ,
#    C=diag(1,nrow=nrow(dmat)),
#    R=diag(cf["tau"]^2, nrow=nrow(dmat))
#  )$loglik
#}
#mle <- optim(coef(gbm8), fun_to_optim)
#Maximize over coefficients
#Puts in various coefficient values and finds which combination of parameters gives MLE
#kfll_mle <- mle$value
#kfll_mle

#print(coef(gbm_obj))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Testing ienkf compared to MIF2
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ienkf_np <- 10000
ienkf_Nenkf <- 50
coef(gbm8) <- c("rho" = 0.7, "sigma"= 0.5, "tau"=0.5, "X1_0"=35, "X2_0"=35,
                  "X3_0"=35, "X4_0"=35, "X5_0"=35, "X6_0"=35, "X7_0"=35, "X8_0"=35, "X9_0"=35, "X10_0"=35)
ienkf_out <- ienkf(gbm8,
                   Nenkf = ienkf_Nenkf,
                   rw.sd = rw.sd(
                     rho=0.02, sigma=0.02, tau=0.02, X1_0=0.0, X2_0=0.0,
                     X3_0=0.0, X4_0=0.0, X5_0=0.0, X6_0=0.0, X7_0=0.0, X8_0=0.0, X9_0=0.0, X10_0=0.0),
                   cooling.type = "geometric",
                   cooling.fraction.50 = 0.5,
                   Np=ienkf_np)

# enkf_out <- enkf(gbm8,
#                  Np = ienkf_np)
#
# mif2_out <- mif2(gbm8,
#                  Nmif = 100,
#                  rw.sd = rw.sd(rho=0.02, sigma=0.02, tau=0.02, X1_0=35, X2_0=35,
#                                X3_0=35),
#                  cooling.type = 'geometric',
#                  cooling.fraction.50 = 0.5,
#                  Np = 1000)

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   log-likelihood estimate from GIRF
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

girf_loglik <- replicate(10,logLik(girf(gbm8,
                                        Np = 500,
                                        lookahead = 1,
                                        Nguide = 50
)))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   log-likelihood estimate from GIRF with lookahead > 1
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

girf_loglik_l2 <- replicate(10,logLik(girf(gbm8,
                                           Np = 500,
                                           lookahead = 2,
                                           Nguide = 50
)))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   log-likelihood estimate from ABF
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
abf_nbhd <- function(object, time, unit) {
  nbhd_list <- list()
  if(time>1) nbhd_list <- c(nbhd_list, list(c(unit, time-1)))
  if(unit>1) nbhd_list <- c(nbhd_list, list(c(unit-1, time)))
  return(nbhd_list)
}

abf_loglik <- replicate(10,logLik(abf(gbm8,
                                      Nrep = 100,
                                      Np = 50,
                                      nbhd = abf_nbhd)))

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   log-likelihood estimate from ABFIR
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
abfir_loglik <- replicate(10,logLik(abfir(gbm8,
                                           Nrep = 100,
                                           Np=50,
                                           nbhd = abf_nbhd)))

test_that("ABF, ABFIR, GIRF all yield close to true log-likelihood estimates", {
  expect_lt(abs(logmeanexp(girf_loglik) - loglik_true), 3)
  expect_lt(abs(logmeanexp(abf_loglik) - loglik_true), 3)
  expect_lt(abs(logmeanexp(abfir_loglik) - loglik_true), 3)

})

test_that("GIRF with lookahead >= 2 yields close to true log-likelihood estimates", {
  expect_lt(abs(logmeanexp(girf_loglik_l2) - loglik_true), 3)
})

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   igirf starting from arbitrary parameter set
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
igirf_lookahead <- 1
igirf_ninter <- length(unit_names(gbm8))
igirf_np <- 800
igirf_nguide <- 40
igirf_ngirf <- 30
coef(gbm8) <- c("rho" = 0.7, "sigma"=0.8, "tau"=0.2, "X1_0"=0, "X2_0"=0,
               "X3_0"=0, "X4_0"=0, "X5_0"=0,"X6_0"=0, "X7_0"=0, "X8_0"=0)
igirf_out1 <- igirf(gbm8, Ngirf = igirf_ngirf,
                    rw.sd = rw.sd(rho=0.02, sigma=0.02, tau=0.02, X1_0=0.02,
                                  X2_0=0.02, X3_0=0.02, X4_0=0.02, X5_0=0.02,X6_0=0.02, X7_0=0.02,
                                  X8_0=0.02),
                    cooling.type = "geometric",
                    cooling.fraction.50 = 0.5,
                    Np=igirf_np,
                    Ninter = igirf_ninter,
                    lookahead = igirf_lookahead,
                    Nguide = igirf_nguide)
igirf_out2 <- igirf(gbm8, Ngirf = igirf_ngirf,
                    rw.sd = rw.sd(rho=0.02, sigma=0.02, tau=0.02, X1_0=0.02,
                                  X2_0=0.02, X3_0=0.02, X4_0=0.02, X5_0=0.02,X6_0=0.02, X7_0=0.02,
                                  X8_0=0.02),
                    cooling.type = "geometric",
                    cooling.fraction.50 = 0.5,
                    Np=igirf_np,
                    Ninter = igirf_ninter,
                    lookahead = igirf_lookahead,
                    Nguide = igirf_nguide,
                    method = 'adams')


test_that("IGIRF produces estimates that are not far from the MLE", {
  expect_lt(abs(logLik(igirf_out1) - (-kfll_mle)), 20)
  expect_lt(abs(logLik(igirf_out2) - (-kfll_mle)), 20)

})
