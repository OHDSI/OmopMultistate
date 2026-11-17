test_that("prepareMultistateData validates states and optional arguments", {
  cdm <- omock::mockCdmFromTables(tables = list(
    cohort = dplyr::tibble(
      cohort_definition_id = c(1L, 2L, 3L),
      subject_id = 1L,
      cohort_start_date = as.Date("2020-01-01") + c(0L, 30L, 60L),
      cohort_end_date = cohort_start_date,
      custom_censor_date = as.Date("2020-06-01")
    )
  )) |>
    copyCdm()
  on.exit(dropCreatedTables(cdm), add = TRUE)

  cdm$cohort <- cdm$cohort |>
    CohortConstructor::renameCohort(c("treated", "untreated", "death"))

  trans <- transMat(
    x = list(c(2, 3), c(1, 3), c()),
    names = c("treated", "untreated", "death")
  )
  missingState <- transMat(
    x = list(c(2, 3), c(3), c()),
    names = c("treated", "untreated", "missing")
  )

  expect_error(
    prepareMultistateData(cdm$cohort, missingState),
    "missing"
  )

  expect_no_error(
    msdata <- prepareMultistateData(
      cohort = cdm$cohort,
      trans = trans,
      censorDate = "custom_censor_date",
      stateHierarchy = c("treated", "untreated", "death"),
      stateStep = 0.1
    )
  )
  expect_s3_class(msdata, "msdata")
  expect_identical(attr(msdata, "trans"), trans)
})

test_that("censorDate can refer to a column named censor_date", {
  cdm <- omock::mockCdmFromTables(tables = list(
    cohort = dplyr::tibble(
      cohort_definition_id = c(1L, 2L, 1L, 2L, 1L, 1L),
      subject_id = c(1L, 1L, 2L, 2L, 3L, 4L),
      cohort_start_date = as.Date("2020-01-01") + c(0L, 10L, 0L, 10L, 0L, 0L),
      cohort_end_date = cohort_start_date,
      censor_date = as.Date("2020-01-01") + c(5L, 5L, 10L, 10L, 15L, NA_integer_)
    ),
    observation_period = dplyr::tibble(
      observation_period_id = 1:4,
      person_id = 1:4,
      observation_period_start_date = as.Date("2020-01-01"),
      observation_period_end_date = as.Date("2020-01-31"),
      period_type_concept_id = 0L
    )
  )) |>
    copyCdm()
  on.exit(dropCreatedTables(cdm), add = TRUE)

  cdm$cohort <- cdm$cohort |>
    CohortConstructor::renameCohort(c("treated", "death"))
  trans <- transMat(
    x = list(c(2), c()),
    names = c("treated", "death")
  )

  expect_no_warning(
    expect_message(
      msdata <- prepareMultistateData(
        cohort = cdm$cohort,
        trans = trans,
        censorDate = "censor_date"
      ),
      "1 record excluded: event occurred after censor date"
    )
  )

  msdata <- msdata |>
    dplyr::arrange(.data$subject_id)
  expect_s3_class(msdata, "msdata")
  expect_identical(attr(msdata, "trans"), trans)
  expect_equal(msdata$subject_id, 1:4)
  expect_equal(msdata$Tstart, rep(0, 4))
  expect_equal(msdata$Tstop, c(5, 10, 15, 30))
  expect_equal(msdata$status, c(0, 1, 0, 0))
})

test_that("excluding all subjects with no follow-up returns empty multistate data", {
  cdm <- omock::mockCdmFromTables(tables = list(
    cohort = dplyr::tibble(
      cohort_definition_id = 1:2,
      subject_id = 1L,
      cohort_start_date = as.Date("2020-01-01"),
      cohort_end_date = cohort_start_date
    ),
    observation_period = dplyr::tibble(
      observation_period_id = 1L,
      person_id = 1L,
      observation_period_start_date = as.Date("2020-01-01"),
      observation_period_end_date = as.Date("2020-01-01"),
      period_type_concept_id = 0L
    )
  )) |>
    copyCdm()
  on.exit(dropCreatedTables(cdm), add = TRUE)

  cdm$cohort <- CohortConstructor::renameCohort(cdm$cohort, c("treated", "death"))
  trans <- transMat(x = list(c(2), c()), names = c("treated", "death"))

  # A hierarchy must not create follow-up by shifting the same-day death.
  for (hierarchy in list(character(), c("treated", "death"))) {
    expect_no_warning(
      expect_message(
        msdata <- prepareMultistateData(cdm$cohort, trans, stateHierarchy = hierarchy),
        "2 records excluded: subject has no follow-up after index date"
      )
    )
    expect_s3_class(msdata, "msdata")
    expect_identical(attr(msdata, "trans"), trans)
    expect_equal(nrow(msdata), 0L)
    expect_named(
      msdata,
      c("subject_id", "from", "to", "trans", "Tstart", "Tstop", "status",
        "from_name", "to_name")
    )
  }

  expect_no_warning(
    expect_message(
      result <- summariseMultistateProbabilities(cdm$cohort, trans),
      "2 records excluded: subject has no follow-up after index date"
    )
  )
  expect_equal(nrow(result), 0L)
  expect_equal(nrow(attr(result, "ms_data")), 0L)
})

test_that("preparation helpers report and reject conflicting states", {
  expect_invisible(reportIndividuals(0, "test reason"))
  expect_message(
    reportIndividuals(2, "test reason"),
    "2 records excluded"
  )

  oneState <- dplyr::tibble(subject_id = c(1L, 2L), state = c("a", "b"))
  conflicting <- dplyr::tibble(subject_id = 1L, state = c("a", "b"))

  expect_invisible(checkMultiple(oneState))
  expect_error(checkMultiple(conflicting), "multiple initial states")
  expect_error(
    checkMultiple(conflicting, iteration = 2L),
    "multiple states after transition 2"
  )
})

test_that("events on the censor date are retained", {
  cdm <- omock::mockCdmFromTables(tables = list(
    cohort = dplyr::tibble(
      cohort_definition_id = c(1L, 2L, 3L, 3L),
      subject_id = c(1L, 1L, 1L, 2L),
      cohort_start_date = as.Date("2020-01-01") + c(0L, 10L, 10L, 5L),
      cohort_end_date = cohort_start_date,
      custom_censor_date = as.Date("2020-01-01") + 10L
    )
  )) |>
    copyCdm()
  on.exit(dropCreatedTables(cdm), add = TRUE)

  cdm$cohort <- cdm$cohort |>
    CohortConstructor::renameCohort(c("treated", "untreated", "death"))
  trans <- transMat(
    x = list(c(2, 3), c(1, 3), c()),
    names = c("treated", "untreated", "death")
  )

  expect_no_warning(
    expect_message(
      msdata <- prepareMultistateData(
        cohort = cdm$cohort,
        trans = trans,
        censorDate = "custom_censor_date",
        stateHierarchy = c("treated", "untreated", "death")
      ),
      "1 record excluded: subject has no eligible initial state"
    )
  )
  transition <- msdata |>
    dplyr::filter(.data$subject_id == 1L, .data$status == 1) |>
    dplyr::arrange(.data$Tstop)
  expect_equal(transition$to_name, c("untreated", "death"))
  expect_equal(transition$Tstop, c(10, 10.01))
  expect_true(all(msdata$Tstop > msdata$Tstart))
})
