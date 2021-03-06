##' Adapted Bagged Filter with Intermediate Resampling (ABF-IR)
##'
##' An algorithm for estimating the likelihood of a spatiotemporal partially-observed
##' Markov process (SpatPOMP for short).
##' Running \code{abfir} causes the algorithm to run Monte Carlo replicated jobs which
##' each carry out an adapted simulation using intermediate resampling.
##' Adapted simulation is an easier task than filtering, since particles in each replicate
##' remain close to each other. Intermediate resampling further assists against
##' the curse of dimensionality (COD) problem for importance sampling.
##' The adapted simulations are then weighted in a way that tries to avert COD by
##' making a weak coupling assumption to get an approximate filter distribution.
##' As a by-product, we also get an approximation to the likelihood of the data.
##'
##' @name abfir
##' @rdname abfir
##' @include spatPomp_class.R generics.R
##' @family particle filter methods
##' @family \pkg{spatPomp} filtering methods
##' @importFrom foreach %dopar%
##'
##' @inheritParams abf
##' @inheritParams girf
##' @inheritParams pomp::pfilter
##' @param object A \code{spatPomp} object.
##' @param Np The number of particles for the adapted simulations within each Monte Carlo replicate.
##' @param Nrep The number of Monte Carlo replicates for the adapted simulations.
##' @examples
##' # Create a simulation of a BM using default parameter set
##' b <- bm(U=3, N=10)
##'
##' # Create a neighborhood function mapping a point in space-time to a list of ``neighboring points" in space-time
##' bm_nbhd <- function(object, time, unit) {
##'   nbhd_list = list()
##'   if(time > 1 && unit > 1) nbhd_list = c(nbhd_list, list(c(unit - 1, time - 1)))
##'   return(nbhd_list)
##' }
##' # Run abfir specified number of Monte Carlo replicates and particles per replicate
##' abfird_b <- abfir(b,
##'                   Nrep = 50,
##'                   Np=20,
##'                   nbhd = bm_nbhd,
##'                   Ninter = length(unit_names(bm3)))
##' # Get the likelihood estimate from abfir
##' logLik(abfird_b)
##'
##' # Compare with the likelihood estimate from Particle Filter
##' pfd_b <- pfilter(b, Np = 500)
##' logLik(pfd_b)
##' @return
##' Upon successful completion, \code{abfir} returns an object of class
##' \sQuote{abfird_spatPomp}.
##'
##' @section Methods:
##' The following methods are available for such an object:
##' \describe{
##' \item{\code{\link{logLik}}}{ yields a biased estimate of the log-likelihood of
##' the data under the model. }
##' }
##'
NULL

setClass(
  "abfird_spatPomp",
  contains="spatPomp",
  slots=c(
    Ninter="integer",
    Np="integer",
    Nrep="integer",
    tol="numeric",
    loglik="numeric",
    nbhd="function"
  ),
  prototype=prototype(
    Ninter=as.integer(NA),
    Np=as.integer(NA),
    Nrep=as.integer(NA),
    tol=as.double(NA),
    loglik=as.double(NA),
    nbhd=function(){}
  )
)
abfir_internal <- function (object, Np, nbhd,
      Ninter, tol, ..., verbose, .gnsi = TRUE) {
  ep <- paste0("in ",sQuote("abfir"),": ")
  p_object <- pomp(object,...,verbose=verbose)
  object <- new("spatPomp",p_object,
                unit_covarnames = object@unit_covarnames,
                shared_covarnames = object@shared_covarnames,
                runit_measure = object@runit_measure,
                dunit_measure = object@dunit_measure,
                eunit_measure = object@eunit_measure,
                munit_measure = object@munit_measure,
                vunit_measure = object@vunit_measure,
                unit_names=object@unit_names,
                unitname=object@unitname,
                unit_statenames=object@unit_statenames,
                unit_obsnames = object@unit_obsnames,
                unit_accumvars = object@unit_accumvars)
  params <- coef(object)
  verbose = FALSE
  pompLoad(object,verbose=verbose)
  on.exit(pompUnload(object,verbose=verbose))
  gnsi <- as.logical(.gnsi)

  if (length(params)==0) stop(ep,sQuote("params")," must be specified",call.=FALSE)
  if (missing(tol)) stop(ep,sQuote("tol")," must be specified",call.=FALSE)

  times <- time(object,t0=TRUE)
  N <- length(times)-1
  U <- length(unit_names(object))

  if (missing(Np)) stop(ep,sQuote("Np")," must be specified",call.=FALSE)
  if (is.function(Np)) stop(ep,"Functions for Np not supported by abfir",call.=FALSE)
  if (length(Np)!=1) stop(ep,"Np should be a length 1 vector",call.=FALSE)
  Np <- as.integer(Np)

  if (NCOL(params)>1) stop(ep,"does not accept matrix parameter input",call.=FALSE)

  paramnames <- names(params)
  if (is.null(paramnames))
    stop(ep,sQuote("params")," must have names",call.=FALSE)

  ## ideally, we shouldn't need param_matrix in abfir
  param_matrix <- matrix(params,nrow=length(params),ncol=Np,
    dimnames=list(names(params),NULL))

  x_init <- rinit(object,params=params,nsim=1,.gnsi=gnsi) # Nx x 1 matrix
  statenames <- rownames(x_init)
  Nx <- nrow(x_init)
  xas <- as.numeric(x_init) # adapted simulation state vector
  znames <- object@accumvars

  loglik <- rep(NA,N)
  log_cond_densities <- array(data = numeric(0), dim=c(U,Np,N))
  dimnames(log_cond_densities) <- list(unit = 1:U, rep = 1:Np, time = 1:N)

  for (n in seq_len(N)) {
    ## assimilate observation n given filter at n-1
    ## note that times[n+1] is the time for observation n

    ## xg: Nx x Np x 1 matrix of guide simulations
    ## also used to calculate local prediction weights
    xf <- matrix(xas,nrow=Nx,ncol=Np,dimnames=list(statenames,NULL))
    xg <- tryCatch(
      rprocess(
        object,
        x0=xf,
        t0=times[n],
        times=times[n+1],
        params=params,
        .gnsi=gnsi
      ),
      error = function (e) stop(ep,"process simulation error: ",
        conditionMessage(e),call.=FALSE)
    )
    xg_2dim <- xg[,,1]
    # print(xg_2dim)
    # print("xg_2dim done")
    xg_with_rep <- do.call(cbind,replicate(Np, xg_2dim, simplify=FALSE))
    dim(xg_with_rep) <- c(dim(xg_with_rep)[1],dim(xg_with_rep)[2],1)
    dimnames(xg_with_rep) <- list(states = rownames(xg_2dim))
    xx <- tryCatch(
      .Call('do_fcst_samp_var',
            object=object,
            X=xg_with_rep,
            Np = as.integer(Np),
            times=times[n+1],
            params=params,
            gnsi=TRUE),
      error = function (e) {
        stop(ep,conditionMessage(e),call.=FALSE) # nocov
      }
    )
    fcst_samp_var <- xx
    dim(fcst_samp_var) <- c(length(unit_names(object)), Np)

    ## determine the weights
    log_weights <- tryCatch(
      vec_dmeasure(
        object,
        y=object@data[,n,drop=FALSE],
        x=xg,
        times=times[n+1],
        params=param_matrix,
        log=TRUE,
        .gnsi=gnsi
      ),
      error = function (e) {
        stop(ep,"error in calculation of weights: ",
             conditionMessage(e),call.=FALSE)
      }
    )

    # weights[weights < tol] <- tol
    log_cond_densities[,,n] <- log_weights[,,1]
    ## adapted simulation via intermediate resampling
    # tt has S+1 (or Ninter+1) entries
    tt <- seq(from=times[n],to=times[n+1],length.out=Ninter+1)
    log_gf <- rep(0,Np) # filtered guide function
    for (s in 1:Ninter){
      xp <- rprocess(object,x0=xf, t0 = tt[s], times= tt[s+1],
        params=params,.gnsi=gnsi) # an Nx by nreps by 1 array
      if(s>1 && length(znames)>0){
        xf.znames <- xf[znames,,drop=FALSE]
        xp[znames,,1] <- xp[znames,,1,drop=FALSE][,,1] + xf.znames
      }
      if(s < Ninter){
        skel <- tryCatch(
          pomp::flow(object,
                     x0=xp[,,1],
                     t0=tt[s+1],
                     params=param_matrix,
                     times = times[n + 1],
                     ...),
          error = function (e) {
            pomp::flow(object,
                       x0=xp[,,1],
                       t0=tt[s+1],params=param_matrix,
                       times = times[n + 1],
                       method='adams')
            }
        )
        if(length(znames) > 0){
          skel.lookahead1.znames <- skel[znames,,1,drop=FALSE]
          xp.znames <- xp[znames,,1,drop=FALSE]
          skel[znames,,] <- skel.lookahead1.znames + xp.znames
        }
      } else {
        skel <- xp
      }

      # create measurement variance at skeleton matrix
      # meas_var_skel <- array(0, dim = c(U, Np))
      # for(u in 1:U){
      #   snames = paste0(object@unit_statenames,u)
      #   for(np in 1:Np){
      #     hskel <- h(state.vec=skel[snames,np,1],param.vec=params)
      #     meas_var_skel[u,np] <- theta.to.v(meas.mean=hskel,param.vec=params)
      #   }
      # }
      meas_var_skel <- tryCatch(
        .Call('do_theta_to_v',
              object=object,
              X=skel,
              Np = as.integer(Np[1]),
              times=times[n+1],
              params=params,
              gnsi=TRUE),
        error = function (e) {
          stop(ep,conditionMessage(e),call.=FALSE) # nocov
        }
      )
      meas_var_skel <- meas_var_skel[,,1]
      fcst_var_upd <- fcst_samp_var*(times[n+1] - tt[s+1])/(times[n+1] - times[n])
      # print(xg)
      # print("done with xg")
      # print(meas_var_skel)
      # print("done with mvs")
      # print(fcst_samp_var)
      # print("done with fsv")
      # print(fcst_var_upd)
      # print("done with fvu")
      # return(1)
      # fcst_var_upd <- array(0, dim = c(U, Np))
      # for(u in 1:U){
      #   fcst_var_upd[u,] <- fcst_samp_var[u] *
      #     (times[n+1] - tt[s+1])/(times[n+1] - times[n])
      # }
      inflated_var <- meas_var_skel + fcst_var_upd
      dim(inflated_var) <- c(U, Np, 1)
      array.params <- array(params, dim = c(length(params), length(unit_names(object)), Np, 1), dimnames = list(params = names(params)))

      mmp <- tryCatch(
        .Call('do_v_to_theta',
              object=object,
              X=skel,
              vc=inflated_var,
              Np = as.integer(Np[1]),
              times=times[n+1],
              params=array.params,
              gnsi=TRUE),
        error = function (e) {
          stop(ep,conditionMessage(e),call.=FALSE) # nocov
        }
      )
      mom_match_param <- mmp[,,,1]

#       mom_match_param <- array(0, dim = c(length(params), U, Np),
#         dimnames = list(params = names(params), unit = NULL, J = NULL))
#       inflated_var <- meas_var_skel + fcst_var_upd
#       for(u in 1:U){
#         for(np in 1:Np){
#           snames = paste0(object@unit_statenames,u)
#           mom_match_param[,u,np] <- v.to.theta(var=inflated_var[u,np],
# 	    param.vec=params, state.vec=skel[snames,np,1])
#         }
#       }

      # U x Np x 1 matrix of skeleton prediction weights
# TRY REMOVING DISCOUNT FOR ABF-IR, FOR SIMPLICITY IF IT IS NO BIG DEAL
#      discount_denom_init = times[n]
#      discount_factor = 1 - (times[n+1] - tt[s+1])/(times[n+1] - discount_denom_init)
      log_wp <- tryCatch(
        vec_dmeasure(
          object,
          y=object@data[,n,drop=FALSE],
          x=skel,
          times=times[n+1],
          params=mom_match_param,
          log=TRUE,
          .gnsi=gnsi
        ),
        error = function (e) stop(ep,"error in calculation of wp: ",
          conditionMessage(e),call.=FALSE)
      )
#      log_gp <- apply(log_wp[,,1,drop=FALSE],2,sum)*discount_factor
      log_gp <- apply(log_wp[,,1,drop=FALSE],2,sum)
      max_log_gp <- max(log_gp)
      #log_gp[log_gp < log(tol)] <- log(tol)
      if(max_log_gp > -Inf){
        log_gp <- log_gp - max_log_gp
        weights <- exp(log_gp - log_gf)
        gnsi <- FALSE
        xx <- tryCatch(
          .Call('abfir_resample', xp, Np, weights, log_gp, tol),
          error = function (e) stop(ep,conditionMessage(e),call.=FALSE)
        )
        xf <- xx$states
        log_gf <- xx$filterguides
      }
      else{
        xf <- xp
        log_gf <- log(tol)
      }

    } ## end of intermediate resampling loop s = 1:Ninter

    # resample down to one particle, making Np copies of, say, particle #1.
    xas <- xf[,1]

    if (verbose && (n%%5==0)) cat("abfir timestep",n,"of",N,"finished\n")

  } ## end of main loop n = 1:N

  # compute locally combined pred. weights for each time, unit and particle
  #
  # matches abf.R except
  #   pp -> np
  #   Np is assumed scalar
  #   ntimes -> N , nt -> n
  #   nunits -> U , unit -> u
  log_loc_comb_pred_weights = array(data = numeric(0), dim=c(U,Np, N))
  log_wm_times_wp_avg = array(data = numeric(0), dim = c(U, N))
  log_wp_avg = array(data = numeric(0), dim = c(U, N))
  for (n in seq_len(N)){
      for (u in seq_len(U)){
          full_nbhd <- nbhd(object, time = n, unit = u)
          log_prod_cond_dens_nt  <- rep(0, Np)
          if(length(full_nbhd) > 0) log_prod_cond_dens_not_nt <- matrix(0, Np[1], max(1,n-min(sapply(full_nbhd,'[[',2))))
          else log_prod_cond_dens_not_nt <- matrix(0,Np[1],0)
          for (neighbor in full_nbhd){
              neighbor_u <- neighbor[1]
              neighbor_n <- neighbor[2]
              if (neighbor_n == n)
                  log_prod_cond_dens_nt  <- log_prod_cond_dens_nt + log_cond_densities[neighbor_u, ,neighbor_n]
              else
                  log_prod_cond_dens_not_nt[, n-neighbor_n] <- log_prod_cond_dens_not_nt[, n-neighbor_n] + log_cond_densities[neighbor_u, ,neighbor_n]
          }
          log_loc_comb_pred_weights[u,,n]  <- sum(apply(log_prod_cond_dens_not_nt, 2, logmeanexp)) + log_prod_cond_dens_nt
      }
  }
  log_wm_times_wp_avg = apply(log_loc_comb_pred_weights + log_cond_densities, c(1,3), FUN = logmeanexp)
  log_wp_avg = apply(log_loc_comb_pred_weights, c(1,3), FUN = logmeanexp)

  pompUnload(object,verbose=verbose)
  new(
    "adapted_replicate",
    log_wm_times_wp_avg = log_wm_times_wp_avg,
    log_wp_avg = log_wp_avg,
    Np=as.integer(Np),
    tol=tol
  )


}
##' @name abfir-spatPomp
##' @aliases abfir,spatPomp-method
##' @rdname abfir
##' @export
setMethod(
  "abfir",
  signature=signature(object="spatPomp"),
  function (object, Np, Nrep, nbhd,
            Ninter, tol = (1e-300), ...,
            verbose=getOption("verbose",FALSE)) {
  if (missing(Ninter)) Ninter <- length(unit_names(object))
  if(missing(nbhd)){
    nbhd <- function(object, unit, time){
      nbhd_list = list()
      if(time>1) nbhd_list <- c(nbhd_list, list(c(unit, time-1)))
      if(unit>1) nbhd_list <- c(nbhd_list, list(c(unit-1, time)))
      return(nbhd_list)
    }
  }
    # set.seed(396658101,kind="L'Ecuyer")
  # begin single-core
  # single_rep_output <- spatPomp:::abfir_internal(
  #   object=object,
  #   Np=Np,
  #   nbhd=nbhd,
  #   Ninter=Ninter,
  #   tol=tol,
  #   ...
  # )
  # return(single_rep_output)
  # end single-core
  mcopts <- list(set.seed=TRUE)
  mult_rep_output <- foreach::foreach(i=1:Nrep,
     .packages=c("pomp","spatPomp"),
     .options.multicore=list(set.seed=TRUE)) %dopar% spatPomp:::abfir_internal(
       object=object,
       Np=Np,
       nbhd=nbhd,
       Ninter=Ninter,
       tol=tol,
       ...,
       verbose=verbose
     )
   # compute sum (over all Nrep) of w_{d,n,i}^{P} for each (d,n)
   N <- length(object@times)
   U <- length(unit_names(object))
   #rep_mp_sums = array(data = numeric(0), dim = c(U,N))
   #rep_p_sums = array(data = numeric(0), dim = c(U, N))
   cond_loglik <- foreach::foreach(u=seq_len(U),
                                   .combine = 'rbind',
                                   .packages=c("pomp", "spatPomp"),
                                   .options.multicore=mcopts) %dopar%
                                   {
                                     cond_loglik_u <- array(data = numeric(0), dim=c(N))
                                     for (n in seq_len(N)){
                                       log_mp_sum = logmeanexp(vapply(mult_rep_output,
                                                                      FUN = function(rep_output) return(rep_output@log_wm_times_wp_avg[u,n]),
                                                                      FUN.VALUE = 1.0))
                                       log_p_sum = logmeanexp(vapply(mult_rep_output,
                                                                     FUN = function(rep_output) return(rep_output@log_wp_avg[u,n]),
                                                                     FUN.VALUE = 1.0))
                                       cond_loglik_u[n] = log_mp_sum - log_p_sum
                                     }
                                     cond_loglik_u
                                   }
   # OLD CODE. Remove by 1/15/2020
   # cond_loglik = array(data = numeric(0), dim=c(U, N))
   # for (u in seq_len(U)){
   #   for (n in seq_len(N)){
   #     log_mp_sum = logmeanexp(vapply(mult_rep_output,
   #                                FUN = function(rep_output) return(rep_output@log_wm_times_wp_avg[u,n]),
   #                                FUN.VALUE = 1.0))
   #     log_p_sum = logmeanexp(vapply(mult_rep_output,
   #                               FUN = function(rep_output) return(rep_output@log_wp_avg[u,n]),
   #                               FUN.VALUE = 1.0))
   #     cond_loglik[u,n] = log_mp_sum - log_p_sum
   #     # for (k in seq_len(Nrep)){
   #     #   mp_sum = mp_sum + mult_rep_output[[k]]@wm.times.wp.avg[u,n]
   #     #   p_sum = p_sum + mult_rep_output[[k]]@wp.avg[u,n]
   #     # }
   #     # cond.loglik[u,n] = log(mp_sum) - log(p_sum)
   #   }
   # }
   new(
      "abfird_spatPomp",
      object,
      Np=as.integer(Np),
      tol=tol,
      loglik=sum(cond_loglik),
      Ninter = as.integer(Ninter),
      Nrep = as.integer(Nrep),
      nbhd = nbhd
      )
  }
)

setMethod(
  "abfir",
  signature=signature(object="abfird_spatPomp"),
  function (object, Np, Nrep, nbhd,
            Ninter, tol, ...) {
    if (missing(Np)) Np <- object@Np
    if (missing(tol)) tol <- object@tol
    if (missing(Ninter)) Ninter <- object@Ninter
    if (missing(Nrep)) Nrep <- object@Nrep
    if (missing(nbhd)) nbhd <- object@nbhd

    abfir(as(object,"spatPomp"),
         Np=Np,
         Ninter=Ninter,
         Nrep=Nrep,
         nbhd=nbhd,
         tol=tol,
         ...)
  }
)

