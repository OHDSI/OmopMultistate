test_that("assertTrans accepts a valid transition matrix", {
  trans <- mstate::transMat(
    list(c(2, 3), c(3), c()),
    names = c("healthy", "ill", "dead")
  )

  expect_no_error(assertTrans(trans))
  expect_invisible(assertTrans(trans))
})

test_that("assertTrans requires a square named matrix", {
  trans <- matrix(
    c(NA, NA, 1, NA),
    nrow = 2,
    dimnames = list(c("a", "b"), c("a", "b"))
  )

  expect_error(assertTrans(as.data.frame(trans)), "must be a matrix")
  expect_error(assertTrans(trans[, 1, drop = FALSE]), "square matrix")

  unnamed <- trans
  dimnames(unnamed) <- NULL
  expect_error(assertTrans(unnamed), "row and column names")

  mismatched <- trans
  colnames(mismatched) <- c("b", "a")
  expect_error(assertTrans(mismatched), "must be identical")

  duplicated <- trans
  dimnames(duplicated) <- list(c("a", "a"), c("a", "a"))
  expect_error(assertTrans(duplicated), "unique row and column names")
})

test_that("assertTrans validates transition identifiers", {
  trans <- mstate::transMat(
    list(c(2, 3), c(3), c()),
    names = c("healthy", "ill", "dead")
  )

  diagonal <- trans
  diagonal[1, 1] <- 0
  expect_error(assertTrans(diagonal), "diagonal elements")

  nonNumeric <- matrix(
    c(NA, NA, "one", NA),
    nrow = 2,
    dimnames = list(c("a", "b"), c("a", "b"))
  )
  expect_error(assertTrans(nonNumeric), "numeric transition identifiers")

  empty <- matrix(
    NA_integer_,
    nrow = 2,
    ncol = 2,
    dimnames = list(c("a", "b"), c("a", "b"))
  )
  expect_error(assertTrans(empty), "at least one possible transition")

  nonInteger <- trans
  nonInteger[1, 2] <- 1.5
  expect_error(assertTrans(nonInteger), "numbered sequentially")

  nonSequential <- trans
  nonSequential[2, 3] <- 4
  expect_error(assertTrans(nonSequential), "numbered sequentially")

  duplicated <- trans
  duplicated[1, 3] <- 1
  expect_error(assertTrans(duplicated), "numbered sequentially")
})
