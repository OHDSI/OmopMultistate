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

  expect_no_error(
    plotMultistateProbabilities(result = res)
  )

  expect_no_error(
    plotYears <- plotMultistateProbabilities(result = res, timeScale = "years")
  )
  expect_equal(plotYears$labels$x, "Time (year)")

  dropCreatedTables(cdm)
})
