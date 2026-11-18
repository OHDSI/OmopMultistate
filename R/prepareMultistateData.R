
#' Prepare Multi-State Data from an OMOP Cohort Table
#'
#' Convert cohort-defined state entries into counting-process data for
#' multi-state survival models using the `survival` and `mstate` packages.
#'
#' @inheritParams cohortDoc
#' @inheritParams transDoc
#' @inheritParams eventDateDoc
#' @inheritParams censorDateDoc
#' @inheritParams stateHierarchyDoc
#' @inheritParams stateStepDoc
#'
#' @details
#' Time zero is each person's earliest entry into a state with at least one
#' outgoing transition. People recorded only in absorbing states cannot enter
#' the analysis. At each step, the earliest subsequent entry permitted by
#' `trans` determines the next state. Repeated visits are supported when the
#' matrix permits returning to a previous state. Cohort end dates alone do not
#' create exits; provide a cohort for each destination state.
#'
#' Events on the censor date are included. After records beyond their censor
#' dates are removed, the latest remaining censor date for each person is used
#' for their trajectory. People with no follow-up after time zero are excluded
#' before applying `stateHierarchy`. If the hierarchy shifts a same-day event
#' beyond the censor date, follow-up is extended to include the shifted event.
#'
#' Informational messages report excluded records: events after censoring,
#' people without an eligible initial state, events before time zero,
#' people with no follow-up after time zero, and states that cannot be reached
#' under `trans`. Counts refer to records,
#' rather than distinct people. Remaining simultaneous competing states cause
#' an error; use `stateHierarchy` to order them.
#'
#' State records are collected into R for processing, including when `cohort`
#' is stored in a database.
#'
#' @returns An `msdata` data frame with one row per possible outgoing transition
#' for each interval at risk. Columns include `subject_id`, integer state
#' identifiers `from` and `to`, transition identifier `trans`, elapsed days
#' `Tstart` and `Tstop`, and `status` (`1` for the observed transition, `0`
#' otherwise). `from_name` and `to_name` contain the state names. The transition
#' matrix is retained in the `trans` attribute.
#'
#' @seealso [summariseMultistateProbabilities()], [transMat()]
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
#' # By default, follow-up ends at the end of each person's observation period.
#' # Resolve any same-day states by placing treatment before discontinuation.
#' msData <- prepareMultistateData(
#'   cohort = cdm$states,
#'   trans = trans,
#'   stateHierarchy = c("treated", "untreated")
#' )
#'
#' # One row per possible transition and time interval; status = 1 is an event.
#' msData |>
#'   arrange(subject_id, Tstart) |>
#'   head()
#'
#' cdmDisconnect(cdm)
#'
prepareMultistateData <- function(cohort,
                                  trans,
                                  eventDate = "cohort_start_date",
                                  censorDate = NULL,
                                  stateHierarchy = character(),
                                  stateStep = 0.01) {
  # initial validations
  cohort <- omopgenerics::validateCohortArgument(cohort)
  validateTrans(trans)
  omopgenerics::validateColumn(eventDate, cohort, type = "date")
  omopgenerics::validateColumn(censorDate, cohort, type = "date", null = TRUE)

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
  omopgenerics::assertChoice(stateHierarchy, choices = states, unique = TRUE)
  omopgenerics::assertNumeric(stateStep, length = 1, min = 0)
  if (stateStep == 0) {
    cli::cli_abort("{.arg stateStep} must be strictly positive.")
  }

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
  id <- omopgenerics::uniqueId(exclude = colnames(cohort))
  cohort <- cohort |>
    PatientProfiles::addCohortName() |>
    dplyr::filter(.data$cohort_name %in% .env$states) |>
    PatientProfiles::addFutureObservationQuery(
      futureObservationType = "date",
      futureObservationName = id
    )
  if (!is.null(censorDate)) {
    cohort <- cohort |>
      dplyr::mutate(
        !!id := dplyr::coalesce(.data[[censorDate]], .data[[id]])
      )
  }

  # get allStates
  allStates <- cohort |>
    dplyr::select(
      "state" = "cohort_name",
      "subject_id",
      "date_event" = dplyr::all_of(eventDate),
      "censor_date" = dplyr::all_of(id)
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

  # Exclude whole subjects before the hierarchy can shift same-day events.
  n0 <- .numberRecords(allStates)
  allStates <- allStates |>
    dplyr::group_by(.data$subject_id) |>
    dplyr::filter(any(.data$censor_date > .data$time_0)) |>
    dplyr::ungroup()
  nD <- n0 - .numberRecords(allStates)
  reportIndividuals(nD, "subject has no follow-up after index date")

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
      time_censor = max(.data$time_censor, .data$Tstart, 0, na.rm = TRUE)
    ) |>
    dplyr::ungroup()

  # initial states
  current <- allStates |>
    dplyr::filter(.data$Tstart == 0)

  # check individuals with more than one initial state
  checkMultiple(current)

  msdata <- list(dplyr::tibble(
    subject_id = allStates$subject_id[0],
    from = character(),
    to = character(),
    trans = transitions$trans[0],
    Tstart = numeric(),
    Tstop = numeric(),
    status = numeric()
  ))
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
