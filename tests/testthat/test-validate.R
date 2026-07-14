test_that("validateTrans behaviour", {
  # validateTrans accepts a valid transition matrix
  trans <- mstate::transMat(
    list(c(2, 3), c(3), c()),
    names = c("healthy", "ill", "dead")
  )

  expect_no_error(validateTrans(trans))
  expect_invisible(validateTrans(trans))

  # validateTrans requires a square named matrix
  trans <- matrix(
    c(NA, NA, 1, NA),
    nrow = 2,
    dimnames = list(c("a", "b"), c("a", "b"))
  )

  expect_error(validateTrans(as.data.frame(trans)), "must be a matrix")
  expect_error(validateTrans(trans[, 1, drop = FALSE]), "square matrix")

  unnamed <- trans
  dimnames(unnamed) <- NULL
  expect_error(validateTrans(unnamed), "row and column names")

  mismatched <- trans
  colnames(mismatched) <- c("b", "a")
  expect_error(validateTrans(mismatched), "must be identical")

  duplicated <- trans
  dimnames(duplicated) <- list(c("a", "a"), c("a", "a"))
  expect_error(validateTrans(duplicated), "unique row and column names")

  # validateTrans validates transition identifiers
  trans <- mstate::transMat(
    list(c(2, 3), c(3), c()),
    names = c("healthy", "ill", "dead")
  )

  diagonal <- trans
  diagonal[1, 1] <- 0
  expect_error(validateTrans(diagonal), "diagonal elements")

  nonNumeric <- matrix(
    c(NA, NA, "one", NA),
    nrow = 2,
    dimnames = list(c("a", "b"), c("a", "b"))
  )
  expect_error(validateTrans(nonNumeric), "numeric transition identifiers")

  empty <- matrix(
    NA_integer_,
    nrow = 2,
    ncol = 2,
    dimnames = list(c("a", "b"), c("a", "b"))
  )
  expect_error(validateTrans(empty), "at least one possible transition")

  nonInteger <- trans
  nonInteger[1, 2] <- 1.5
  expect_error(validateTrans(nonInteger), "numbered sequentially")

  nonSequential <- trans
  nonSequential[2, 3] <- 4
  expect_error(validateTrans(nonSequential), "numbered sequentially")

  duplicated <- trans
  duplicated[1, 3] <- 1
  expect_error(validateTrans(duplicated), "numbered sequentially")
})
