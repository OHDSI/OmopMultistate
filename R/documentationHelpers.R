# Argument descriptions repeated > 1:

#' Helper for consistent documentation of `trans`.
#'
#' @param trans Transition matrix describing the states and transitions in the
#' multi-state model. If S is the number of states in the multi-state model,
#' trans should be an S x S matrix, with (i,j)-element a positive integer if a
#' transition from i to j is possible in the multi-state model, NA otherwise. In
#' particular, all diagonal elements should be NA. The integers indicating the
#' possible transitions in the multi-state model should be sequentially
#' numbered, 1,...,K, with K the number of transitions. Row and column names
#' must be identical, unique state names in the same order. A row containing
#' only `NA` defines an absorbing state. Use [transMat()] to build a matrix.
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
#' individual enters a state. State entries are defined by these dates;
#' reaching `cohort_end_date` does not automatically create a state change.
#'
#' @name eventDateDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `censorDate`.
#'
#' @param censorDate Name of the date column in `cohort` that identifies the end
#' of follow-up, inclusive. If `NULL`, the end of each individual's observation
#' period is used. Missing values in a supplied column also fall back to the
#' observation period end. Supplied dates replace the observation-based dates;
#' they are not automatically capped at observation end. Use the same date on
#' all state records for a person when specifying a single follow-up endpoint.
#' Individuals with no follow-up after their index date are excluded from the
#' analysis.
#'
#' @name censorDateDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `stateHierarchy`.
#'
#' @param stateHierarchy Character vector of state names in the order used to
#' resolve states that occur on the same date, with earlier entries occurring
#' first. An empty character vector applies no hierarchy; unresolved ties
#' between competing states cause an error. Include all states that need a
#' distinct order. Unlisted states share the priority of the last listed state.
#'
#' @name stateHierarchyDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `stateStep`.
#'
#' @param stateStep Numeric increment used to separate states that occur on the
#' same date according to `stateHierarchy`, in days. Must be finite and strictly
#' positive. Successive priority ranks are shifted by multiples of this
#' increment. The default is `0.01` days.
#'
#' @name stateStepDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `strata`.
#'
#' @param strata List of character vectors defining stratifications. Each
#' character vector identifies one or more columns in `cohort`; a separate model
#' is fitted for each combination of values. For example,
#' `list("sex", c("sex", "age_group"))` requests models by sex and by sex and
#' age group jointly. An unstratified model is always included. Each column
#' must be constant within a person across all cohort records. Missing values
#' are labelled `"Missing"`.
#'
#' @name strataDoc
#' @keywords internal
NULL

#' Helper for consistent documentation of `followUpDays`.
#'
#' @param followUpDays Non-negative maximum number of days of follow-up for
#' which to estimate state occupation probabilities. Use `Inf` to include all available
#' follow-up. This limits the time points returned after model fitting; it
#' does not censor the input data or refit the model at this horizon.
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
#' either `"days"` or `"years"`. Years are calculated as days divided by
#' `365.25`; this changes only the plot axis.
#'
#' @name timeScaleDoc
#' @keywords internal
NULL
