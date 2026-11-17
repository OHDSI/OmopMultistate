# Prepare Multi-State Data from an OMOP Cohort Table

Convert cohort-defined state entries into counting-process data for
multi-state survival models using the `survival` and `mstate` packages.

## Usage

``` r
prepareMultistateData(
  cohort,
  trans,
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
  number of transitions. Row and column names must be identical, unique
  state names in the same order. A row containing only `NA` defines an
  absorbing state. Use
  [`transMat()`](https://rdrr.io/pkg/mstate/man/transMat.html) to build
  a matrix.

- eventDate:

  Name of the date column in `cohort` that identifies when an individual
  enters a state. State entries are defined by these dates; reaching
  `cohort_end_date` does not automatically create a state change.

- censorDate:

  Name of the date column in `cohort` that identifies the end of
  follow-up, inclusive. If `NULL`, the end of each individual's
  observation period is used. Missing values in a supplied column also
  fall back to the observation period end. Supplied dates replace the
  observation-based dates; they are not automatically capped at
  observation end. Use the same date on all state records for a person
  when specifying a single follow-up endpoint.

- stateHierarchy:

  Character vector of state names in the order used to resolve states
  that occur on the same date, with earlier entries occurring first. An
  empty character vector applies no hierarchy; unresolved ties between
  competing states cause an error. Include all states that need a
  distinct order. Unlisted states share the priority of the last listed
  state.

- stateStep:

  Numeric increment used to separate states that occur on the same date
  according to `stateHierarchy`, in days. Successive priority ranks are
  shifted by multiples of this increment. The default is `0.01` days.

## Value

An `msdata` data frame with one row per possible outgoing transition for
each interval at risk. Columns include `subject_id`, integer state
identifiers `from` and `to`, transition identifier `trans`, elapsed days
`Tstart` and `Tstop`, and `status` (`1` for the observed transition, `0`
otherwise). `from_name` and `to_name` contain the state names. The
transition matrix is retained in the `trans` attribute.

## Details

Time zero is each person's earliest entry into a state with at least one
outgoing transition. People recorded only in absorbing states cannot
enter the analysis. At each step, the earliest subsequent entry
permitted by `trans` determines the next state. Repeated visits are
supported when the matrix permits returning to a previous state. Cohort
end dates alone do not create exits; provide a cohort for each
destination state.

Events on the censor date are included. After records beyond their
censor dates are removed, the latest remaining censor date for each
person is used for their trajectory. If `stateHierarchy` shifts a
same-day event beyond that date, follow-up is extended to include the
shifted event.

Informational messages report excluded records: events after censoring,
people without an eligible initial state, events before time zero, and
states that cannot be reached under `trans`. Counts refer to records,
rather than distinct people. Remaining simultaneous competing states
cause an error; use `stateHierarchy` to order them.

State records are collected into R for processing, including when
`cohort` is stored in a database.

## See also

[`summariseMultistateProbabilities()`](https://oxford-pharmacoepi.github.io/OmopMultistate/reference/summariseMultistateProbabilities.md),
[`transMat()`](https://rdrr.io/pkg/mstate/man/transMat.html)

## Examples

``` r
library(CohortConstructor)
library(dplyr)
library(omock)
library(OmopMultistate)

cdm <- mockCdmFromDataset(datasetName = "GiBleed")
#> ℹ Loading bundled GiBleed tables from package data.
#> ℹ Adding drug_strength table.
#> ℹ Creating local <cdm_reference> object.

# An illustrative concept set: aspirin 81 mg oral tablets.
# Keep the first treatment episode for each person.
cdm$treated <- conceptCohort(
  cdm = cdm,
  conceptSet = list(treated = 19059056L),
  name = "treated"
) |>
  requireIsFirstEntry()
#> ℹ Subsetting table drug_exposure using 1 concept with domain: drug.
#> ℹ Combining tables.
#> ℹ Creating cohort attributes.
#> ℹ Applying cohort requirements.
#> ℹ Merging overlapping records.
#> ✔ Cohort treated created.

# Enter the untreated state the day after treatment ends. Require that day
# to be within observation, so loss to follow-up is not a discontinuation.
cdm$untreated <- cdm$treated |>
  padCohortEnd(days = 1L, requireFullContribution = TRUE, name = "untreated") |>
  padCohortDate(
    days = 0L,
    indexDate = "cohort_end_date",
    cohortDate = "cohort_start_date"
  ) |>
  renameCohort("untreated")
cdm <- bind(cdm$treated, cdm$untreated, name = "states")

# Model first discontinuation: untreated is an absorbing state.
# Matrix state names must match the cohort names.
trans <- transMat(
  x = list(2, integer()),
  names = c("treated", "untreated")
)

# By default, follow-up ends at the end of each person's observation period.
# Resolve any same-day states by placing treatment before discontinuation.
msData <- prepareMultistateData(
  cohort = cdm$states,
  trans = trans,
  stateHierarchy = c("treated", "untreated")
)

# One row per possible transition and time interval; status = 1 is an event.
msData |>
  arrange(subject_id, Tstart) |>
  head()
#> An object of class 'msdata'
#> 
#> Data:
#>   subject_id from to trans Tstart Tstop status from_name   to_name
#> 1          1    1  2     1      0    29      1   treated untreated
#> 2          2    1  2     1      0    15      1   treated untreated
#> 3          3    1  2     1      0    22      1   treated untreated
#> 4          5    1  2     1      0    68      1   treated untreated
#> 5          6    1  2     1      0    15      1   treated untreated
#> 6          7    1  2     1      0    15      1   treated untreated

cdmDisconnect(cdm)
```
