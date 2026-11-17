
#' Summarise Multi-State Occupation Probabilities over time
#'
#' Prepare state transitions with [prepareMultistateData()], estimate state
#' occupation probabilities, and return a standard `summarised_result` for
#' inspection or plotting with [plotMultistateProbabilities()].
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
#' @details
#' Each model uses [survival::coxph()] with a separate baseline hazard for each
#' transition, clustering by person, and Breslow handling of tied event times.
#' [mstate::msfit()] and [mstate::probtrans()] then estimate state occupation
#' probabilities from time zero. Time zero, censoring, and exclusions follow
#' [prepareMultistateData()].
#'
#' Results are provided conditional on each initial state, together with an
#' overall estimate weighted by the observed distribution of initial states in
#' that model's population. When strata are requested, this is repeated within
#' each stratum, alongside the unstratified analysis. If fitting fails for a
#' stratum, an informational message identifies it and the underlying error;
#' that stratum contributes no probability rows.
#'
#' Time points are those returned by the fitted model, including time zero,
#' restricted to `followUpDays`. A row at exactly `followUpDays` is not
#' guaranteed. Confidence intervals are not included in the returned result.
#'
#' @returns A `summarised_result` with result type
#' `"summarise_multistate_probabilities"`. Use [tidy()] to obtain columns:
#'
#' - `initial_state`: the conditioning state, or `"overall"` for the weighted
#'   estimate;
#' - `variable_name`: `"prob_"` followed by the destination state name;
#' - `variable_level`: elapsed days since time zero, stored as character;
#' - `probability`: state occupation probability on a scale from zero to one;
#' - requested strata columns, with `"overall"` for unstratified results.
#'
#' [settings()] contains analysis settings, including the permitted transitions
#' and follow-up horizon. The `ms_data` attribute contains the prepared data
#' used for fitting, with any requested strata columns.
#'
#' @seealso [prepareMultistateData()], [plotMultistateProbabilities()],
#'   [filterGroup()], [filterStrata()]
#'
#' @export
#'
#' @examples
#' library(CohortConstructor)
#' library(dplyr)
#' library(omock)
#' library(OmopMultistate)
#'
#' cdm <- mockCdmFromDataset(datasetName = "GiBleed")
#'
#' # An illustrative concept set: aspirin 81 mg oral tablets.
#' # Keep the first treatment episode for each person.
#' cdm$treated <- conceptCohort(
#'   cdm = cdm,
#'   conceptSet = list(treated = 19059056L),
#'   name = "treated"
#' ) |>
#'   requireIsFirstEntry()
#'
#' # Enter the untreated state the day after treatment ends. Require that day
#' # to be within observation, so loss to follow-up is not a discontinuation.
#' cdm$untreated <- cdm$treated |>
#'   padCohortEnd(days = 1L, requireFullContribution = TRUE, name = "untreated") |>
#'   padCohortDate(
#'     days = 0L,
#'     indexDate = "cohort_end_date",
#'     cohortDate = "cohort_start_date"
#'   ) |>
#'   renameCohort("untreated")
#' cdm <- bind(cdm$treated, cdm$untreated, name = "states")
#'
#' # Model first discontinuation: untreated is an absorbing state.
#' # Matrix state names must match the cohort names.
#' trans <- transMat(
#'   x = list(2, integer()),
#'   names = c("treated", "untreated")
#' )
#'
#' # Estimate probabilities during the first year, overall and by initial state.
#' result <- summariseMultistateProbabilities(
#'   cohort = cdm$states,
#'   trans = trans,
#'   followUpDays = 365,
#'   stateHierarchy = c("treated", "untreated")
#' )
#' tidy(result) |>
#'   head()
#'
#' # Sex is constant within each person and can be used for stratification.
#' cdm$states <- PatientProfiles::addSex(cdm$states)
#' bySex <- summariseMultistateProbabilities(
#'   cohort = cdm$states,
#'   trans = trans,
#'   strata = list("sex"),
#'   followUpDays = 365,
#'   stateHierarchy = c("treated", "untreated")
#' )
#' bySex |>
#'   filterGroup(initial_state == "treated") |>
#'   filterStrata(sex == "Female") |>
#'   tidy() |>
#'   head()
#'
#' cdmDisconnect(cdm)
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
    stateStep = stateStep
  )

  # add strata
  strataData <- getStrataData(cohort, strata)

  # add strata
  msData <- msData |>
    dplyr::inner_join(strataData, by = "subject_id")

  # extract probabilities
  strata <- unique(c(list(character()), strata))
  result <- strata |>
    purrr::map(\(st) {
      msData |>
        dplyr::group_by(dplyr::across(dplyr::all_of(st))) |>
        dplyr::group_split() |>
        as.list() |>
        purrr::map(\(ms) {
          strataValues <- ms |>
            dplyr::select(dplyr::any_of(st)) |>
            dplyr::distinct()
          strataLabel <- if (length(st) == 0) {
            "overall"
          } else {
            paste0(st, " = ", unlist(strataValues[1, st]), collapse = ", ")
          }

          tryCatch(
            {
              start <- startingProbabilities(ms, trans)
              extractProbabilities(ms, trans, followUpDays, start) |>
                dplyr::cross_join(strataValues)
            },
            error = function(cnd) {
              cli::cli_inform(
                c(
                  i = "No probabilities were estimated for stratum {.val {strataLabel}}.",
                  i = "Underlying error: {conditionMessage(cnd)}"
                )
              )
              dplyr::bind_cols(
                dplyr::tibble(
                  variable_level = character(),
                  variable_name = character(),
                  probability = numeric(),
                  initial_state = character()
                ),
                strataValues[0, , drop = FALSE]
              )
            }
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
    ) |>
    addTransToSettings(trans = trans)

  attr(result, "ms_data") <- msData

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
  stateOrder <- paste0("prob_", states)

  # cox
  cox <- survival::coxph(
    survival::Surv(Tstart, Tstop, status) ~ survival::strata(trans) + survival::cluster(subject_id),
    data = x,
    ties = "breslow"
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
    dplyr::arrange(
      as.numeric(.data$variable_level),
      match(.data$variable_name, .env$stateOrder)
    )

  # initial state
  probInitial <- probStates |>
    dplyr::inner_join(start, by = "initial_state") |>
    dplyr::mutate(probability = .data$probability * .data$prob) |>
    dplyr::group_by(.data$variable_level, .data$variable_name) |>
    dplyr::summarise(probability = sum(.data$probability), .groups = "drop") |>
    dplyr::mutate(initial_state = NA_character_) |>
    dplyr::arrange(
      as.numeric(.data$variable_level),
      match(.data$variable_name, .env$stateOrder)
    )

  dplyr::union_all(probInitial, probStates)
}
pkgName <- function() {
  "OmopMultistate"
}
pkgVersion <- function() {
  as.character(utils::packageVersion(pkg = pkgName()))
}
getStrataData <- function(x, strata) {
  strataCols <- unique(unlist(strata))
  x <- x |>
    dplyr::select("subject_id", dplyr::all_of(strataCols)) |>
    dplyr::distinct() |>
    dplyr::collect() |>
    dplyr::mutate(dplyr::across(
      dplyr::all_of(strataCols),
      \(val) dplyr::coalesce(as.character(val), "Missing")
    ))
  strataError <- strataCols |>
    purrr::keep(\(st) {
      x |>
        dplyr::group_by(.data$subject_id) |>
        dplyr::filter(dplyr::n_distinct(.data[[st]]) > 1) |>
        dplyr::ungroup() |>
        dplyr::tally() |>
        dplyr::pull() > 0
    })
  if (length(strataError) > 0) {
    cli::cli_abort(c(x = "Multiple values of strata for {.var {strataError}}. Strata has to be unique for each subject_id."))
  }
  return(x)
}
addTransToSettings <- function(x, trans) {
  transitions <- trans |>
    as.data.frame() |>
    dplyr::mutate(from = rownames(trans)) |>
    tidyr::pivot_longer(!"from", names_to = "to", values_to = "trans") |>
    dplyr::filter(!is.na(.data$trans)) |>
    dplyr::arrange(.data$from, .data$to) |>
    purrr::pmap(\(from, to, ...) {
      paste0(from, "->", to)
    }) |>
    paste0(collapse = "; ")
  attr(x, "settings") <- attr(x, "settings") |>
    dplyr::mutate(transitions = transitions)
  return(x)
}

#' Plot Multi-State Occupation Probabilities
#'
#' Display the probabilities from [summariseMultistateProbabilities()] as
#' stacked step areas, with state occupation shown as percentages.
#'
#' @details
#' States are stacked in transition-matrix order. Varying result columns,
#' including initial states, strata, and analysis settings, create separate
#' panels. Use [filterGroup()] and [filterStrata()] before plotting to select
#' the initial states and populations to display. Keep all destination states
#' when displaying the complete probability distribution.
#'
#' Plotting requires the suggested packages `visOmopResults`, `ggplot2`, and
#' `scales`.
#'
#' @inheritParams resultDoc
#' @inheritParams styleDoc
#' @inheritParams timeScaleDoc
#'
#' @returns A `ggplot2` plot that can be customised with additional layers,
#' labels, or themes.
#'
#' @seealso [summariseMultistateProbabilities()], [filterGroup()],
#'   [filterStrata()], [visOmopResults::themeVisOmop()]
#'
#' @export
#'
#' @examples
#' library(CohortConstructor)
#' library(dplyr)
#' library(omock)
#' library(OmopMultistate)
#'
#' cdm <- mockCdmFromDataset(datasetName = "GiBleed")
#'
#' # An illustrative concept set: aspirin 81 mg oral tablets.
#' # Keep the first treatment episode for each person.
#' cdm$treated <- conceptCohort(
#'   cdm = cdm,
#'   conceptSet = list(treated = 19059056L),
#'   name = "treated"
#' ) |>
#'   requireIsFirstEntry()
#'
#' # Enter the untreated state the day after treatment ends. Require that day
#' # to be within observation, so loss to follow-up is not a discontinuation.
#' cdm$untreated <- cdm$treated |>
#'   padCohortEnd(days = 1L, requireFullContribution = TRUE, name = "untreated") |>
#'   padCohortDate(
#'     days = 0L, indexDate = "cohort_end_date", cohortDate = "cohort_start_date"
#'   ) |>
#'   renameCohort("untreated")
#' cdm <- bind(cdm$treated, cdm$untreated, name = "states")
#'
#' # Model first discontinuation: untreated is an absorbing state.
#' # Matrix state names must match the cohort names.
#' trans <- transMat(
#'   x = list(2, integer()),
#'   names = c("treated", "untreated")
#' )
#'
#' cdm$states <- PatientProfiles::addSex(cdm$states)
#' result <- summariseMultistateProbabilities(
#'   cohort = cdm$states,
#'   trans = trans,
#'   strata = list("sex"),
#'   followUpDays = 365,
#'   stateHierarchy = c("treated", "untreated")
#' )
#'
#' # Show the overall probabilities for people starting treatment.
#' result |>
#'   filterGroup(initial_state == "treated") |>
#'   filterStrata(sex == "overall") |>
#'   plotMultistateProbabilities()
#'
#' # Compare the sex strata in separate panels, with time displayed in years.
#' result |>
#'   filterGroup(initial_state == "treated") |>
#'   filterStrata(sex != "overall") |>
#'   plotMultistateProbabilities(timeScale = "years")
#'
#' cdmDisconnect(cdm)
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
      state = stringr::str_remove(.data$variable_name, "prob_"),
      state = factor(.data$state, levels = unique(.data$state))
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

  x <- stepAreaData(x, facet)

  p <- ggplot2::ggplot(
    data = x,
    mapping = ggplot2::aes(
      x = .data$time,
      ymin = .data$ymin,
      ymax = .data$ymax,
      fill = .data$state
    )
  ) +
    ggplot2::geom_ribbon()

  if (length(facet) > 0) {
    p <- p +
      ggplot2::facet_wrap(facet)
  }

  p +
    visTheme +
    ggplot2::labs(x = xLab, y = "Probability (%)", fill = "") +
    ggplot2::theme(legend.position = "top") +
    ggplot2::scale_y_continuous(labels = scales::percent)
}

stepAreaData <- function(x, facet = character()) {
  x <- x |>
    dplyr::select("state", "time", "probability", dplyr::all_of(facet)) |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(facet, "time")))) |>
    dplyr::arrange(.data$state, .by_group = TRUE) |>
    dplyr::mutate(
      ymax = cumsum(.data$probability),
      ymin = .data$ymax - .data$probability
    ) |>
    dplyr::ungroup()

  previous <- x |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(facet, "state")))) |>
    dplyr::arrange(.data$time, .by_group = TRUE) |>
    dplyr::mutate(time = dplyr::lead(.data$time)) |>
    dplyr::filter(!is.na(.data$time)) |>
    dplyr::ungroup()

  dplyr::bind_rows(
    dplyr::mutate(previous, .step = 0L),
    dplyr::mutate(x, .step = 1L)
  ) |>
    dplyr::arrange(
      dplyr::across(dplyr::all_of(c(facet, "state"))),
      .data$time,
      .data$.step
    ) |>
    dplyr::select(!".step")
}
