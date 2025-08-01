test_that("TMB IID simulation works", {
  skip_on_cran()

  set.seed(1)
  predictor_dat <- data.frame(
    X = runif(2000), Y = runif(2000),
    a1 = rnorm(2000), year = rep(1:10, each = 200)
  )
  mesh <- make_mesh(predictor_dat, xy_cols = c("X", "Y"), cutoff = 0.1)

  sim_dat <- sdmTMB_simulate(
    formula = ~ 1 + a1,
    data = predictor_dat,
    time = "year",
    mesh = mesh,
    family = gaussian(),
    range = 0.5,
    sigma_E = 0.1,
    phi = 0.1,
    sigma_O = 0.2,
    seed = 42,
    B = c(0.2, -0.4) # B0 = intercept, B1 = a1 slope
  )
  fit <- sdmTMB(observed ~ a1, sim_dat, mesh = mesh, time = "year")
  b <- tidy(fit)
  b
  expect_equal(b$estimate[b$term == "a1"], -0.4, tolerance = 0.1)
  expect_equal(b$estimate[b$term == "(Intercept)"], 0.2, tolerance = 0.2)
  b <- tidy(fit, "ran_pars")
  b
})

test_that("TMB AR1 simulation works", {
  skip_on_cran()

  set.seed(1)
  predictor_dat <- data.frame(
    X = runif(2000), Y = runif(2000),
    a1 = rnorm(2000), year = rep(1:10, each = 200)
  )
  mesh <- make_mesh(predictor_dat, xy_cols = c("X", "Y"), cutoff = 0.1)
  sim_dat <- sdmTMB_simulate(
    formula = ~ 1 + a1,
    data = predictor_dat,
    time = "year",
    mesh = mesh,
    family = gaussian(),
    range = 0.5,
    sigma_E = 0.1,
    phi = 0.1,
    sigma_O = 0,
    seed = 42,
    rho = 0.8, #<
    B = c(0.2, -0.4) # B0 = intercept, B1 = a1 slope
  )
  fit <- sdmTMB(observed ~ a1, sim_dat,
    mesh = mesh, time = "year",
    spatiotemporal = "ar1", spatial = "off"
  )
  b <- tidy(fit)
  b
  b <- tidy(fit, "ran_pars")
  b
  rho_hat <- b$estimate[b$term == "rho"]
  expect_true(rho_hat > 0.7 && rho_hat < 0.9)
  sigma_E_hat <- b$estimate[b$term == "sigma_E"]
  expect_true(sigma_E_hat > 0.07 && sigma_E_hat < 0.13)
})

test_that("TMB RW simulation works", {
  skip_on_cran()

  set.seed(1)
  predictor_dat <- data.frame(
    X = runif(2000), Y = runif(2000),
    a1 = rnorm(2000), year = rep(1:20, each = 200)
  )
  mesh <- make_mesh(predictor_dat, xy_cols = c("X", "Y"), cutoff = 0.1)

  sim_dat <- sdmTMB_simulate(
    formula = ~1,
    data = predictor_dat,
    time = "year",
    mesh = mesh,
    family = gaussian(),
    range = 0.3,
    sigma_E = 0.1,
    phi = 0.05,
    sigma_O = 0,
    seed = 42,
    rho = 1, #<
    B = 0
  )
  fit_ar1 <- sdmTMB(observed ~ 0,
    sim_dat,
    mesh = mesh, time = "year",
    spatiotemporal = "ar1", #<
    spatial = "off"
  )
  b_ar1 <- tidy(fit_ar1, "ran_pars")
  b_ar1
  rho_hat <- b_ar1$estimate[b_ar1$term == "rho"]
  expect_true(rho_hat > 0.9)
  sigma_E_hat_ar1 <- b_ar1$estimate[b_ar1$term == "sigma_E"]

  fit_rw <- sdmTMB(observed ~ 0,
    sim_dat,
    mesh = mesh, time = "year",
    spatiotemporal = "rw", #<
    spatial = "off"
  )
  b_rw <- tidy(fit_rw, "ran_pars")
  b_rw
  sigma_E_hat_rw <- b_rw$estimate[b_rw$term == "sigma_E"]
  sigma_E_hat_rw
  expect_true(sigma_E_hat_rw > 0.07 && sigma_E_hat_rw < 1.13)
  expect_true(sigma_E_hat_rw < sigma_E_hat_ar1)
})

test_that("TMB breakpt sims work", {
  skip_on_cran()

  set.seed(1)
  predictor_dat <- data.frame(
    X = runif(1000), Y = runif(1000),
    a1 = rnorm(1000)
  )
  mesh <- make_mesh(predictor_dat, xy_cols = c("X", "Y"), cutoff = 0.2)
  sim_dat <- sdmTMB_simulate(
    formula = ~ 1 + breakpt(a1),
    data = predictor_dat,
    mesh = mesh,
    family = gaussian(),
    range = 0.5,
    phi = 0.02,
    sigma_O = 0.001,
    seed = 42,
    B = 0,
    threshold_coefs = c(0.3, 0)
  )
  plot(predictor_dat$a1, sim_dat$observed)
  expect_lt(max(sim_dat$observed), 0.1)
  sim_dat$a1 <- predictor_dat$a1
  fit <- sdmTMB(observed ~ 1 + breakpt(a1), sim_dat, mesh = mesh, spatial = "off",
    control = sdmTMBcontrol(newton_loops = 1L))
  b <- tidy(fit)
  expect_gt(b$estimate[b$term == "a1-breakpt"], -0.02)
  expect_lt(b$estimate[b$term == "a1-breakpt"], 0.02)
  expect_gt(b$estimate[b$term == "a1-slope"], 0.28)
  expect_lt(b$estimate[b$term == "a1-slope"], 0.32)

  sim_dat <- sdmTMB_simulate(
    formula = ~ 1 + logistic(a1),
    data = predictor_dat,
    mesh = mesh,
    family = gaussian(),
    range = 0.5,
    phi = 0.001,
    sigma_O = 0.001,
    seed = 42,
    B = 0,
    threshold_coefs = c(0.2, 0.4, 0.5)
  )
  plot(predictor_dat$a1, sim_dat$observed)
  expect_lt(max(sim_dat$observed), 0.53)
  expect_gt(min(sim_dat$observed), -0.05)
})

test_that("simulate.sdmTMB returns the right length", {
  skip_on_cran()
  pcod$os <- rep(log(0.01), nrow(pcod)) # offset
  m <- sdmTMB(
    data = pcod,
    formula = density ~ 0,
    time_varying = ~ 1,
    offset = pcod$os,
    family = tweedie(link = "log"),
    spatial = "off",
    time = "year",
    extra_time = c(2006, 2008, 2010, 2012, 2014, 2016),
    spatiotemporal = "off"
  )
  s <- simulate(m, nsim = 2)
  expect_equal(nrow(s), nrow(pcod))
})

test_that("simulate.sdmTMB works with sizes in binomial GLMs #465", {
  skip_on_cran()
  set.seed(1)
  w <- sample(1:10, size = 200, replace = TRUE)
  x <- rnorm(200)
  dat <- data.frame(y = stats::rbinom(length(w), size = w, prob = plogis(x * 0.5)))
  dat$prop <- dat$y / w
  dat$x <- x
  fit <- sdmTMB(prop ~ x, data = dat, weights = w, family = binomial(), spatial = "off")
  dat$X <- dat$Y <- NA # FIXME
  set.seed(1)
  snd <- simulate(fit, nsim = 500, newdata = dat, size = w)
  set.seed(1)
  s <- simulate(fit, nsim = 500)
  expect_equal(as.matrix(s), as.matrix(snd), ignore_attr = TRUE)
  expect_true(nrow(snd) == 200L)
  expect_true(ncol(snd) == 500L)
  sim_means <- rowMeans(snd)
  expect_gt(cor(sim_means, dat$y), 0.7)
})

test_that("coarse meshes with zeros in simulation still return fields #370", {
  set.seed(123)
  predictor_dat <- data.frame(
    X = runif(100), Y = runif(100),
    a1 = rnorm(100), year = rep(1:2, each = 50))
  mesh <- sdmTMB::make_mesh(predictor_dat, xy_cols = c("X", "Y"), n_knots = 30)
  sim_dat <- sdmTMB::sdmTMB_simulate(
    formula = ~ 1 + a1,
    data = predictor_dat,
    time = "year",
    mesh = mesh,
    family = gaussian(),
    range = 0.5,
    sigma_E = 0.1,
    phi = 0.1,
    sigma_O = 0.2,
    seed = 42,
    B = c(0.2, -0.4) # B0 = intercept, B1 = a1 slope
  )
  nm <- names(sim_dat)
  expect_true("omega_s" %in% nm)
  expect_true("epsilon_st" %in% nm)
  expect_false("zeta_s" %in% nm)
})

test_that("simulate without observation error works for binomial likelihoods #431", {
  mesh <- make_mesh(pcod, c("X", "Y"), cutoff = 30)
  fit.dg <- sdmTMB(density ~ 1,
    data = pcod, mesh = mesh, family = delta_gamma(type="standard")
  )
  s.dg <- simulate(
    fit.dg,
    newdata = qcs_grid,
    type = "mle-mvn", # fixed effects at MLE values and random effect MVN draws
    mle_mvn_samples = "multiple", # take an MVN draw for each sample
    nsim = 50, # increase this for more stable results
    observation_error = FALSE, # do not include observation error
    seed = 23859
  )
  expect_gt(min(s.dg), 0)
  m <- apply(s.dg, 1, mean)
  p <- predict(fit.dg, newdata = qcs_grid)
  expect_gt(cor(plogis(p$est1) * exp(p$est2), m), 0.95)

  fit.b <- sdmTMB(present ~ 1,
    data = pcod, mesh = mesh, family = binomial()
  )
  s.b <- simulate(
    fit.b,
    newdata = qcs_grid,
    type = "mle-mvn", # fixed effects at MLE values and random effect MVN draws
    mle_mvn_samples = "multiple", # take an MVN draw for each sample
    nsim = 50, # increase this for more stable results
    observation_error = FALSE, # do not include observation error
    seed = 23859
  )
  expect_gt(min(s.dg), 0)
  m <- apply(s.b, 1, mean)
  p <- predict(fit.b, newdata = qcs_grid)
  expect_gt(cor(plogis(p$est), m), 0.95)

  # with size specified
  expect_error({simulate(
    fit.b,
    newdata = qcs_grid,
    nsim = 1,
    observation_error = FALSE,
    size = c(1, 2, 3)
  )}, regexp = "size")

  s.b1 <- simulate(
    fit.b,
    newdata = qcs_grid,
    type = "mle-mvn", # fixed effects at MLE values and random effect MVN draws
    mle_mvn_samples = "multiple", # take an MVN draw for each sample
    nsim = 50, # increase this for more stable results
    observation_error = FALSE, # do not include observation error
    seed = 23859,
    size = sample(1:9, size = nrow(qcs_grid), replace = TRUE)
  )
  expect_false(identical(s.b, s.b1))
})
