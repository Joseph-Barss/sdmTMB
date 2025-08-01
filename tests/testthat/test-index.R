test_that("get_index works", {
  skip_on_cran()

  pcod_spde <- make_mesh(pcod, c("X", "Y"), n_knots = 50, type = "kmeans")
  m <- sdmTMB(
    data = pcod,
    formula = density ~ 0 + as.factor(year),
    spatiotemporal = "off", # speed
    time = "year", mesh = pcod_spde,
    family = tweedie(link = "log")
  )
  nd <- replicate_df(qcs_grid, "year", unique(pcod$year))
  predictions <- predict(m, newdata = nd, return_tmb_object = TRUE)
  ind <- get_index(predictions, bias_correct = FALSE)
  ind
  expect_s3_class(ind, "data.frame")

  indsp <- get_index_split(m, nd, nsplit = 2, bias_correct = FALSE)
  expect_equal(ind, indsp)
  expect_identical(chunk_time(c(1, 2, 3), 2), list(`1` = c(1, 2), `2` = 3))
  expect_error(chunk_time(c(1, 2), 0))
  expect_error(chunk_time(c(1, 2), -1))
  expect_error(chunk_time(c(1, 2), "a"))
  expect_error(chunk_time(c(1, 2), 0.2))
  expect_error(indsp <- get_index_split(m, nd, nsplit = 2, predict_args = "a"), regexp = "list")

  ind <- get_index(predictions, bias_correct = TRUE)
  expect_s3_class(ind, "data.frame")

  cog <- get_cog(predictions)
  cog
  expect_s3_class(cog, "data.frame")

  cog <- get_cog(predictions, format = "wide")
  cog
  expect_s3_class(cog, "data.frame")

  expect_error(get_index(predictions, area = c(1, 2, 3)), regexp = "area")

  # splits work with areas:
  set.seed(1)
  areas <- rlnorm(nrow(nd), meanlog = 0, sdlog = 0.1)
  ind <- get_index(predictions, area = areas, bias_correct = FALSE)
  indsp <- get_index_split(m, nd, nsplit = 2, area = areas, bias_correct = FALSE)
  expect_equal(ind, indsp)

  # splits work with offsets:
  m2 <- sdmTMB(
    data = dogfish,
    formula = catch_weight ~ 0 + as.factor(year),
    offset = log(dogfish$area_swept),
    spatiotemporal = "off", spatial = "off",
    time = "year",
    family = tweedie(link = "log")
  )
  nd2 <- replicate_df(wcvi_grid, "year", unique(dogfish$year))
  set.seed(1)
  fake_offset <- rnorm(nrow(nd2), 0, 0.1)
  predictions2 <- predict(m2, newdata = nd2, return_tmb_object = TRUE, offset = fake_offset)
  ind <- get_index(predictions2, bias_correct = FALSE)
  indsp <- get_index_split(m2, nd2, nsplit = 2, predict_args = list(offset = fake_offset), bias_correct = FALSE)
  expect_equal(ind, indsp)
})

test_that("get_index works with subsets of years", {
  skip_on_cran()

  m <- sdmTMB(
    density ~ 0 + as.factor(year),
    data = pcod_2011,
    time = "year",
    spatiotemporal = "off",
    spatial = 'off',
    mesh = pcod_mesh_2011,
    family = delta_gamma()
  )
  nd <- replicate_df(qcs_grid, "year", unique(pcod_2011$year))
  p_full <- predict(m, newdata = nd, return_tmb_object = TRUE)

  nd_2011 <- replicate_df(qcs_grid, "year", 2011)
  p_2011 <- predict(m, newdata = nd_2011, return_tmb_object = TRUE)

  nd_2 <- replicate_df(qcs_grid, "year", c(2011, 2013))
  p_2 <- predict(m, newdata = nd_2, return_tmb_object = TRUE)

  nd_3 <- replicate_df(qcs_grid, "year", c(2015, 2011))
  p_3 <- predict(m, newdata = nd_3, return_tmb_object = TRUE)

  index_full <- get_index(p_full, bias_correct = TRUE)
  expect_equal(index_full$est, c(322529.7268, 293854.3696, 390942.2649, 184368.2756), tolerance = 0.01)
  index_2011 <- get_index(p_2011, bias_correct = TRUE)
  index_2 <- get_index(p_2, bias_correct = TRUE)
  index_3 <- get_index(p_3, bias_correct = TRUE)
  cog <- get_cog(p_full)

  expect_equal(index_2011$est, subset(index_full, year == 2011)$est)
  expect_equal(index_2$est, subset(index_full, year %in% c(2011, 2013))$est)
  expect_equal(index_3$est, subset(index_full, year %in% c(2015, 2011))$est)

  index_apply <- lapply(unique(pcod_2011$year), \(y) {
    nd <- replicate_df(qcs_grid, "year", y)
    p <- predict(m, newdata = nd, return_tmb_object = TRUE)
    get_index(p, bias_correct = TRUE)
  })
  index_apply <- do.call(rbind, index_apply)
  expect_equal(index_apply, index_full)

  cog <- get_cog(p_full)
  eao <- get_eao(p_full)
  cog2011 <- get_cog(p_2011)
  eao2011 <- get_eao(p_2011)
  expect_equal(eao2011$est, eao$est[eao$year == 2011])
  expect_equal(cog2011$est, cog2011$est[cog2011$year == 2011])
})

test_that("Index integration with area vector works with extra time and possibly not all time elements in prediction data #323", {
  skip_on_cran()
  fit <- sdmTMB(
    density ~ s(depth),
    time_varying_type = 'ar1',
    time_varying = ~ 1,
    time = 'year',
    spatial = 'off',
    spatiotemporal = 'off',
    extra_time = c(2012, 2014, 2016),
    data = pcod_2011,
    family = tweedie(link = "log")
  )
  # with all years:
  nd <- replicate_df(qcs_grid, "year", seq(2011, 2017))
  nd$area <- 4
  p <- predict(fit, newdata = nd, return_tmb_object = TRUE)
  ind0 <- get_index(p, area = nd$area, bias_correct = FALSE)

  # newdata doesn't have all fitted years:
  nd <- replicate_df(qcs_grid, "year", unique(pcod_2011$year))
  nd$area <- 4
  p <- predict(fit, newdata = nd, return_tmb_object = TRUE)
  ind <- get_index(p, area = nd$area, bias_correct = FALSE)
  if (FALSE) {
    library(ggplot2)
    ggplot(ind, aes(year, est, ymin = lwr, ymax = upr)) + geom_pointrange() +
      geom_pointrange(data = ind0, colour = "red", mapping = aes(x = year + 0.05))
  }
  expect_equal(ind$est - ind0$est[ind0$year %in% seq(2011, 2017, 2)], c(0, 0, 0, 0))
  expect_equal(ind$se - ind0$se[ind0$year %in% seq(2011, 2017, 2)], c(0, 0, 0, 0))
})

test_that("get_index works", {
  skip_on_cran()

  pcod_spde <- make_mesh(pcod, c("X", "Y"), n_knots = 50, type = "kmeans")
  m <- sdmTMB(
    data = pcod,
    formula = density ~ 0 + as.factor(year),
    spatiotemporal = "off", # speed
    time = "year", mesh = pcod_spde,
    family = tweedie(link = "log")
  )

  # add some jittered area data to qcs_grid for testing
  qcs_grid$area <- runif(nrow(qcs_grid), 0.9, 1.1)
  nd <- replicate_df(qcs_grid, "year", unique(pcod$year))

  predictions <- predict(m, newdata = nd, return_tmb_object = TRUE)

  # get predictions with area passed as vector
  ind <- get_index(predictions, area = nd$area, bias_correct = FALSE)
  # get predictions with area as a named column
  ind2 <- get_index(predictions, area = "area", bias_correct = FALSE)
  expect_equal(ind, ind2)

  # get predictions with area passed as vector
  eao <- get_eao(predictions, area = nd$area)
  # get predictions with area as a named column
  eao2 <- get_eao(predictions, area = "area")
  expect_equal(eao, eao2)

  # get predictions with area passed as vector
  cog <- get_cog(predictions, area = nd$area)
  # get predictions with area as a named column
  cog2 <- get_cog(predictions, area = "area")
  expect_equal(cog, cog2)
})

# test_that("get_index faster epsilon bias correction", {
#   skip_on_cran()
#
#   library(sdmTMB)
#   mesh <- make_mesh(pcod, c('X', 'Y'), cutoff = 5)
#
#   m <- sdmTMB(
#     density ~ factor(year),
#     data = pcod,
#     mesh = mesh,
#     time = "year",
#     family = delta_gamma()
#   )
#   nd <- replicate_df(qcs_grid, "year", unique(pcod$year))
#   p <- predict(m, newdata = nd, return_tmb_object = TRUE)
#
#   TRACE=TRUE
#
#   INTERN=TRUE
#   LOWRANK=TRUE
#   index <- get_index(p, bias_correct = TRUE)
#
#   INTERN=FALSE
#   LOWRANK=FALSE
#   index <- get_index(p, bias_correct = TRUE)
#
#   INTERN=FALSE
#   LOWRANK=TRUE
#   index <- get_index(p, bias_correct = TRUE)
#
#   INTERN=TRUE
#   LOWRANK=FALSE
#   index <- get_index(p, bias_correct = TRUE)
#
# })

# https://github.com/pbs-assess/sdmTMB/issues/408
test_that("Models error our nicely with Inf or -Inf covariates before get_index()", {
  d <- pcod
  d$depth_scaled[1] <- -Inf
  expect_error(m <- sdmTMB(
    data = d,
    formula = density ~ 0 + as.factor(year) + depth_scaled,
    spatiotemporal = "off", # speed
    spatial = "off", # speed
    time = "year",
    family = delta_gamma(type = "poisson-link")
  ), regexp = "Inf")
})

