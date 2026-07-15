# Summarise Multi-State Occupation Probabilities over time

Summarise Multi-State Occupation Probabilities over time

## Usage

``` r
summariseMultistateProbabilities(
  cohort,
  trans,
  strata = list(),
  followUpDays = Inf,
  eventDate = "cohort_start_date",
  censorDate = NULL,
  stateHierarchy = character(),
  stateStep = 0.01
)
```

## Arguments

- cohort:

  A `cohort_table` object containing one cohort for each state in the
  multi-state model. Cohort names must match the state names in `trans`.

- trans:

  Transition matrix describing the states and transitions in the
  multi-state model. If S is the number of states in the multi-state
  model, trans should be an S x S matrix, with (i,j)-element a positive
  integer if a transition from i to j is possible in the multi-state
  model, NA otherwise. In particular, all diagonal elements should be
  NA. The integers indicating the possible transitions in the
  multi-state model should be sequentially numbered, 1,...,K, with K the
  number of transitions.

- strata:

  List of character vectors defining stratifications. Each character
  vector identifies one or more columns in `cohort`; a separate model is
  fitted for each stratification. The value of strata can not change in
  each individual.

- followUpDays:

  Maximum number of days of follow-up for which to estimate state
  occupation probabilities. Use `Inf` to include all available
  follow-up.

- eventDate:

  Name of the date column in `cohort` that identifies when an individual
  enters a state.

- censorDate:

  Name of the date column in `cohort` that identifies the end of
  follow-up, inclusive. If `NULL`, the end of each individual's
  observation period is used.

- stateHierarchy:

  Character vector of state names in the order used to resolve states
  that occur on the same date, with earlier entries occurring first. An
  empty character vector applies no hierarchy.

- stateStep:

  Numeric increment used to separate states that occur on the same date
  according to `stateHierarchy`.

## Value

A `<summarised_result>` object with result_type =
"summarise_multistate_probabilities" that contains the multistate
probabilities.
