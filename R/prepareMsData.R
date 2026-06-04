
prepareMsData <- function(events, tmat) {
  # get transitions
  transitions <- tmat |>
    as.data.frame() |>
    tibble::rownames_to_column("from") |>
    tidyr::pivot_longer(!"from", names_to = "to", values_to = "trans") |>
    dplyr::filter(!is.na(.data$trans))
  notFinal <- transitions |>
    dplyr::distinct(.data$from) |>
    dplyr::pull()

  # initialise: each subject starts at their first state
  current <- events |>
    dplyr::group_by(.data$subject_id) |>
    dplyr::filter(.data$time_event == min(.data$time_event, na.rm = TRUE)) |>
    dplyr::ungroup() |>
    dplyr::select("subject_id", "state", Tstart = "time_event", "censor_time")

  msdata <- list()
  i <- 1L

  while (nrow(current) > 0) {
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
      dplyr::select("subject_id", "from", "to", "trans", "Tstart", "Tstop",
                    "status", "censor_time")

    # active states after transition
    current <- activeTransitons |>
      dplyr::filter(.data$status == 1, .data$to %in% .env$notFinal) |>
      dplyr::select("subject_id", state = "to", Tstart = "Tstop", "censor_time")

    msdata[[i]] <- activeTransitons
    i <- i + 1L
  }

  dplyr::bind_rows(msdata)
}
