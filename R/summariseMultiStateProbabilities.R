
#' Title
#'
#' @param cohort
#' @param trans
#' @param strata A different model is fit for each stratification.
#' @param followUpDays
#' @param eventDate
#' @param censorDate
#' @param stateHierarchy
#' @param stateStep
#'
#' @returns
#' @export
#'
#' @examples
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
  if (length(strata) > 0) {
    cols <- c(
      omopgenerics::cohortColumns(table = "cohort"), eventDate, censorDate,
      unlist(strata)
    ) |>
      unique()
    cohort <- cohort |>
      dplyr::select(dplyr::all_of(cols))
  }

  # prepare the multistate data
  msData <- prepareMultistateData(
    cohort = cohort,
    trans = trans,
    eventDate = eventData,
    censorDate = censorDate,
    stateHierarchy = stateHierarchy,
    stateStep = 0.01,
    keepExtraColumns = TRUE
  )

  # get start probabilities
  start <- startingProbabilities(msData)

  # extract probabilities
  strata <- unique(c(list(character()), strata))
  result <- strata |>
    purrr::map(\(st) {
      msData |>
        dplyr::group_by(dplyr::across(dplyr::all_of(st))) |>
        dplyr::group_split() |>
        as.list() |>
        purrr::map(\(ms) {
          extractProbabilities(ms, trans, followUpDays, start) |>
            dplyr::cross_join(
              st |>
                dplyr::select(dplyr::any_of(st)) |>
                dplyr::distinct()
            )
        }) |>
        dplyr::bind_rows()
    }) |>
    dplyr::bind_rows() |>
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
      estimates = "proportion",
      settings = c(
        "result_type", "package_name", "package_version", "follow_up_days",
        "cohort_table_name", "state_hierarchy", "state_step"
      )
    )

  # format data


  return(result)
}
startingProbabilities <- function(msData) {

}
extractProbabilities <- function(x, trans, followUp, start) {
  # cox
  cox_mod <- survival::coxph(
    survival::Surv(Tstart, Tstop, status) ~ survival::strata(trans) + survival::cluster(subject_id),
    data = x
  )
  msf <- mstate::msfit(cox_mod, trans = trans)
  pt_list <- mstate::probtrans(msf, predt = 0)


}
pkgName <- function() {
  "OmopMultistate"
}
pkgVersion <- function() {
  as.character(utils::packageVersion(pkg = pkgName()))
}

#' Title
#'
#' @param result
#' @param facet
#' @param colour
#' @param style
#' @param initialState
#'
#' @returns
#' @export
#'
#' @examples
plotMultistateProbabilities <- function(result,
                                        facet = "cdm_name",
                                        colour = "state",
                                        style = NULL,
                                        initialState = NULL) {
}
