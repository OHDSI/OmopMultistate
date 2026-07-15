
#' Prepare Multi-State Data from an OMOP Cohort Table
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
  validateTrans(trans)
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

  # get allStates
  allStates <- cohort |>
    dplyr::select(
      "state" = "cohort_name",
      "subject_id",
      "date_event" = dplyr::all_of(eventDate),
      "censor_date"
    ) |>
    dplyr::collect()

  # censored states
  n0 <- .numberRecords(allStates)
  allStates <- allStates |>
    dplyr::filter(.data$date_event <= .data$censor_date)
  nD <- n0 - .numberRecords(allStates)
  reportIndividuals(nD, "event occurred after censor date")

  # initialise: calculate time 0 for each individual
  time0 <- allStates |>
    dplyr::filter(.data$state %in% .env$initialStates) |>
    dplyr::group_by(.data$subject_id) |>
    dplyr::summarise(time_0 = min(.data$date_event, na.rm = TRUE), .groups = "drop")

  # eliminate records with no initial state
  n0 <- .numberRecords(allStates)
  allStates <- allStates |>
    dplyr::left_join(time0, by = "subject_id") |>
    dplyr::filter(!is.na(.data$time_0))
  nD <- n0 - .numberRecords(allStates)
  reportIndividuals(nD, "subject has no eligible initial state")

  # keep only records after initial state
  n0 <- .numberRecords(allStates)
  allStates <- allStates |>
    dplyr::filter(.data$time_0 <= .data$date_event)
  nD <- n0 - .numberRecords(allStates)
  reportIndividuals(nD, "event occurred before start event")

  # calculate time
  allStates <- allStates |>
    dplyr::mutate(
      Tstart = as.numeric(clock::date_count_between(.data$time_0, .data$date_event, "day")),
      time_censor = as.numeric(clock::date_count_between(.data$time_0, .data$censor_date, "day"))
    ) |>
    dplyr::select("subject_id", "state", "Tstart", "time_censor")

  # update conflicting times
  allStates <- updateTime(allStates, stateHierarchy, stateStep)

  # this is because the hierarchy may have added some time to the last state
  allStates <- allStates |>
    dplyr::group_by(.data$subject_id) |>
    dplyr::mutate(
      time_censor = max(.data$time_censor, .data$Tstart, na.rm = TRUE)
    ) |>
    dplyr::ungroup()

  # initial states
  current <- allStates |>
    dplyr::filter(.data$Tstart == 0)

  # check individuals with more than one initial state
  checkMultiple(current)

  msdata <- list()
  i <- 1L

  while (.numberRecords(current) > 0) {

    # for each subject in current state, find the possible transitions
    possibleTransitions <- current |>
      dplyr::rename(from = "state") |>
      dplyr::inner_join(transitions, by = "from", relationship = "many-to-many")

    # find the transition that takes place
    activeTransiton <- possibleTransitions |>
      dplyr::inner_join(
        allStates |>
          dplyr::select("subject_id", Tstop = "Tstart", to = "state"),
        by = c("subject_id", "to")
      ) |>
      # state comes after start
      dplyr::filter(.data$Tstart < .data$Tstop) |>
      # state comes before censoring
      dplyr::filter(.data$Tstop <= .data$time_censor) |>
      # subset to first transition
      dplyr::group_by(.data$subject_id) |>
      dplyr::slice_min(
        order_by = .data$Tstop,
        n = 1,
        with_ties = TRUE,
        na_rm = TRUE
      ) |>
      dplyr::ungroup() |>
      dplyr::select("subject_id", "Tstop", state = "to")

    # check individuals with more than one state
    checkMultiple(activeTransiton, iteration = i)

    # build msdata rows for current state visits
    activeTransitons <- possibleTransitions |>
      dplyr::left_join(activeTransiton, by = "subject_id") |>
      dplyr::mutate(
        # if no transition then they are censored
        Tstop = dplyr::coalesce(.data$Tstop, .data$time_censor),
        # put status 1 to the transition that takes place
        status = dplyr::case_when(
          is.na(.data$to) ~ 0,
          .data$to == .data$state ~ 1,
          .default = 0
        )
      ) |>
      dplyr::select(
        "subject_id", "from", "to", "trans", "Tstart", "Tstop", "status",
        "time_censor"
      )

    # active states after transition
    current <- activeTransitons |>
      dplyr::filter(
        .data$status == 1,
        .data$to %in% .env$initialStates,
        .data$Tstop < .data$time_censor
      ) |>
      dplyr::select("subject_id", state = "to", Tstart = "Tstop", "time_censor")

    msdata[[i]] <- activeTransitons |>
      dplyr::select(!"time_censor")
    i <- i + 1L
  }

  # bind all ms data
  msdata <- dplyr::bind_rows(msdata)

  # update from, to values
  stateId <- dplyr::tibble(state = colnames(trans)) |>
    dplyr::mutate(id = as.integer(dplyr::row_number()))
  msdata <- msdata |>
    dplyr::rename("from_name" = "from", "to_name" = "to") |>
    dplyr::inner_join(
      stateId |>
        dplyr::rename(from_name = "state", from = "id"),
      by = "from_name"
    ) |>
    dplyr::inner_join(
      stateId |>
        dplyr::rename(to_name = "state", to = "id"),
      by = "to_name"
    ) |>
    dplyr::relocate("subject_id", "from", "to", "trans", "Tstart", "Tstop", "status")

  # warn about not reached states
  notReached <- allStates |>
    dplyr::anti_join(
      msdata |>
        dplyr::select("subject_id", "state" = "from_name", "Tstart") |>
        dplyr::distinct(),
      by = c("subject_id", "state", "Tstart")
    ) |>
    dplyr::anti_join(
      msdata |>
        dplyr::filter(.data$status == 1) |>
        dplyr::select("subject_id", "state" = "to_name", "Tstart" = "Tstop"),
      by = c("subject_id", "state", "Tstart")
    ) |>
    .numberRecords()
  reportIndividuals(notReached, "state is not reachable under the transition matrix")

  attr(msdata, "trans") <- trans
  class(msdata) <- c("msdata", "data.frame")

  return(msdata)
}
reportIndividuals <- function(n, reason) {
  if (n > 0) {
    cli::cli_inform(c("i" = "{.strong {n}} record{?s} excluded: {.emph {reason}}."))
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
    cli::cli_abort(c(x = message, i = "Individuals are not allowed to be in more than one state at the same time. Use `stateHierarchy` to resolve ties."))
  }
  invisible()
}
updateTime <- function(states, stateHierarchy, stateStep) {
  states |>
    dplyr::inner_join(stateHierarchy, by = "state") |>
    dplyr::group_by(.data$subject_id, .data$Tstart) |>
    dplyr::mutate(Tstart = .data$Tstart + .env$stateStep * (dplyr::dense_rank(.data$id) - 1)) |>
    dplyr::ungroup() |>
    dplyr::select(!"id")
}
.numberRecords <- function(x) {
  x |>
    dplyr::ungroup() |>
    dplyr::tally() |>
    dplyr::pull() |>
    as.integer()
}
