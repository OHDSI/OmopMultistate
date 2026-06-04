
#' Title
#'
#' @param cohortNames
#' @param transitions
#'
#' @returns
#' @export
#'
#' @examples
#' library(OmopMultistate)
#'
#' transitionMatrix(cohortNames = c("treated", "untreated", "dead"))
#'
#' transitionMatrix(
#'   cohortNames = c("treated", "untreated", "dead"),
#'   transitions = list(
#'     c("treated", "untreated"), c("untreated", "treated"),
#'     c("treated", "dead"), c("untreated", "dead")
#'   )
#' )
#'
#' transitionMatrix(
#'   cohortNames = c("treated", "untreated", "dead"),
#'   transitions = list(c(1, 2), c(2, 1), c(1, 3), c(2, 3))
#' )
#'
#' transitionMatrix(
#'   transitions = list(
#'     c("treated", "untreated"), c("untreated", "treated"),
#'     c("treated", "dead"), c("untreated", "dead")
#'   )
#' )
#'
transitionMatrix <- function(cohortNames = NULL,
                             transitions = list()) {
  # check inputs
  omopgenerics::assertCharacter(cohortNames, unique = TRUE, null = TRUE)
  omopgenerics::assertList(transitions)

  nms <- unique(unlist(transitions))

  # states
  if (is.null(cohortNames)) {
    if (is.character(nms)) {
      cohortNames <- nms
    } else if (is.numeric(nms)) {
      cohortNames <- paste0("state ", seq_len(max(nms)))
    }
  }

  # check incorrect transitions
  if (is.numeric(nms)) {
    if (max(nms) > length(cohortNames)) {
      cli::cli_abort(c(x = "There are ids not defined in cohortNames."))
    }
  } else if (is.character(nms)) {
    notPresent <- nms[!nms %in% cohortNames]
    if (length(notPresent) > 0) {
      cli::cli_abort(c(x = "Some names are not provided, but appear in transitions."))
    }
  } else if (length(nms) > 0) {
    cli::cli_abort(c(x = "Transitions should be provided as numbers or names, please see examples."))
  }

  # correct transitions names
  transitions <- transitions |>
    purrr::map(\(x) {
      if (is.character(x)) {
        x <- c(which(cohortNames == x[1]), which(cohortNames == x[2]))
      }
      x
    })

  n <- length(cohortNames)
  m <- matrix(rep(NA_real_, n * n), nrow = n, ncol = n)

  # transition identifier
  for (i in seq_along(transitions)) {
    m[transitions[[i]][1], transitions[[i]][1]] <- i
  }

  # add names
  namesList <- list(from = cohortNames, to = cohortNames)
  dimnames(m) <- namesList

  m
}
