# Argument descriptions repeated > 1:

#' Helper for consistent documentation of `trans`.
#'
#' @param trans Transition matrix describing the states and transitions in the
#' multi-state model. If S is the number of states in the multi-state model,
#' trans should be an S x S matrix, with (i,j)-element a positive integer if a
#' transition from i to j is possible in the multi-state model, NA otherwise. In
#' particular, all diagonal elements should be NA. The integers indicating the
#' possible transitions in the multi-state model should be sequentially
#' numbered, 1,...,K, with K the number of transitions.
#'
#' @name transDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `cohort`.
#'
#' @param cohort A `cohort_table` object containing one cohort for each state in
#' the multi-state model. Cohort names must match the state names in `trans`.
#'
#' @name cohortDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `eventDate`.
#'
#' @param eventDate Name of the date column in `cohort` that identifies when an
#' individual enters a state.
#'
#' @name eventDateDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `censorDate`.
#'
#' @param censorDate Name of the date column in `cohort` that identifies the end
#' of follow-up, inclusive. If `NULL`, the end of each individual's observation
#' period is used.
#'
#' @name censorDateDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `stateHierarchy`.
#'
#' @param stateHierarchy Character vector of state names in the order used to
#' resolve states that occur on the same date, with earlier entries occurring
#' first. An empty character vector applies no hierarchy.
#'
#' @name stateHierarchyDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `stateStep`.
#'
#' @param stateStep Numeric increment used to separate states that occur on the
#' same date according to `stateHierarchy`.
#'
#' @name stateStepDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `strata`.
#'
#' @param strata List of character vectors defining stratifications. Each
#' character vector identifies one or more columns in `cohort`; a separate model
#' is fitted for each stratification. The value of strata can not change in each
#' individual.
#'
#' @name strataDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `followUpDays`.
#'
#' @param followUpDays Maximum number of days of follow-up for which to estimate
#' state occupation probabilities. Use `Inf` to include all available
#' follow-up.
#'
#' @name followUpDaysDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `result`.
#'
#' @param result A `summarised_result` object produced by
#' [summariseMultistateProbabilities()].
#'
#' @name resultDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `style`.
#'
#' @param style Plot style passed to [visOmopResults::themeVisOmop()]. It can be
#' the name of a built-in style, a path to a YAML style file, or `NULL` to use
#' the default style.
#'
#' @name styleDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `timeScale`.
#'
#' @param timeScale Character string specifying the time scale of the x-axis:
#' either `"days"` or `"years"`.
#'
#' @name timeScaleDoc
#' @keywords internal
NULL
