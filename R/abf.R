##' Adapted Bagged Filter (ABF)
##'
##' An algorithm for estimating the filter distribution and likelihood estimate of a spatiotemporal partially-observed Markov process model.
##' Running \code{abf} causes the algorithm to run bootstrap replicate jobs which each yield an imperfect adapted simulation. Simulating from the "adapted filter"
##' distribution runs into a curse of dimensionality (COD) problem, which is mitigated by keeping particles in each replicate close to each other through resampling down
##' to one particle per replicate at each observation time point.
##' The adapted simulations are then weighted in a way that tries to avert COD by making a weak coupling assumption to get an approximate filter distribution.
##' As a by-product, we also get a biased estimate of the likelihood of the data.
##'
##' @name abf
##' @rdname abf
##' @include spatPomp_class.R generics.R
##' @family particle filter methods
##' @family \pkg{spatPomp} filtering methods
##' @importFrom foreach %dopar%
##'
##'
##' @param object A \code{spatPomp} object.
##' @param params A parameter set for the spatiotemporal POMP. If missing, \code{abf} will attempt to run using \code{coef(object)}
##' @param Np The number of particles used within each replicate for the adapted simulations.
##' @param nbhd A neighborhood function with three arguments: \code{object}, \code{time} and \code{unit}. The function should return a \code{list} of two-element vectors. The list output of
##' \code{nbhd(u,n)} consists of vectors \code{c(a,b)} where \eqn{(a,b)} is a neighbor of \code{(u,n)} in space-time.
##' @param Nreplicates The number of replicates for the adapted simulations.
##' @param tol If the resampling weight for a particle is zero due to floating-point precision issues, it is set to the value of \code{tol} since resampling has to be done.
##' @examples
##' # Create a simulation of a BM using default parameter set
##' b <- bm(U=3, N=10)
##'
##' # Create a neighborhood function mapping a point in space-time to a list of "neighboring points" in space-time
##' bm_nbhd <- function(object, time, unit) {
##'   nbhd_list = list()
##'   if(time > 1 && unit > 1) nbhd_list = c(nbhd_list, list(c(unit - 1, time - 1)))
##'   return(nbhd_list)
##' }
##'
##' # Run ABF specified number of Monte Carlo islands and particles per island
##' abfd.b <- abf(b, islands = 50, Np = 10, nbhd = bm_nbhd)
##'
##' # Get the likelihood estimate from ABF
##' logLik(abfd.b)
##'
##' # Compare with the likelihood estimate from Particle Filter
##' pfd.b <- pfilter(b, Np = 500)
##' logLik(pfd.b)
##' @return
##' Upon successful completion, \code{abf} returns an object of class
##' \sQuote{abfd_spatPomp}.
##'
##' @section Methods:
##' The following methods are available for such an object:
##' \describe{
##' \item{\code{\link{logLik}}}{ yields a biased estimate of the log-likelihood of the data under the model. }
##' }
##'
NULL

setClass(
  "adapted_replicate",
  slots=c(
    log_wm_times_wp_avg="array",
    log_wp_avg="array",
    Np="integer",
    tol="numeric"
  ),
  prototype=prototype(
    log_wm_times_wp_avg=array(data=numeric(0),dim=c(0,0)),
    log_wp_avg=array(data=numeric(0),dim=c(0,0)),
    Np=as.integer(NA),
    tol=as.double(NA)
  )
)
setClass(
  "abfd_spatPomp",
  contains="spatPomp",
  slots=c(
    Nrep="integer",
    nbhd="function",
    Np="integer",
    tol="numeric",
    loglik="numeric"
  ),
  prototype=prototype(
    Nrep=as.integer(NA),
    Np=as.integer(NA),
    tol=as.double(NA),
    loglik=as.double(NA)
  )
)
abf_internal <- function (object, Np, nbhd, Ninter, tol, ..., verbose, .gnsi = TRUE) {
  ep <- paste0("in ",sQuote("abf"),": ")
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
  pompLoad(object,verbose)
  gnsi <- as.logical(.gnsi)
  if (length(params)==0)
    stop(ep,sQuote("params")," must be specified",call.=FALSE)

  if (missing(tol))
    stop(ep,sQuote("tol")," must be specified",call.=FALSE)

  times <- time(object,t0=TRUE)
  ntimes <- length(times)-1
  nunits <- length(unit_names(object))

  if (missing(Np)) {
    if (is.matrix(params)) {
      Np <- ncol(params)
    } else {
      stop(ep,sQuote("Np")," must be specified",call.=FALSE)
    }
  }
  if (is.function(Np)) {
    Np <- tryCatch(
      vapply(seq.int(from=0,to=ntimes,by=1),Np,numeric(1)),
      error = function (e) {
        stop(ep,"if ",sQuote("Np")," is a function, ",
             "it must return a single positive integer",call.=FALSE)
      }
    )
  }
  if (length(Np)==1)
    Np <- rep(Np,times=ntimes+1)
  else if (length(Np)!=(ntimes+1))
    stop(ep,sQuote("Np")," must have length 1 or length ",ntimes+1,call.=FALSE)
  if (any(Np<=0))
    stop(ep,"number of particles, ",sQuote("Np"),", must always be positive",call.=FALSE)
  if (!is.numeric(Np))
    stop(ep,sQuote("Np")," must be a number, a vector of numbers, or a function",call.=FALSE)
  Np <- as.integer(Np)
  if (is.matrix(params)) {
    if (!all(Np==ncol(params)))
      stop(ep,"when ",sQuote("params")," is provided as a matrix, do not specify ",
           sQuote("Np"),"!",call.=FALSE)
  }

  if (NCOL(params)==1) {        # there is only one parameter vector
    one.par <- TRUE
    coef(object) <- params     # set params slot to the parameters
    params <- as.matrix(params)
  }

  paramnames <- rownames(params)
  if (is.null(paramnames))
    stop(ep,sQuote("params")," must have rownames",call.=FALSE)

  ## returns an nvars by nsim matrix
  init.x <- rinit(object,params=params,nsim=Np[1L],.gnsi=gnsi)
  statenames <- rownames(init.x)
  nvars <- nrow(init.x)
  x <- init.x

  loglik <- rep(NA,ntimes)

  # create array to store weights across time
  log_cond_densities <- array(data = numeric(0), dim=c(nunits,Np[1L],ntimes))
  dimnames(log_cond_densities) <- list(unit = 1:nunits, rep = 1:Np[1L], time = 1:ntimes)
  for (nt in seq_len(ntimes)) { ## main loop
    ## advance the state variables according to the process model
    X <- tryCatch(
      rprocess(
        object,
        x0=x,
        t0=times[nt],
        times=times[nt+1],
        params=params,
        .gnsi=gnsi
      ),
      error = function (e) {
        stop(ep,"process simulation error: ",
             conditionMessage(e),call.=FALSE)
      }
    )

    ## determine the weights
    log_weights <- tryCatch(
      vec_dmeasure(
        object,
        y=object@data[,nt,drop=FALSE],
        x=X,
        times=times[nt+1],
        params=params,
        log=TRUE,
        .gnsi=gnsi
      ),
      error = function (e) {
        stop(ep,"error in calculation of weights: ",
             conditionMessage(e),call.=FALSE)
      }
    )

    #weights[weights == 0] <- tol
    log_cond_densities[,,nt] <- log_weights[,,1]
    log_resamp_weights <- apply(log_weights[,,1,drop=FALSE], 2, function(x) sum(x))
    max_log_resamp_weights <- max(log_resamp_weights)
    # if any particle's resampling weight is zero replace by tolerance
    if(all(is.infinite(log_resamp_weights))) log_resamp_weights <- rep(log(tol), Np[1L])
    else log_resamp_weights <- log_resamp_weights - max_log_resamp_weights
    resamp_weights <- exp(log_resamp_weights)
    #if(all(resamp_weights == 0)) resamp_weights <- rep(tol, Np[1L])
    gnsi <- FALSE

    ## do resampling if filtering has not failed
    xx <- tryCatch(
      .Call(
        "abf_computations",
        x=X,
        params=params,
        Np=Np[nt+1],
        trackancestry=FALSE,
        weights=resamp_weights
      ),
      error = function (e) {
        stop(ep,conditionMessage(e),call.=FALSE) # nocov
      }
    )

    x <- xx$states
    params <- xx$params

    if (verbose && (nt%%5==0))
      cat("abf timestep",nt,"of",ntimes,"finished\n")
  } ## end of main loop

  # compute locally combined pred. weights for each time, unit and particle
  log_loc_comb_pred_weights = array(data = numeric(0), dim=c(nunits,Np[1L], ntimes))
  log_wm_times_wp_avg = array(data = numeric(0), dim = c(nunits, ntimes))
  log_wp_avg = array(data = numeric(0), dim = c(nunits, ntimes))
  for (nt in seq_len(ntimes)){
      for (unit in seq_len(nunits)){
          full_nbhd <- nbhd(object, time = nt, unit = unit)
          log_prod_cond_dens_nt  <- rep(0, Np[1])
          if(length(full_nbhd) > 0) log_prod_cond_dens_not_nt <- matrix(0, Np[1], max(1,nt-min(sapply(full_nbhd,'[[',2))))
          else log_prod_cond_dens_not_nt <- matrix(0,Np[1],0)
          for (neighbor in full_nbhd){
              neighbor_u <- neighbor[1]
              neighbor_n <- neighbor[2]
              if (neighbor_n == nt)
                  log_prod_cond_dens_nt  <- log_prod_cond_dens_nt + log_cond_densities[neighbor_u, ,neighbor_n]
              else
                  log_prod_cond_dens_not_nt[, nt-neighbor_n] <- log_prod_cond_dens_not_nt[, nt-neighbor_n] + log_cond_densities[neighbor_u, ,neighbor_n]
          }
          log_loc_comb_pred_weights[unit, ,nt]  <- sum(apply(log_prod_cond_dens_not_nt, 2, logmeanexp)) + log_prod_cond_dens_nt
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
##' @name abf-spatPomp
##' @aliases abf,spatPomp-method
##' @rdname abf
##' @export
setMethod(
  "abf",
  signature=signature(object="spatPomp"),
  function (object, Ninter, Nrep, Np, nbhd,
           tol = (1e-300),
           ..., verbose=getOption("verbose",FALSE)) {
    if (missing(Ninter)) Ninter <- length(unit_names(object))
    if(missing(nbhd)){
     nbhd <- function(object, unit, time){
       nbhd_list = list()
       if(time>1) nbhd_list <- c(nbhd_list, list(c(unit, time-1)))
       if(unit>1) nbhd_list <- c(nbhd_list, list(c(unit-1, time)))
       return(nbhd_list)
     }
   }
   ## single thread for testing
   # single_rep_output <- abf.internal(
   #  object=object,
   #  params=params,
   #  Np=Np,
   #  nbhd = nbhd,
   #  tol=tol,
   #  ...)
   # return(single_rep_output)
   ## end single thread for testing
   ## begin multi-thread code
   mcopts <- list(set.seed=TRUE)
   mult_rep_output <- foreach::foreach(i=1:Nrep,
       .packages=c("pomp","spatPomp"),
       .options.multicore=mcopts) %dopar%  spatPomp:::abf_internal(
     object=object,
     Np=Np,
     nbhd=nbhd,
     Ninter=Ninter,
     tol=tol,
     ...,
     verbose=verbose
     )
   ntimes = length(time(object))
   nunits = length(unit_names(object))
   rep_mp_sums = array(data = numeric(0), dim = c(nunits,ntimes))
   rep_p_sums = array(data = numeric(0), dim = c(nunits, ntimes))
   cond_loglik <- foreach::foreach(u=seq_len(nunits),
                    .combine = 'rbind',
                    .packages=c("pomp", "spatPomp"),
                    .options.multicore=mcopts) %dopar%
                    {
                      cond_loglik_u <- array(data = numeric(0), dim=c(ntimes))
                      for (n in seq_len(ntimes)){
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
   # end multi-threaded code
   new(
      "abfd_spatPomp",
      object,
      Np=as.integer(Np),
      tol=tol,
      loglik=sum(cond_loglik)
     )
  }
)

setMethod(
  "abf",
  signature=signature(object="abfd_spatPomp"),
  function (object, Nrep, Np, nbhd, params,
            tol,
            ...) {
    if (missing(Np)) Np <- object@Np
    if (missing(tol)) tol <- object@tol
    if (missing(params)) params <- coef(object)
    if (missing(Nrep)) Nrep <- object@Nrep
    if (missing(nbhd)) nbhd <- object@nbhd

    abf(as(object,"spatPomp"),
           Np=Np,
           Nrep=Nrep,
           nbhd=nbhd,
           params = params,
           tol=tol,
           ...)
  }
)

