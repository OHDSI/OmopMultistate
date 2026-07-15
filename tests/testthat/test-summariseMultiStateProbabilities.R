test_that("summariseMultistateProbabilities", {
  # create test cdm
  cdm <- omock::mockCdmFromTables(tables = list(
    cohort1 = dplyr::tibble(
      cohort_definition_id = c(1L, 1L, 1L, 2L, 2L, 3L, 1L),
      subject_id = c(rep(1L, 6), 2L),
      cohort_start_date = as.Date("2020-01-01") + c(0L, 100L, 120L, 50L, 110L, 150L, -400L),
      cohort_end_date = cohort_start_date
    )
  )) |>
    copyCdm()

  cdm$cohort1 <- cdm$cohort1 |>
    CohortConstructor::renameCohort(c("treated", "untreated", "death"))

  expect_no_error(
    trans <- transMat(
      x = list(c(2, 3), c(1, 3), c()),
      names = c("treated", "untreated", "death")
    )
  )

  expect_no_error(
    res <- summariseMultistateProbabilities(
      cohort = cdm$cohort1,
      trans = trans
    )
  )

  probabilities <- omopgenerics::tidy(res)
  expect_equal(
    unique(probabilities$variable_name),
    paste0("prob_", colnames(trans))
  )
  expect_true(all(probabilities$probability >= 0))
  expect_true(all(probabilities$probability <= 1))
  totals <- probabilities |>
    dplyr::group_by(.data$initial_state, .data$variable_level) |>
    dplyr::summarise(total = sum(.data$probability), .groups = "drop")
  expect_equal(totals$total, rep(1, nrow(totals)), tolerance = 1e-10)

  expect_no_error(
    plot <- plotMultistateProbabilities(result = res)
  )
  expect_equal(levels(plot$data$state), colnames(trans))

  expect_no_error(
    plotYears <- plotMultistateProbabilities(result = res, timeScale = "years")
  )
  expect_equal(plotYears$labels$x, "Time (year)")

  dropCreatedTables(cdm)
})

test_that("tied transitions produce valid probabilities", {
  trans <- transMat(
    x = list(c(2, 3), c(), c()),
    names = c("a", "b", "c")
  )

  msData <- tidyr::crossing(subject_id = 1:9, trans = 1:2) |>
    dplyr::mutate(
      from = 1L,
      to = .data$trans + 1L,
      from_name = "a",
      to_name = c("b", "c")[.data$trans],
      Tstart = 0,
      Tstop = dplyr::if_else(.data$subject_id >= 8L, 2, 1),
      status = as.integer(
        (.data$subject_id <= 6 & .data$trans == 1) |
          (.data$subject_id %in% c(7L, 8L) & .data$trans == 2)
      )
    )
  start <- dplyr::tibble(
    initial_state = c("a", "b", "c"),
    prob = c(1, 0, 0)
  )

  probabilities <- extractProbabilities(msData, trans, Inf, start)

  expect_true(all(probabilities$probability >= 0))
  expect_true(all(probabilities$probability <= 1))
  expect_equal(
    probabilities |>
      dplyr::filter(.data$initial_state == "a", .data$variable_level == "1") |>
      dplyr::arrange(.data$variable_name) |>
      dplyr::pull("probability"),
    c(2 / 9, 6 / 9, 1 / 9)
  )
})

test_that("stratified probabilities are estimated for each requested group", {
  cohort <- dplyr::tibble(
    subject_id = rep(1:8, each = 3),
    cohort_definition_id = rep(1:3, times = 8),
    cohort_start_date = as.Date("2020-01-01") +
      unlist(lapply(1:8, \(i) c(0, 5 + i, 20 + 2 * i))),
    cohort_end_date = cohort_start_date,
    sex = rep(rep(c("Female", "Male"), each = 4), each = 3),
    age_group = rep(rep(c("young", "old"), times = 4), each = 3)
  )
  cdm <- omock::mockCdmFromTables(tables = list(cohort1 = cohort)) |>
    copyCdm()
  on.exit(dropCreatedTables(cdm), add = TRUE)

  cdm$cohort1 <- cdm$cohort1 |>
    CohortConstructor::renameCohort(c("treated", "untreated", "death"))
  trans <- transMat(
    x = list(c(2), c(3), c()),
    names = c("treated", "untreated", "death")
  )

  result <- summariseMultistateProbabilities(
    cohort = cdm$cohort1,
    trans = trans,
    strata = list("sex", c("sex", "age_group"))
  ) |>
    omopgenerics::tidy()

  observedStrata <- result |>
    dplyr::distinct(.data$sex, .data$age_group)
  expectedStrata <- dplyr::tribble(
    ~sex, ~age_group,
    "overall", "overall",
    "Female", "overall",
    "Male", "overall",
    "Female", "old",
    "Female", "young",
    "Male", "old",
    "Male", "young"
  )
  expect_equal(
    dplyr::arrange(observedStrata, .data$sex, .data$age_group),
    dplyr::arrange(expectedStrata, .data$sex, .data$age_group)
  )
  tolerance <- sqrt(.Machine$double.eps)
  expect_gte(min(result$probability), -tolerance)
  expect_lte(max(result$probability), 1 + tolerance)
})

test_that("strata must be constant within an individual", {
  strataData <- dplyr::tibble(
    subject_id = c(1L, 1L, 2L),
    sex = c("Female", "Male", NA_character_),
    age_group = c("young", "young", "old")
  )

  expect_error(
    getStrataData(strataData, list("sex", "age_group")),
    regexp = "Multiple values of strata for `sex`"
  )

  strataData$sex[2] <- "Female"
  expect_equal(
    getStrataData(strataData, list("sex"))$sex,
    c("Female", "Missing")
  )
})

test_that("a model failure reports and omits the stratum", {
  cohort <- dplyr::tibble(
    subject_id = rep(1:8, each = 3),
    cohort_definition_id = rep(1:3, times = 8),
    cohort_start_date = as.Date("2020-01-01") +
      unlist(lapply(1:8, \(i) c(0, 5 + i, 20 + 2 * i))),
    cohort_end_date = cohort_start_date,
    sex = rep(rep(c("Female", "Male"), each = 4), each = 3)
  )
  cdm <- omock::mockCdmFromTables(tables = list(cohort1 = cohort)) |>
    copyCdm()
  on.exit(dropCreatedTables(cdm), add = TRUE)

  cdm$cohort1 <- cdm$cohort1 |>
    CohortConstructor::renameCohort(c("treated", "untreated", "death"))
  trans <- transMat(
    x = list(c(2), c(3), c()),
    names = c("treated", "untreated", "death")
  )

  originalExtractProbabilities <- extractProbabilities
  testthat::local_mocked_bindings(
    extractProbabilities = function(x, trans, followUp, start) {
      if (identical(unique(x$sex), "Male")) {
        stop("deliberate model failure")
      }
      originalExtractProbabilities(x, trans, followUp, start)
    },
    .package = "OmopMultistate"
  )

  expect_message(
    result <- summariseMultistateProbabilities(
      cohort = cdm$cohort1,
      trans = trans,
      strata = list("sex")
    ),
    regexp = "sex = Male",
    fixed = TRUE
  )
  result <- omopgenerics::tidy(result)
  expect_setequal(unique(result$sex), c("overall", "Female"))
})
