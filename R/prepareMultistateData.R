
#' Title
#'
#' @inheritParams cohortDoc
#' @inheritParams transDoc
#' @inheritParams eventDateDoc
#' @inheritParams censorDateDoc
#' @inheritParams stateHierarchyDoc
#' @inheritParams stateStepDoc
#' @inheritParams keepExtraColumnsDoc
#'
#' @returns An `msdata` object to be used by the `mstate` package.
#'
#' @export
#'
prepareMultistateData <- function(cohort,
                                  trans,
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
  transitions <- trans |>
    as.data.frame() |>
    dplyr::mutate(from = rownames(trans)) |>
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

  # states hierarchy
  stateHierarchy <- dplyr::tibble(state = stateHierarchy) |>
    dplyr::mutate(id = dplyr::row_number()) |>
    dplyr::full_join(dplyr::tibble(state = states), by = "state")
  if (all(is.na(stateHierarchy$id))) {
    mID <- 0
  } else {
    mID <- max(stateHierarchy$id, na.rm = TRUE)
  }
  stateHierarchy <- stateHierarchy |>
    dplyr::mutate(id = dplyr::coalesce(.data$id, .env$mID))

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
      "date_event" = dplyr::all_of(eventDate),
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
    dplyr::mutate(time_event = 0)

  # update times
  current <- updateTime(current, stateHierarchy, stateStep)

  # check individuals with more than one initial state
  checkMultiple(current)

  # censored states
  n0 <- omopgenerics::numberRecords(states)
  states <- states |>
    dplyr::filter(.data$date_event <= .data$censor_date)
  nD <- n0 - omopgenerics::numberRecords(states)
  reportIndividuals(nD, "event occurred after censor date")

  # keep only records after initial state
  n0 <- omopgenerics::numberRecords(states)
  states <- states |>
    dplyr::left_join(
      current |>
        dplyr::select("subject_id", "time_0" = "date_event"),
      by = "subject_id"
    ) |>
    dplyr::filter(.data$time_0 <= .data$date_event)
  nD <- n0 - omopgenerics::numberRecords(states)
  reportIndividuals(nD, "event occurred before start event")

  # calculate time
  states <- states |>
    dplyr::mutate(
      time_event = clock::date_count_between(.data$time_0, .data$date_event),
      time_censor = clock::date_count_between(.data$time_0, .data$censor_date)
    ) |>
    dplyr::select("subject_id", "state", "time_event", "time_censor")

  # update times
  states <- updateTime(states, stateHierarchy, stateStep)

  # update current
  current <- current |>
    dplyr::select("subejct_id", "state", "time_event")

  # update event time for conflicting times
  states <- updateTime(states, stateHierarchy, stateStep)

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
        states |>
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
      dplyr::select("subject_id", "Tstop", state = "to")

    # check individuals with more than one state
    checkMultiple(activeTransiton, iteration = i)

    # build msdata rows for current state visits
    activeTransitons <- possibleTransitions |>
      dplyr::left_join(activeTransiton, by = "subject_id") |>
      dplyr::mutate(
        # if no transition then they are censored
        Tstop = dplyr::coalesce(.data$Tstop, .data$censor_time),
        # put status 1 to the transition that takes place
        status = dplyr::case_when(
          is.na(.data$to) ~ 0,
          .data$to == .data$state ~ 1,
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

  attr(msres, "trans") <- trans
  class(msres) <- c("msdata", "data.frame")

  return(msdata)
}
reportIndividuals <- function(n, reason) {
  if (n > 0) {
    cli::cli_inform(c("i" = "{.strong {n}} record{?s} won't be reached due to `{.emph {reason}}`."))
  }
}
checkMultiple <- function(states, iteration = 0) {
  multiple <- states |>
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
updateTime <- function(states, stateHierarchy, stateStep) {
  states |>
    dplyr::inner_join(stateHierarchy, by = "state") |>
    dplyr::group_by(.data$subject_id, .data$time_event) |>
    dplyr::mutate(time_event = .data$time_event + .env$stateStep * (dplyr::dense_rank(.data$id) - 1)) |>
    dplyr::ungroup() |>
    dplyr::select(!"id")
}
