validateTrans <- function(trans, call = rlang::caller_env()) {
  if (!is.matrix(trans)) {
    cli::cli_abort("{.arg trans} must be a matrix.", call = call)
  }

  if (nrow(trans) != ncol(trans) || nrow(trans) < 2) {
    cli::cli_abort(
      "{.arg trans} must be a square matrix with at least two states.",
      call = call
    )
  }

  from <- rownames(trans)
  to <- colnames(trans)
  validNames <- !is.null(from) &&
    !is.null(to) &&
    !anyNA(from) &&
    !anyNA(to) &&
    all(nzchar(from)) &&
    all(nzchar(to)) &&
    !anyDuplicated(from) &&
    !anyDuplicated(to)

  if (!validNames) {
    cli::cli_abort(
      "{.arg trans} must have non-missing, non-empty, unique row and column names.",
      call = call
    )
  }

  if (!identical(from, to)) {
    cli::cli_abort(
      "The row and column names of {.arg trans} must be identical and in the same order.",
      call = call
    )
  }

  if (!all(is.na(diag(trans)))) {
    cli::cli_abort(
      "All diagonal elements of {.arg trans} must be {.code NA}.",
      call = call
    )
  }

  if (!is.numeric(trans)) {
    cli::cli_abort(
      "{.arg trans} must contain only numeric transition identifiers and {.code NA}.",
      call = call
    )
  }

  transitions <- trans[!is.na(trans)]
  if (length(transitions) == 0) {
    cli::cli_abort(
      "{.arg trans} must contain at least one possible transition.",
      call = call
    )
  }

  sequential <- all(is.finite(transitions)) &&
    all(transitions > 0) &&
    all(transitions == floor(transitions)) &&
    identical(sort(as.integer(transitions)), seq_along(transitions))

  if (!sequential) {
    cli::cli_abort(
      paste0(
        "The transition identifiers in {.arg trans} must be unique, positive ",
        "integers numbered sequentially from 1."
      ),
      call = call
    )
  }

  invisible(trans)
}
