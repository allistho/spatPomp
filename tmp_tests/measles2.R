png(filename="measles2-%02d.png",res=100)

library(magrittr)
library(plyr)
library(reshape2)
library(ggplot2)
library(spatPomp3)
options(
  stringsAsFactors=FALSE,
  encoding="UTF-8"
)

## ----read_data-----------------------------------------------------------
read.csv("measlesUKUS.csv",stringsAsFactors=FALSE) %>% subset(country=="UK") -> x
ddply(x,~loc,summarize,mean.pop=mean(pop)) %>% arrange(-mean.pop) -> meanpop
x2 <- mutate(x,loc=ordered(loc,levels=meanpop$loc))
measles_wide <- dcast(x2,decimalYear~loc,value.var="cases")
measles_long <- measles_wide %>% tidyr::gather(LONDON:IPSWICH, key = "unit", value = "cases") %>% arrange(decimalYear)
unit_index <- unique(measles_long[["unit"]])
names(unit_index) <- 1:length(unit_index)

## ----plot_data,fig.width=9,fig.height=8,cache=TRUE,echo=FALSE------------
subset(x,x$loc %in% meanpop$loc[1:20]) %>% mutate(loc=ordered(loc,levels=meanpop$loc)) %>% ggplot(aes(x=decimalYear,y=cases))+
  geom_line()+
  scale_y_continuous(breaks=c(0,4,40,400,4000),trans=scales::log1p_trans())+
  facet_wrap(~loc,ncol=4)+theme(text=element_text(size=7))

## ----spatPomp_object-----------------------------------------------------
D <- 3
obs_names <- "cases"
measles_long <- measles_long %>% dplyr::filter(unit %in% unique(measles_long[['unit']])[1:D])
colnames(measles_long)[1] <- c("year")
measles_long <- subset(measles_long,measles_long$year>1949.99)

## ----covar---------------------------------------------------------------
pop_wide <- dcast(x2,decimalYear~loc,value.var="pop")[,1:(D+1)]
colnames(pop_wide) <- c("year",paste0("pop",1:D))
births_wide <- dcast(x2,decimalYear~loc,value.var="rec")[,1:(D+1)]
birthrate_wide <- births_wide[,-1]*26 ## total annual birth rate for each city
lag <- 3*26  ## lag for birthrate, in number of biweeks
tmp <- matrix(NA,nrow=lag,ncol=ncol(birthrate_wide))
colnames(tmp) <- colnames(birthrate_wide)
lag_birthrate_wide <- rbind(tmp,birthrate_wide[1:(nrow(birthrate_wide)-lag),])
colnames(lag_birthrate_wide) <- paste0("birthrate",1:D)
rownames(lag_birthrate_wide) <- rownames(birthrate_wide)
measles_covar <- cbind(pop_wide,lag_birthrate_wide)
measles_covar <- measles_covar %>% tidyr::gather(pop1:birthrate3, key = 'cov', value = 'val')
measles_covar <- measles_covar %>% mutate(unit = stringr::str_extract(cov,"[0123456789]+$"))
measles_covar <- measles_covar %>% mutate(cov = stringr::str_extract(cov,"^[a-z]+"))
measles_covar <- measles_covar %>% tidyr::spread(key = cov, value = val)
measles_covar <- measles_covar %>% mutate(unit = unit_index[unit])


## ----dist----------------------------------------------------------------
library(geosphere)
s2 <- subset(x,x$biweek==1& x$year==1944 & x$country=="UK")
s3 <- subset(s2,select=c("lon","lat"))
rownames(s3) <- s2$loc
s4 <- s3[meanpop$loc,]
long_lat <- s4[1:D,]
dmat <- matrix(0,D,D)
for(d1 in 1:D) {
  for(d2 in 1:D) {
    dmat[d1,d2] <- round(distHaversine(long_lat[d1,],long_lat[d2,]) / 1609.344,1)
  }
}
p <- meanpop[1:D,2]
v_by_g <- matrix(0,D,D)
dist_mean <- sum(dmat)/(D*(D-1))
p_mean <- mean(p)
for(d1 in 2:D){
  for(d2 in 1:(d1-1)){
    v_by_g[d1,d2] <- (dist_mean*p[d1]*p[d2]) / (dmat[d1,d2] * p_mean^2)
    v_by_g[d2,d1] <- v_by_g[d1,d2]
  }
}
to_C_array <- function(v)paste0("{",paste0(v,collapse=","),"}")
v_by_g_C_rows <- apply(v_by_g,1,to_C_array)
v_by_g_C_array <- to_C_array(v_by_g_C_rows)
v_by_g_C <- Csnippet(paste0("const double v_by_g[",D,"][",D,"] = ",v_by_g_C_array,"; "))
v_by_g_C

## ----rprocess------------------------------------------------------------
states <- c("S","E","I","R","C","W")
state_names <- paste0(rep(states,each=D),1:D)

## initial value parameters
ivp_names <- paste0(state_names[1:(4*D)],"_0")

## regular parameters
he10_rp_names <- c("alpha","iota","R0","cohort","amplitude","gamma","sigma","mu","sigmaSE","rho","psi")
rp_names <- c(he10_rp_names,"D","g")

## all parameters
param_names <- c(rp_names,ivp_names)

rproc <- Csnippet("
  double beta, br, seas, foi, dw, births;
  double rate[6], trans[6];
  double *S = &S1;
  double *E = &E1;
  double *I = &I1;
  double *R = &R1;
  double *C = &C1;
  double *W = &W1;
  const double *pop = &pop1;
  const double *birthrate = &birthrate1;
  int d,e;

  // term-time seasonality
  t = (t-floor(t))*365.25;
  if ((t>=7&&t<=100) || (t>=115&&t<=199) || (t>=252&&t<=300) || (t>=308&&t<=356))
      seas = 1.0+amplitude*0.2411/0.7589;
    else
      seas = 1.0-amplitude;

  // transmission rate
  beta = R0*(gamma+mu)*seas;

  for (d = 0 ; d < D ; d++) {

    // cohort effect
    if (fabs(t-floor(t)-251.0/365.0) < 0.5*dt)
      br = cohort*birthrate[d]/dt + (1-cohort)*birthrate[d];
    else
      br = (1.0-cohort)*birthrate[d];

    // expected force of infection
    foi = pow( (I[d]+iota)/pop[d],alpha);
    // Do we still need iota in a spatPomp version?
    // See also discrepancy between Joonha and Daihai versions
    // Daihai didn't raise pop to the alpha power

    for (e=0; e < D ; e++) {
      if(e != d)
        foi += g * v_by_g[d][e] * (pow(I[e]/pop[e],alpha) - pow(I[d]/pop[d],alpha)) / pop[d];
    }
    // white noise (extrademographic stochasticity)
    dw = rgammawn(sigmaSE,dt);

    rate[0] = beta*foi*dw/dt;  // stochastic force of infection

    // These rates could be outside the d loop if all parameters are shared between units
    rate[1] = mu;			    // natural S death
    rate[2] = sigma;		  // rate of ending of latent stage
    rate[3] = mu;			    // natural E death
    rate[4] = gamma;		  // recovery
    rate[5] = mu;			    // natural I death

    // Poisson births
    births = rpois(br*dt);

    // transitions between classes
    reulermultinom(2,S[d],&rate[0],dt,&trans[0]);
    reulermultinom(2,E[d],&rate[2],dt,&trans[2]);
    reulermultinom(2,I[d],&rate[4],dt,&trans[4]);

    S[d] += births   - trans[0] - trans[1];
    E[d] += trans[0] - trans[2] - trans[3];
    I[d] += trans[2] - trans[4] - trans[5];
    R[d] = pop[d] - S[d] - E[d] - I[d];
    W[d] += (dw - dt)/sigmaSE;  // standardized i.i.d. white noise
    C[d] += trans[4];           // true incidence
  }
")

## ----initializer---------------------------------------------------------
measles_initializer <- Csnippet("
  double *S = &S1;
  double *E = &E1;
  double *I = &I1;
  double *R = &R1;
  double *C = &C1;
  double *W = &W1;
  const double *S_0 = &S1_0;
  const double *E_0 = &E1_0;
  const double *I_0 = &I1_0;
  const double *R_0 = &R1_0;
  const double *pop = &pop1;
  double m;
  int d;
  for (d = 0; d < D; d++) {
    m = pop[d]/(S_0[d]+E_0[d]+I_0[d]+R_0[d]);
    S[d] = nearbyint(m*S_0[d]);
    E[d] = nearbyint(m*E_0[d]);
    I[d] = nearbyint(m*I_0[d]);
    R[d] = nearbyint(m*R_0[d]);
    W[d] = 0;
    C[d] = 0;
  }
")

## ----he_mles-------------------------------------------------------------
read.csv(text="
town,loglik,loglik.sd,mu,delay,sigma,gamma,rho,R0,amplitude,alpha,iota,cohort,psi,S_0,E_0,I_0,R_0,sigmaSE
LONDON,-3804.9,0.16,0.02,4,28.9,30.4,0.488,56.8,0.554,0.976,2.9,0.557,0.116,0.0297,5.17e-05,5.14e-05,0.97,0.0878
BIRMINGHAM,-3239.3,1.55,0.02,4,45.6,32.9,0.544,43.4,0.428,1.01,0.343,0.331,0.178,0.0264,8.96e-05,0.000335,0.973,0.0611
LIVERPOOL,-3403.1,0.34,0.02,4,49.4,39.3,0.494,48.1,0.305,0.978,0.263,0.191,0.136,0.0286,0.000184,0.00124,0.97,0.0533
MANCHESTER,-3250.9,0.66,0.02,4,34.4,56.8,0.55,32.9,0.29,0.965,0.59,0.362,0.161,0.0489,2.41e-05,3.38e-05,0.951,0.0551
LEEDS,-2918.6,0.23,0.02,4,40.7,35.1,0.666,47.8,0.267,1,1.25,0.592,0.167,0.0262,6.04e-05,3e-05,0.974,0.0778
SHEFFIELD,-2810.7,0.21,0.02,4,54.3,62.2,0.649,33.1,0.313,1.02,0.853,0.225,0.175,0.0291,6.04e-05,8.86e-05,0.971,0.0428
BRISTOL,-2681.6,0.5,0.02,4,64.3,82.6,0.626,26.8,0.203,1.01,0.441,0.344,0.201,0.0358,9.62e-06,5.37e-06,0.964,0.0392
NOTTINGHAM,-2703.5,0.53,0.02,4,70.2,115,0.609,22.6,0.157,0.982,0.17,0.34,0.258,0.05,1.36e-05,1.41e-05,0.95,0.038
HULL,-2729.4,0.39,0.02,4,42.1,73.9,0.582,38.9,0.221,0.968,0.142,0.275,0.256,0.0371,1.2e-05,1.13e-05,0.963,0.0636
BRADFORD,-2586.6,0.68,0.02,4,45.6,129,0.599,32.1,0.236,0.991,0.244,0.297,0.19,0.0365,7.41e-06,4.59e-06,0.964,0.0451
",stringsAsFactors=FALSE) -> he10_mles

if(D>10) stop("Code only designed for D<=10")
test_params <- c(
  unlist(he10_mles[1,he10_rp_names]),
  D=D,
  g=100,
  he10_mles[1:D,"S_0"],
  he10_mles[1:D,"E_0"],
  he10_mles[1:D,"I_0"],
  he10_mles[1:D,"R_0"]
)
names(test_params) <- param_names


## ----dmeasure------------------------------------------------------------
measles_dmeas <- Csnippet("
  const double *C = &C1;
  const double *cases = &cases1;
  double m,v;
  double tol = pow(1.0e-18,D);
  int d;

  lik = 0;
  for (d = 0; d < D; d++) {
    m = rho*C[d];
    v = m*(1.0-rho+psi*psi*m);
    if (cases[d] > 0.0) {
      lik += log(pnorm(cases[d]+0.5,m,sqrt(v)+tol,1,0)-pnorm(cases[d]-0.5,m,sqrt(v)+tol,1,0)+tol);
    } else {
      lik += log(pnorm(cases[d]+0.5,m,sqrt(v)+tol,1,0)+tol);
    }
  }
  if(!give_log) lik = exp(lik);
")

## ----rmeasure------------------------------------------------------------
measles_rmeas <- Csnippet("
  const double *C = &C1;
  double *cases = &cases1;
  double m,v;
  double tol = pow(1.0e-18,D);
  int d;

  for (d = 0; d < D; d++) {
    m = rho*C[d];
    v = m*(1.0-rho+psi*psi*m);
    cases[d] = rnorm(m,sqrt(v)+tol);
    if (cases[d] > 0.0) {
      cases[d] = nearbyint(cases[d]);
    } else {
      cases[d] = 0.0;
    }
  }
")
measles <- spatPomp(measles_long,
  units = "unit",
  times = "year",
  t0 = min(measles_long$year)-1/26,
  unit_statenames = c('S','E','I','R','C','W'),
  global_statenames = c('P'),
  covar = measles_covar,
  tcovar = "year",
  rprocess=euler.sim(rproc, delta.t=2/365),
  zeronames = c(paste0("C",1:D),paste0("W",1:D)),
  paramnames=param_names,globals=v_by_g_C,
  initializer=measles_initializer,
  dmeasure=measles_dmeas,
  rmeasure=measles_rmeas)

## ----sim_test------------------------------------------------------------
set.seed(8375621)
sim <- simulate(measles,params=test_params)

## ----sim_plot,fig.width=9,fig.height=8,eval=T----------------------------
sim2 <- as.data.frame(sim)
subset(sim2,select=!grepl("^W",colnames(sim2))) %>% melt(id.vars="time") -> sim3
ggplot(sim3, aes(x=time,y=value))+
  geom_line()+
  facet_wrap(~variable,ncol=D)+theme(text=element_text(size=10))+
  scale_y_continuous(breaks=c(0,100,10000,1e6),trans=scales::log1p_trans())

## ----vec_dmeasure--------------------------------------------------------
vec_dmeas <- function(y, x, t, params, log = FALSE, ...){
  lik = numeric(length = D)
  for(i in 1:D){
    m = params["rho"]*x[paste("C", i, sep = "")]
    v = m*(1.0 - params["rho"] + params["psi"]*params["psi"]*m)
    tol = (1e-18)^D
    if(y[obs_names[i]]>0.0){
      lik[i] = log(pnorm(y[obs_names[i]] + 0.5, mean = m, sd = sqrt(v) + tol) - pnorm(y[obs_names[i]]-0.5, mean = m, sd = sqrt(v) + tol)+tol)
    }
    else{
      lik[i] = log(pnorm(y[obs_names[i]] + 0.5, mean = m, sd = sqrt(v) + tol) + tol)
    }
  }
  if(!log) return(exp(lik))
  else  return(lik)
}

## ----dunit_measure-------------------------------------------------------
unit_dmeas <- Csnippet("
                       double m = rho*C;
                       double v = m*(1.0-rho+psi*psi*m);
                       double tol = 1.0e-18;
                       if (cases > 0.0) {
                         lik = pnorm(cases+0.5,m,sqrt(v)+tol,1,0)-pnorm(cases-0.5,m,sqrt(v)+tol,1,0)+tol;
                       } else {
                           lik = pnorm(cases+0.5,m,sqrt(v)+tol,1,0)+tol;
                       }
                       ")
measles <- spatPomp(measles_long,
  units = "unit",
  times = "year",
  t0 = min(measles_long$year)-1/26,
  unit_statenames = c('S','E','I','R','C','W'),
  global_statenames = c('P'),
  covar = measles_covar,
  tcovar = "year",
  rprocess=euler.sim(rproc, delta.t=2/365),
  zeronames = c(paste0("C",1:D),paste0("W",1:D)),
  paramnames=param_names,globals=v_by_g_C,
  initializer=measles_initializer,
  dmeasure=measles_dmeas,
  dunit_measure=unit_dmeas,
  rmeasure=measles_rmeas)

## ----naive_pfilter3, eval = T--------------------------------------------
pfilter3(measles, params = test_params, Np=1000, tol = (1e-17)^3) -> pf1

## ----naive_pfilter, eval = T---------------------------------------------
pfilter(measles, params = test_params, Np=1000, tol = (1e-17)^3) -> pf2

dev.off()
