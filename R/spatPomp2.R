##' @export
spatPomp2 <- function (data, units, times, covar, t0, ...,
                      eunit_measure, munit_measure, vunit_measure, dunit_measure, runit_measure,
                      rprocess, rmeasure, dprocess, dmeasure, skeleton, rinit, rprior, dprior,
                      unit_statenames, unit_accumvars, shared_covarnames, globals, paramnames, params,
                      cdir,cfile, shlib.args, PACKAGE,
                      partrans, compile=TRUE, verbose = getOption("verbose",FALSE)) {

  ep <- paste0("in ",sQuote("spatPomp"),": ")

  if (missing(data))
    stop(ep,sQuote("data")," is a required argument",call.=FALSE)

  if (!inherits(data,what=c("data.frame","spatPomp")))
    pStop("spatPomp",sQuote("data")," must be a data frame or an object of ",
          "class ",sQuote("spatPomp"),".")

  ## return as quickly as possible if no work is to be done
  if (is(data,"spatPomp") && missing(times) && missing(t0) &&
      missing(dunit_measure) && missing(eunit_measure) &&
      missing(vunit_measure) && missing(munit_measure) &&
      missing(runit_measure) &&
      missing(rinit) && missing(rprocess) && missing(dprocess) &&
      missing(rmeasure) && missing(dmeasure) && missing(skeleton) &&
      missing(rprior) && missing(dprior) && missing(partrans) &&
      missing(covar) && missing(tcovar) && missing(params) && missing(accumvars) &&
      length(list(...)) == 0)
    return(as(data,"spatPomp"))

  if (missing(times)) times <- NULL
  if (missing(units)) units <- NULL

  tryCatch(
    construct_spatPomp(
      data=data,times=times,units=units,t0=t0,...,
      rinit=rinit,rprocess=rprocess,dprocess=dprocess,
      rmeasure=rmeasure,dmeasure=dmeasure,
      skeleton=skeleton,rprior=rprior,dprior=dprior,partrans=partrans,
      params=params,covar=covar,unit_accumvars=unit_accumvars,
      dunit_measure=dunit_measure,eunit_measure=eunit_measure,
      vunit_measure=vunit_measure,munit_measure=munit_measure,
      runit_measure=runit_measure,unit_statenames=unit_statenames,
      paramnames=paramnames, shared_covarnames=shared_covarnames,PACKAGE=PACKAGE,
      globals=globals,cdir=cdir,cfile=cfile,shlib.args=shlib.args,
      compile=compile, verbose=verbose
    ),
    error = function (e) pomp:::pStop_(conditionMessage(e))
  )
}
# Takes care of case where times or units has been set to NULL
setMethod(
  "construct_spatPomp",
  signature=signature(data="ANY", times="ANY", units="ANY"),
  definition = function (data, times, t0, ...) {
    pomp:::pStop_(sQuote("times")," should be a single name identifying the column of data that represents",
           " the observation times. ", sQuote("units"), " should be likewise for column that represents",
           " the observation units.")
  }
)

setMethod(
  "construct_spatPomp",
  signature=signature(data="data.frame", times="character", units="character"),
  definition = function (data, times, units, t0, ...,
                         rinit, rprocess, dprocess, rmeasure, dmeasure, skeleton, rprior, dprior,
                         partrans, params, covar, unit_accumvars, dunit_measure, eunit_measure,
                         vunit_measure, munit_measure, runit_measure, unit_statenames,
                         paramnames, shared_covarnames, PACKAGE, globals,
                         cdir, cfile, shlib.args, compile, verbose) {

    if (anyDuplicated(names(data)))
      pomp:::pStop_("names of data variables must be unique.")

    if (missing(t0)) reqd_arg(NULL,"t0")

    tpos <- match(times,names(data),nomatch=0L)
    upos <- match(units,names(data),nomatch=0L)

    if (length(times) != 1 || tpos == 0L)
      pomp:::pStop_(sQuote("times")," does not identify a single column of ",
             sQuote("data")," by name.")
    if (length(units) != 1 || upos == 0L)
      pomp:::pStop_(sQuote("units")," does not identify a single column of ",
             sQuote("data")," by name.")

    timename <- times
    unitname <- units

    # units slot contains unique units. unit_names is an "ordering" of units
    unit_names <- unique(data[[upos]]); U <- length(unit_names)

    # get observation types
    unit_obsnames <- names(data)[-c(upos,tpos)]
    if(missing(unit_statenames)) unit_statenames <- as.character(NULL)
    if(missing(unit_accumvars)) unit_accumvars <- as.character(NULL)

    # if missing workhorses, set to default
    if (missing(rinit)) rinit <- NULL
    if (missing(rprocess) || is.null(rprocess)) {
      rprocess <- pomp:::rproc_plugin()
    }
    if (missing(dprocess)) dprocess <- NULL
    if (missing(rmeasure)) rmeasure <- NULL
    if (missing(dmeasure)) dmeasure <- NULL
    if (missing(dunit_measure)) dunit_measure <- NULL
    if (missing(eunit_measure)) eunit_measure <- NULL
    if (missing(vunit_measure)) vunit_measure <- NULL
    if (missing(munit_measure)) munit_measure <- NULL
    if (missing(runit_measure)) runit_measure <- NULL
    if (missing(skeleton) || is.null(skeleton)) {
      skeleton <- pomp:::skel_plugin()
    }
    if (missing(rprior)) rprior <- NULL
    if (missing(dprior)) dprior <- NULL
    if (missing(partrans) || is.null(partrans)) {
      partrans <- parameter_trans()
    }

    if (missing(params)) params <- numeric(0)
    if (is.list(params)) params <- unlist(params)

    # Make data into a dataframe that pomp would expect
    tmp <- 1:length(unit_names)
    names(tmp) <- unit_names
    pomp_data <- data %>% dplyr::mutate(ui = tmp[match(data[,unitname], names(tmp))])
    pomp_data <- pomp_data %>% tidyr::gather(unit_obsnames, key = 'obsname', value = 'val') %>% dplyr::arrange(pomp_data[,timename], obsname, ui)
    pomp_data <- pomp_data %>% dplyr::mutate(obsname = paste0(obsname,ui)) %>% dplyr::select(-upos) %>% dplyr::select(-ui)
    pomp_data <- pomp_data %>% tidyr::spread(key = obsname, value = val)
    dat_col_order <- vector(length = U*length(unit_obsnames))
    for(ot in unit_obsnames){
      for(i in 1:U){
        dat_col_order[i] = paste0(ot, i)
      }
    }
    pomp_data <- pomp_data[, c(timename, dat_col_order)]
    if(!missing(covar)){
      if(timename %in% names(covar)) tcovar <- timename
      else{
        pomp:::pStop_(sQuote("covariate"), ' data.frame should have a time column with the same name as the ',
        'time column of the observation data.frame')
      }
    }
    # make covariates into a dataframe that pomp would expect
    unit_covarnames <- NULL # could get overwritten soon
    if(missing(shared_covarnames)) shared_covarnames <- NULL
    if(!missing(covar)){
      upos_cov <- match(unitname, names(covar))
      tpos_cov <- match(tcovar, names(covar))
      if(missing(shared_covarnames)) unit_covarnames <- names(covar)[-c(upos_cov, tpos_cov)]
      else {
        pos_shared_cov <- match(shared_covarnames, names(covar))
        unit_covarnames <- names(covar)[-c(upos_cov, tpos_cov, pos_shared_cov)]
      }
      tmp <- 1:length(unit_names)
      names(tmp) <- unit_names
      pomp_covar <- covar %>% dplyr::mutate(ui = match(covar[,unitname], names(tmp)))
      pomp_covar <- pomp_covar %>% tidyr::gather(unit_covarnames, key = 'covname', value = 'val')
      pomp_covar <- pomp_covar %>% dplyr::mutate(covname = paste0(covname,ui)) %>% dplyr::select(-upos_cov) %>% dplyr::select(-ui)
      pomp_covar <- pomp_covar %>% tidyr::spread(key = covname, value = val)
      cov_col_order <- c()
      for(cn in unit_covarnames){
        for(i in 1:U){
          cov_col_order = c(cov_col_order, paste0(cn, i))
        }
      }
      pomp_covar <- pomp_covar[, c(timename, cov_col_order)]
      pomp_covar <- pomp::covariate_table(pomp_covar, times=tcovar)
    } else {
      pomp_covar <- pomp::covariate_table()
    }

    # Get all names before call to pomp().
    if(!missing(unit_statenames)) pomp_statenames <- paste0(rep(unit_statenames,each=U),1:U)
    else pomp_statenames <- NULL
    pomp_obsnames <- paste0(rep(unit_obsnames,each=U),1:U)
    if (!missing(covar)) pomp_covarnames <- paste0(rep(unit_covarnames,each=U),1:U)
    else pomp_covarnames <- NULL
    if (!missing(unit_accumvars)) pomp_accumvars <- paste0(rep(unit_accumvars,each=U),1:U)
    else pomp_accumvars <- NULL
    if (missing(paramnames)) paramnames <- NULL
    if (!missing(paramnames)) mparamnames <- paste("M_", paramnames, sep = "")


    # We will always have a global giving us the number of spatial units
    if(missing(globals)) globals <- Csnippet(paste0("const int U = ",length(unit_names),";\n"))
    else globals <- Csnippet(paste0(paste0("\nconst int U = ",length(unit_names),";\n"),globals@text))

    # create the pomp object
    po <- pomp(data = pomp_data,
               times=times,
               t0 = t0,
               rprocess = rprocess,
               rmeasure = rmeasure,
               dprocess = dprocess,
               dmeasure = dmeasure,
               skeleton = skeleton,
               rinit = rinit,
               statenames=pomp_statenames,
               accumvars=pomp_accumvars,
               covar = pomp_covar,
               paramnames = paramnames,
               globals = globals,
               cdir = cdir,
               cfile = cfile,
               shlib.args = shlib.args,
               partrans = partrans,
               ...,
               verbose=verbose
    )

    # Hitch the spatPomp components
    hitches <- pomp::hitch(
      eunit_measure=eunit_measure,
      munit_measure=munit_measure,
      vunit_measure=vunit_measure,
      dunit_measure=dunit_measure,
      runit_measure=runit_measure,
      templates=eval(spatPomp_workhorse_templates),
      obsnames = paste0(unit_obsnames,"1"),
      statenames = paste0(unit_statenames,"1"),
      paramnames=paramnames,
      covarnames=pomp_covarnames,
      PACKAGE=PACKAGE,
      globals=globals,
      cfile=cfile,
      cdir=cdir,
      shlib.args=shlib.args,
      verbose=verbose
    )

    pomp:::solibs(po) <- hitches$lib
    new("spatPomp",po,
        eunit_measure=hitches$funs$eunit_measure,
        munit_measure=hitches$funs$munit_measure,
        vunit_measure=hitches$funs$vunit_measure,
        dunit_measure=hitches$funs$dunit_measure,
        runit_measure=hitches$funs$runit_measure,
        unit_names=unit_names,
        unit_statenames=unit_statenames,
        unit_accumvars=unit_accumvars,
        unit_obsnames=unit_obsnames,
        unitname=unitname,
        unit_covarnames=as.character(unit_covarnames),
        shared_covarnames=as.character(shared_covarnames))
  }
)

setMethod(
  "construct_spatPomp",
  signature=signature(data="spatPomp", times="NULL", units="NULL"),
  definition = function (data, times, units, t0, timename, unitname, ...,
                         rinit, rprocess, dprocess, rmeasure, dmeasure, skeleton, rprior, dprior,
                         partrans, params, paramnames, unit_statenames, covar, shared_covarnames, unit_accumvars,
                         dunit_measure, eunit_measure, vunit_measure, munit_measure, runit_measure,
                         globals, verbose, PACKAGE, cfile, cdir, shlib.args) {
    times <- data@times
    unit_names <- data@unit_names; U <- length(unit_names)
    if(missing(unit_statenames)) unit_statenames <- data@unit_statenames
    if(length(unit_statenames) == 0) pomp_statenames <- NULL
    else pomp_statenames <- paste0(rep(unit_statenames,each=U),1:U)
    unit_obsnames <- data@unit_obsnames
    if(missing(timename)) timename <- data@timename
    else timename <- as.character(timename)
    if(missing(unitname)) unitname <- data@unitname
    else unitname <- as.character(unitname)

    unit_covarnames <- data@unit_covarnames
    if(missing(shared_covarnames))  shared_covarnames <- data@shared_covarnames
    if(missing(unit_accumvars)) unit_accumvars <- data@unit_accumvars

    if(!missing(covar)){
      if(timename %in% names(covar)) tcovar <- timename
      else{
        pomp:::pStop_(sQuote("covariate"), ' data.frame should have a time column with the same name as the ',
                      'observation data')
      }
      upos_cov <- match(unitname, names(covar))
      tpos_cov <- match(tcovar, names(covar))
      if(missing(shared_covarnames)) unit_covarnames <- names(covar)[-c(upos_cov, tpos_cov)]
      else {
        pos_shared_cov <- match(shared_covarnames, names(covar))
        unit_covarnames <- names(covar)[-c(upos_cov, tpos_cov, pos_shared_cov)]
      }
      tmp <- 1:length(unit_names)
      names(tmp) <- unit_names
      pomp_covar <- covar %>% dplyr::mutate(ui = match(covar[,unitname], names(tmp)))
      pomp_covar <- pomp_covar %>% tidyr::gather(unit_covarnames, key = 'covname', value = 'val')
      pomp_covar <- pomp_covar %>% dplyr::mutate(covname = paste0(covname,ui)) %>% dplyr::select(-upos_cov) %>% dplyr::select(-ui)
      pomp_covar <- pomp_covar %>% tidyr::spread(key = covname, value = val)
      cov_col_order <- c()
      for(cn in unit_covarnames){
        for(i in 1:U){
          cov_col_order = c(cov_col_order, paste0(cn, i))
        }
      }
      pomp_covar <- pomp_covar[, c(timename, cov_col_order)]
      pomp_covar <- pomp::covariate_table(pomp_covar, times=tcovar)
    } else pomp_covar <- data@covar

    if (missing(t0)) t0 <- data@t0
    if (missing(rinit)) rinit <- data@rinit
    if (missing(rprocess)) rprocess <- data@rprocess
    else if (is.null(rprocess)) rprocess <- pomp:::rproc_plugin()
    if (missing(dprocess)) dprocess <- data@dprocess
    if (missing(rmeasure)) rmeasure <- data@rmeasure
    if (missing(dmeasure)) dmeasure <- data@dmeasure
    if (missing(dunit_measure)) dunit_measure <- data@dunit_measure
    if (missing(munit_measure)) munit_measure <- data@munit_measure
    if (missing(vunit_measure)) vunit_measure <- data@vunit_measure
    if (missing(eunit_measure)) eunit_measure <- data@eunit_measure
    if (missing(runit_measure)) runit_measure <- data@runit_measure
    if (missing(skeleton)) skeleton <- data@skeleton
    else if (is.null(skeleton)) skeleton <- skel_plugin()
    if (missing(rprior)) rprior <- data@rprior
    if (missing(dprior)) dprior <- data@dprior
    if (missing(partrans)) partrans <- data@partrans
    else if (is.null(partrans)) partrans <- parameter_trans()
    if (missing(params) && missing(paramnames)){
      params <- data@params
      paramnames <- names(data@params)
    } else{
      if (!missing(params)) paramnames <- names(params)
    }
    if (missing(unit_accumvars)) accumvars <- data@accumvars
    .solibs <- data@solibs

    # Get all names before call to hitch()
    if (!missing(covar)) pomp_covarnames <- paste0(rep(unit_covarnames,each=U),1:U)
    else  pomp_covarnames <- pomp:::get_covariate_names(data@covar)
    if (!missing(unit_accumvars)) pomp_accumvars <- paste0(rep(unit_accumvars,each=U),1:U)
    else pomp_accumvars <- data@accumvars
    mparamnames <- paste("M_", paramnames, sep = "")

    # We will always have a global giving us the number of spatial units
    if(missing(globals)) globals <- Csnippet(paste0("const int U = ",length(unit_names),";\n"))
    else globals <- Csnippet(paste0(paste0("\nconst int U = ",length(unit_names),";\n"),globals@text))
    po <- pomp(data = data,
               t0 = t0,
               rprocess = rprocess,
               rmeasure = rmeasure,
               dprocess = dprocess,
               dmeasure = dmeasure,
               skeleton = skeleton,
               rinit = rinit,
               covar = pomp_covar,
               statenames=pomp_statenames,
               accumvars=pomp_accumvars,
               paramnames = paramnames,
               globals = globals,
               cdir = cdir,
               cfile = cfile,
               shlib.args = shlib.args,
               partrans = partrans,
               ...,
               verbose=verbose
    )

    hitches <- pomp::hitch(
      eunit_measure=eunit_measure,
      munit_measure=munit_measure,
      vunit_measure=vunit_measure,
      dunit_measure=dunit_measure,
      runit_measure=runit_measure,
      templates=eval(spatPomp_workhorse_templates),
      obsnames = paste0(unit_obsnames,"1"),
      statenames = paste0(unit_statenames,"1"),
      paramnames=paramnames,
      covarnames=pomp_covarnames,
      PACKAGE=PACKAGE,
      globals=globals,
      cfile=cfile,
      cdir=cdir,
      shlib.args=shlib.args,
      verbose=verbose
    )
    pomp:::solibs(po) <- hitches$lib
    new(
      "spatPomp",
      po,
      unit_names = unit_names,
      unit_statenames = unit_statenames,
      unit_obsnames = unit_obsnames,
      unitname = unitname,
      shared_covarnames = shared_covarnames,
      unit_covarnames=as.character(unit_covarnames),
      unit_accumvars = unit_accumvars,
      eunit_measure=hitches$funs$eunit_measure,
      munit_measure=hitches$funs$munit_measure,
      vunit_measure=hitches$funs$vunit_measure,
      dunit_measure=hitches$funs$dunit_measure,
      runit_measure=hitches$funs$runit_measure
    )
  }
)
