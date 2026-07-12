
#' Title
#'
#' @param cohort
#' @param tmat
#' @param eventDate
#' @param censorDate
#' @param stateHierarchy
#' @param stateStep
#' @param keepExtraColumns
#'
#' @returns
#' @export
#'
#' @examples
prepareMultiStateData <- function(cohort,
                                  tmat,
                                  eventDate = "cohort_start_date",
                                  censorDate = NULL,
                                  stateHierarchy = character(),
                                  stateStep = 0.01,
                                  keepExtraColumns = TRUE) {
  # initial validations
  cohort <- omopgenerics::validateCohortArgument(cohort)
  name <- omopgenerics::validateNameArgument(name = name, cdm = cdm, null = TRUE)
  omopgenerics::validateColumn(eventDate, cohort, type = "date")
  omopgenerics::validateColumn(censorDate, cohort, type = "date", null = TRUE)
  omopgenerics::assertLogical(keepExtraColumns)

  cdm <- omopgenerics::cdmReference(cohort)

  # get transitions
  transitions <- tmat |>
    as.data.frame() |>
    tibble::rownames_to_column("from") |>
    tidyr::pivot_longer(!"from", names_to = "to", values_to = "trans") |>
    dplyr::filter(!is.na(.data$trans))

  # get not final states
  initialStates <- unique(transitions$from)

  # states
  states <- unique(c(initialStates, unique(transitions$to)))

  # check names
  set <- omopgenerics::settings(cohort)
  notPresent <- states[!states %in% set$cohort_name]
  if (length(notPresent) > 0) {
    cli::cli_abort(c(x = "The following states are not identified in the cohort: {.var {notPresent}}."))
  }

  # check states hierarchy
  omopgenerics::assertChoice(stateHierarchy, choices = states)
  omopgenerics::assertNumeric(stateStep, length = 1)
  stateHierarchy <- dplyr::tibble(
    state = stateHierarchy,
    step = stateStep * seq_along(stateHierarchy)
  ) |>
    dplyr::full_join(dplyr::tibble(state = states), by = "state") |>
    dplyr::mutate(step = dplyr::coalesce(.data$step, 0))

  # prepare censor date
  cohort <- cohort |>
    PatientProfiles::addCohortName() |>
    dplyr::filter(.data$cohort_name %in% .env$states) |>
    PatientProfiles::addFutureObservationQuery(
      futureObservationType = "date",
      futureObservationName = "censor_date"
    )
  if (!is.null(censorDate)) {
    cohort <- cohort |>
      dplyr::mutate(
        "censor_date" = dplyr::coalesce(.data[[censorDate]], .data$censor_date)
      )
  }

  # get states
  states <- cohort |>
    dplyr::select(
      "state" = "cohort_name",
      "subject_id",
      "date_event" = dplyr::all_of(indexDate),
      "censor_date"
    ) |>
    dplyr::collect()

  # initialise: each subject starts at their first state
  current <- states |>
    dplyr::filter(.data$state %in% .env$initialStates) |>
    dplyr::group_by(.data$subject_id) |>
    dplyr::filter(.data$date_event == min(.data$date_event, na.rm = TRUE)) |>
    dplyr::ungroup() |>
    dplyr::select("subject_id", "state", "date_event") |>
    computeNull(cnm)

  # check individuals with more than one initial state
  checkMultiple(current)

  # keep only records after initial state
  ns <- omopgenerics::numberRecords(states)
  states <- states |>
    dplyr::left_join(
      current |>
        dplyr::select("subject_id", "time_0" = "date_event"),
      by = "subject_id"
    ) |>
    dplyr::filter(.data$time_0 <= .data$date_event) |>
    computeNull(snm)
  nn <- omopgenerics::numberRecords(states)
  nd <- nn - ns
  if (nd > 0) {
    cli::cli_inform(c("!" = "There are {nd} states that occur before first entry and will never be reached."))
  }

  msdata <- list()
  i <- 1L

  while (omopgenerics::numberRecords(current) > 0) {

    # for each subject in current state, find the possible transitions
    possibleTransitions <- current |>
      dplyr::rename(from = "state") |>
      dplyr::inner_join(transitions, by = "from", relationship = "many-to-many")

    # find the transition that takes place
    activeTransiton <- possibleTransitions |>
      dplyr::inner_join(
        xx |>
          dplyr::select("subject_id", Tstop = "time_event", to = "state"),
        by = c("subject_id", "to")
      ) |>
      # state comes after start
      dplyr::filter(.data$Tstart < .data$Tstop) |>
      # state comes before censoring
      dplyr::filter(.data$Tstop < .data$censor_time) |>
      # subset to first transition
      dplyr::group_by(.data$subject_id) |>
      dplyr::filter(.data$Tstop == min(.data$Tstop, na.rm = TRUE)) |>
      dplyr::ungroup() |>
      dplyr::select("subject_id", "Tstop", status = "to")

    # build msdata rows for current state visits
    activeTransitons <- possibleTransitions |>
      dplyr::left_join(activeTransiton, by = "subject_id") |>
      dplyr::mutate(
        # if no transition then they are censored
        Tstop = dplyr::coalesce(.data$Tstop, .data$censor_time),
        # put status 1 to the transition that takes place
        status = dplyr::case_when(
          is.na(.data$to) ~ 0,
          .data$to == .data$status ~ 1,
          .default = 0
        )
      ) |>
      dplyr::select(
        "subject_id", "from", "to", "trans", "Tstart", "Tstop", "status",
        "censor_time"
      )

    # active states after transition
    current <- activeTransitons |>
      dplyr::filter(.data$status == 1, .data$to %in% .env$initialStates) |>
      dplyr::select("subject_id", state = "to", Tstart = "Tstop", "censor_time")

    msdata[[i]] <- activeTransitons
    i <- i + 1L
  }

  # bind all ms data
  msdata <- dplyr::bind_rows(msdata)

  # warn about not reached states
  probtrans
  attr(msres, "trans") <- trans
  class(msres) <- c("msdata", "data.frame")

  return(msdata)
}

checkMultiple <- function(states, iteration = 0) {
  multiple <- current |>
    dplyr::group_by(.data$subject_id) |>
    dplyr::summarise(
      n_state = dplyr::n_distinct(.data$state),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$n_state > 1) |>
    dplyr::tally() |>
    dplyr::pull() |>
    as.numeric()
  if (multiple > 0) {
    if (iteration == 0) {
      ini <- "initial "
      end <- ""
    } else {
      ini <- ""
      end <- paste0(" after transition ", iteration)
    }
    message <- paste0("Individuals have multiple ", ini, "states", end, ".")
    cli::cli_abort(c(x = message, i = "Individuals are not allowed to be in more than one state at the same time. Use the `stateHeriarchy`"))
  }
  invisible()
}
