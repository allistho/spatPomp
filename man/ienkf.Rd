% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ienkf.R
\name{ienkf-spatPomp}
\alias{ienkf-spatPomp}
\alias{ienkf,spatPomp-method}
\title{Iterative Ensemble Kalman Filter (IENKF)}
\usage{
\S4method{ienkf}{spatPomp}(
  data,
  Nenkf = 1,
  rw.sd,
  cooling.type = c("geometric", "hyperbolic"),
  cooling.fraction.50,
  Np,
  tol = 0,
  max.fail = Inf,
  ...,
  verbose = getOption("verbose", FALSE)
)
}
\arguments{
\item{data}{either a data frame holding the spatiotemporal data,
or an object of class \sQuote{spatPomp},
i.e., the output of another \pkg{spatPomp} calculation.}

\item{Nenkf}{number of iterations of perturbed ENKF.}

\item{rw.sd}{specification of the magnitude of the random-walk perturbations that will be applied to some or all model parameters.
Parameters that are to be estimated should have positive perturbations specified here.
The specification is given using the \code{\link[pomp]{rw.sd}} function, which creates a list of unevaluated expressions.
The latter are evaluated in a context where the model time variable is defined (as \code{time}).
The expression \code{ivp(s)} can be used in this context as shorthand for \preformatted{ifelse(time==time[1],s,0).}
Likewise, \code{ivp(s,lag)} is equivalent to \preformatted{ifelse(time==time[lag],s,0).}
See below for some examples.

The perturbations that are applied are normally distributed with the specified s.d.
If parameter transformations have been supplied, then the perturbations are applied on the transformed (estimation) scale.}

\item{cooling.type}{specifications for the cooling schedule,
i.e., the manner and rate with which the intensity of the parameter perturbations is reduced with successive filtering iterations.
\code{cooling.type} specifies the nature of the cooling schedule.
See below (under \dQuote{Specifying the perturbations}) for more detail.}

\item{cooling.fraction.50}{specifications for the cooling schedule,
i.e., the manner and rate with which the intensity of the parameter perturbations is reduced with successive filtering iterations.
\code{cooling.type} specifies the nature of the cooling schedule.
See below (under \dQuote{Specifying the perturbations}) for more detail.}

\item{Np}{the number of particles to use.
This may be specified as a single positive integer, in which case the same number of particles will be used at each timestep.
Alternatively, if one wishes the number of particles to vary across timesteps, one may specify \code{Np} either as a vector of positive integers of length \preformatted{length(time(object,t0=TRUE))} or as a function taking a positive integer argument.
In the latter case, \code{Np(k)} must be a single positive integer, representing the number of particles to be used at the \code{k}-th timestep:
\code{Np(0)} is the number of particles to use going from \code{timezero(object)} to \code{time(object)[1]},
\code{Np(1)}, from \code{timezero(object)} to \code{time(object)[1]},
and so on,
while when \code{T=length(time(object))}, \code{Np(T)} is the number of particles to sample at the end of the time-series.}

\item{...}{additional arguments supply new or modify existing model characteristics or components.
See \code{\link[pomp]{pomp}} for a full list of recognized arguments.

When named arguments not recognized by \code{\link[pomp]{pomp}} are provided, these are made available to all basic components via the so-called \dfn{userdata} facility.
This allows the user to pass information to the basic components outside of the usual routes of covariates (\code{covar}) and model parameters (\code{params}).
See \link[pomp:userdata]{?userdata} for information on how to use this facility.}

\item{verbose}{logical; if \code{TRUE}, diagnostic messages will be printed to the console.}
}
\value{
Upon successful completion, \code{ienkf} returns an object of class
\sQuote{ienkfd_spatPomp}.
}
\description{
An implementation of a parameter estimation algorithm combining
ENKF with IF2.
}
\section{Methods}{

The following methods are available for such an object:
\describe{
\item{\code{\link{coef}}}{ gives the Monte Carlo estimate of the maximum likelihood. }
}
}

\examples{
# Create a simulation of a GBM using a default parameter set
gbm10 <- gbm(U = 10, N = 30, IVP_values = 35, delta.t = .0001, delta.obs = .001)
gbm10_2 <- gbm10

# Set the initial estimates for the unknown parameters
 coef(gbm10_2) <- c("rho" = 0.7, "sigma"= 0.5, "tau"=0.5, "X1_0"=35, "X2_0"=35,
"X3_0"=35, "X4_0"=35, "X5_0"=35, "X6_0"=35, "X7_0"=35, "X8_0"=35, "X9_0"=35, "X10_0"=35)

# Run IENKF with the specified parameters
ienkf_out <- ienkf(gbm10_2,
Nenkf = ienkf_Nenkf,
rw.sd = rw.sd(
  rho=0.02, sigma=0.02, tau=0.02, X1_0=0.0, X2_0=0.0,
  X3_0=0.0, X4_0=0.0, X5_0=0.0, X6_0=0.0, X7_0=0.0, X8_0=0.0, X9_0=0.0, X10_0=0.0),
cooling.type = "geometric",
cooling.fraction.50 = 0.5,
Np=ienkf_np)

# Get the parameter estimates from the IENKF object
coef(ienkf_out)

}
\references{
Evensen, G. (1994) Sequential data assimilation with a
nonlinear quasi-geostrophic model using Monte Carlo methods to forecast
error statistics Journal of Geophysical Research: Oceans 99:10143--10162

Evensen, G. (2009) Data assimilation: the ensemble Kalman filter
Springer-Verlag.

Anderson, J. L. (2001) An Ensemble Adjustment Kalman Filter for Data
Assimilation Monthly Weather Review 129:2884--2903
}
\seealso{
Other particle filter methods: 
\code{\link{abfir}()},
\code{\link{abf}()},
\code{\link{bootgirf2}()},
\code{\link{bootgirf}()},
\code{\link{bpfilter-spatPomp}},
\code{\link{girf}()},
\code{\link{hippie}()},
\code{\link{igirf}()}

Other \pkg{spatPomp} parameter estimation methods: 
\code{\link{enkf}()},
\code{\link{hippie}()}
}
\concept{\pkg{spatPomp} parameter estimation methods}
\concept{particle filter methods}
