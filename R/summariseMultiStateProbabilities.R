
#' Summarise Multi-State Occupation Probabilities over time
#'
#' @inheritParams cohortDoc
#' @inheritParams transDoc
#' @inheritParams strataDoc
#' @inheritParams followUpDaysDoc
#' @inheritParams eventDateDoc
#' @inheritParams censorDateDoc
#' @inheritParams stateHierarchyDoc
#' @inheritParams stateStepDoc
#'
#' @returns A `<summarised_result>` object with result_type =
#' "summarise_multistate_probabilities" that contains the multistate
#' probabilities.
#'
#' @export
#'
summariseMultistateProbabilities <- function(cohort,
                                             trans,
                                             strata = list(),
                                             followUpDays = Inf,
                                             eventDate = "cohort_start_date",
                                             censorDate = NULL,
                                             stateHierarchy = character(),
                                             stateStep = 0.01) {
  # initial checks
  cohort <- omopgenerics::validateCohortArgument(cohort = cohort)
  strata <- omopgenerics::validateStrataArgument(strata = strata, table = cohort)
  cols <- c(
    omopgenerics::cohortColumns(table = "cohort"), eventDate, censorDate,
    unlist(strata)
  ) |>
    unique()
  cohort <- cohort |>
    dplyr::select(dplyr::all_of(cols))

  # prepare the multistate data
  msData <- prepareMultistateData(
    cohort = cohort,
    trans = trans,
    eventDate = eventDate,
    censorDate = censorDate,
    stateHierarchy = stateHierarchy,
    stateStep = stateStep,
    keepExtraColumns = TRUE
  )

  # extract probabilities
  strata <- unique(c(list(character()), strata))
  result <- strata |>
    purrr::map(\(st) {
      msData |>
        dplyr::group_by(dplyr::across(dplyr::all_of(st))) |>
        dplyr::group_split() |>
        as.list() |>
        purrr::map(\(ms) {
          start <- startingProbabilities(ms, trans)
          extractProbabilities(ms, trans, followUpDays, start) |>
            dplyr::cross_join(
              ms |>
                dplyr::select(dplyr::any_of(st)) |>
                dplyr::distinct()
            )
        }) |>
        dplyr::bind_rows()
    }) |>
    dplyr::bind_rows()

  # format data
  result <- result |>
    dplyr::mutate(
      cdm_name = omopgenerics::cdmName(cohort),
      result_type = "summarise_multistate_probabilities",
      package_name = pkgName(),
      package_version = pkgVersion(),
      follow_up_days = sprintf("%.0f", followUpDays),
      cohort_table_name = omopgenerics::tableName(cohort),
      state_hierarchy = paste0(stateHierarchy, collapse = ";"),
      state_step = as.character(stateStep)
    ) |>
    omopgenerics::transformToSummarisedResult(
      group = "initial_state",
      strata = unique(unlist(strata)),
      estimates = "probability",
      settings = c(
        "result_type", "package_name", "package_version", "follow_up_days",
        "cohort_table_name", "state_hierarchy", "state_step"
      )
    )

  return(result)
}
startingProbabilities <- function(msData, trans) {
  msData |>
    dplyr::filter(.data$Tstart == 0) |>
    dplyr::distinct(.data$subject_id, .data$from_name) |>
    dplyr::group_by(.data$from_name) |>
    dplyr::summarise(n = as.numeric(dplyr::n()), .groups = "drop") |>
    dplyr::right_join(dplyr::tibble(from_name = colnames(trans)), by = "from_name") |>
    dplyr::mutate(
      n = dplyr::coalesce(.data$n, 0),
      prob = .data$n / sum(.data$n)
    ) |>
    dplyr::select("initial_state" = "from_name", "prob")
}
extractProbabilities <- function(x, trans, followUp, start) {
  states <- colnames(trans)

  # cox
  cox <- survival::coxph(
    survival::Surv(Tstart, Tstop, status) ~ survival::strata(trans) + survival::cluster(subject_id),
    data = x
  )
  msf <- mstate::msfit(cox, trans = trans)
  probs <- mstate::probtrans(msf, predt = 0)

  # rename
  rn <- paste0("pstate", seq_along(states)) |>
    rlang::set_names(paste0("prob_", states))

  # no initial state
  probStates <- states |>
    purrr::imap(\(x, i) {
      probs[[i]] |>
        dplyr::select(variable_level = "time", dplyr::all_of(rn)) |>
        dplyr::filter(.data$variable_level <= .env$followUp) |>
        tidyr::pivot_longer(
          cols = !"variable_level",
          names_to = "variable_name",
          values_to = "probability"
        ) |>
        dplyr::mutate(initial_state = .env$x)
    }) |>
    dplyr::bind_rows() |>
    dplyr::mutate(variable_level = as.character(.data$variable_level)) |>
    dplyr::arrange(as.numeric(.data$variable_level), .data$variable_name)

  # initial state
  probInitial <- probStates |>
    dplyr::inner_join(start, by = "initial_state") |>
    dplyr::mutate(probability = .data$probability * .data$prob) |>
    dplyr::group_by(.data$variable_level, .data$variable_name) |>
    dplyr::summarise(probability = sum(.data$probability), .groups = "drop") |>
    dplyr::mutate(initial_state = NA_character_) |>
    dplyr::arrange(as.numeric(.data$variable_level), .data$variable_name)

  dplyr::union_all(probInitial, probStates)
}
pkgName <- function() {
  "OmopMultistate"
}
pkgVersion <- function() {
  as.character(utils::packageVersion(pkg = pkgName()))
}

#' Plot Multi-State Occupation Probabilities extracted by
#' `summariseMultistateProbabilities()`
#'
#' @inheritParams resultDoc
#' @inheritParams styleDoc
#' @inheritParams timeScaleDoc
#'
#' @returns A ggplot2 object with the visualisation of the probabilities over
#' time.
#'
#' @export
#'
plotMultistateProbabilities <- function(result,
                                        style = NULL,
                                        timeScale = "days") {
  rlang::check_installed(c("visOmopResults", "ggplot2", "scales"))

  # initial checks
  result <- omopgenerics::validateResultArgument(result)
  visTheme <- visOmopResults::themeVisOmop(style = style)
  omopgenerics::assertChoice(timeScale, c("days", "years"), length = 1)

  x <- result |>
    omopgenerics::tidy() |>
    dplyr::mutate(
      time = as.numeric(.data$variable_level),
      state = stringr::str_remove(.data$variable_name, "prob_")
    )

  facet <- colnames(x) |>
    purrr::keep(\(col) {
      if (col %in% c("variable_name", "variable_level", "probability", "time", "state")) {
        FALSE
      } else if (length(unique(x[[col]])) == 1) {
        FALSE
      } else {
        TRUE
      }
    })

  if (timeScale == "years") {
    x <- x |>
      dplyr::mutate(time = .data$time / 365.25)
    xLab <- "Time (year)"
  } else {
    xLab <- "Time (days)"
  }

  ggplot2::ggplot(
    data = x,
    mapping = ggplot2::aes(x = .data$time, y = .data$probability, fill = .data$state)
  ) +
    ggplot2::geom_area() +
    ggplot2::facet_wrap(facet) +
    visTheme +
    ggplot2::labs(x = xLab, y = "Probability (%)", fill = "") +
    ggplot2::theme(legend.position = "top") +
    ggplot2::scale_y_continuous(labels = scales::percent)
}
