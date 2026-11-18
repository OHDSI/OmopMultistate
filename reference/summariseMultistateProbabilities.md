# Summarise Multi-State Occupation Probabilities over time

Prepare state transitions with
[`prepareMultistateData()`](https://ohdsi.github.io/OmopMultistate/reference/prepareMultiStateData.md),
estimate state occupation probabilities, and return a standard
`summarised_result` for inspection or plotting with
[`plotMultistateProbabilities()`](https://ohdsi.github.io/OmopMultistate/reference/plotMultistateProbabilities.md).

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
  number of transitions. Row and column names must be identical, unique
  state names in the same order. A row containing only `NA` defines an
  absorbing state. Use
  [`transMat()`](https://rdrr.io/pkg/mstate/man/transMat.html) to build
  a matrix.

- strata:

  List of character vectors defining stratifications. Each character
  vector identifies one or more columns in `cohort`; a separate model is
  fitted for each combination of values. For example,
  `list("sex", c("sex", "age_group"))` requests models by sex and by sex
  and age group jointly. An unstratified model is always included. Each
  column must be constant within a person across all cohort records.
  Missing values are labelled `"Missing"`.

- followUpDays:

  Non-negative maximum number of days of follow-up for which to estimate
  state occupation probabilities. Use `Inf` to include all available
  follow-up. This limits the time points returned after model fitting;
  it does not censor the input data or refit the model at this horizon.

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
  when specifying a single follow-up endpoint. Individuals with no
  follow-up after their index date are excluded from the analysis.

- stateHierarchy:

  Character vector of state names in the order used to resolve states
  that occur on the same date, with earlier entries occurring first. An
  empty character vector applies no hierarchy; unresolved ties between
  competing states cause an error. Include all states that need a
  distinct order. Unlisted states share the priority of the last listed
  state.

- stateStep:

  Numeric increment used to separate states that occur on the same date
  according to `stateHierarchy`, in days. Must be finite and strictly
  positive. Successive priority ranks are shifted by multiples of this
  increment. The default is `0.01` days.

## Value

A `summarised_result` with result type
`"summarise_multistate_probabilities"`. Use
[`tidy()`](https://generics.r-lib.org/reference/tidy.html) to obtain
columns:

- `initial_state`: the conditioning state, or `"overall"` for the
  weighted estimate;

- `variable_name`: `"prob_"` followed by the destination state name;

- `variable_level`: elapsed days since time zero, stored as character;

- `probability`: state occupation probability on a scale from zero to
  one;

- requested strata columns, with `"overall"` for unstratified results.

[`settings()`](https://darwin-eu.github.io/omopgenerics/reference/settings.html)
contains analysis settings, including the permitted transitions and
follow-up horizon. The `ms_data` attribute contains the prepared data
used for fitting, with any requested strata columns.

## Details

Each model uses
[`survival::coxph()`](https://rdrr.io/pkg/survival/man/coxph.html) with
a separate baseline hazard for each transition, clustering by person,
and Breslow handling of tied event times.
[`mstate::msfit()`](https://rdrr.io/pkg/mstate/man/msfit.html) and
[`mstate::probtrans()`](https://rdrr.io/pkg/mstate/man/probtrans.html)
then estimate state occupation probabilities from time zero. Time zero,
censoring, and exclusions follow
[`prepareMultistateData()`](https://ohdsi.github.io/OmopMultistate/reference/prepareMultiStateData.md).

Results are provided conditional on each initial state, together with an
overall estimate weighted by the observed distribution of initial states
in that model's population. When strata are requested, this is repeated
within each stratum, alongside the unstratified analysis. If fitting
fails for a stratum, an informational message identifies it and the
underlying error; that stratum contributes no probability rows.

Time points are those returned by the fitted model, including time zero,
restricted to `followUpDays`. A row at exactly `followUpDays` is not
guaranteed. Confidence intervals are not included in the returned
result.

## See also

[`prepareMultistateData()`](https://ohdsi.github.io/OmopMultistate/reference/prepareMultiStateData.md),
[`plotMultistateProbabilities()`](https://ohdsi.github.io/OmopMultistate/reference/plotMultistateProbabilities.md),
[`filterGroup()`](https://darwin-eu.github.io/omopgenerics/reference/filterGroup.html),
[`filterStrata()`](https://darwin-eu.github.io/omopgenerics/reference/filterStrata.html)

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

# Estimate probabilities during the first year, overall and by initial state.
result <- summariseMultistateProbabilities(
  cohort = cdm$states,
  trans = trans,
  followUpDays = 365,
  stateHierarchy = c("treated", "untreated")
)
tidy(result) |>
  head()
#> # A tibble: 6 × 10
#>   cdm_name initial_state variable_name  variable_level probability
#>   <chr>    <chr>         <chr>          <chr>                <dbl>
#> 1 GiBleed  overall       prob_treated   0                    1    
#> 2 GiBleed  overall       prob_untreated 0                    0    
#> 3 GiBleed  overall       prob_treated   15                   0.320
#> 4 GiBleed  overall       prob_untreated 15                   0.680
#> 5 GiBleed  overall       prob_treated   16                   0.319
#> 6 GiBleed  overall       prob_untreated 16                   0.681
#> # ℹ 5 more variables: cohort_table_name <chr>, follow_up_days <chr>,
#> #   state_hierarchy <chr>, state_step <chr>, transitions <chr>

# Sex is constant within each person and can be used for stratification.
cdm$states <- PatientProfiles::addSex(cdm$states)
bySex <- summariseMultistateProbabilities(
  cohort = cdm$states,
  trans = trans,
  strata = list("sex"),
  followUpDays = 365,
  stateHierarchy = c("treated", "untreated")
)
#> `cohort_table_name` eliminated from settings as all elements are NA.
bySex |>
  filterGroup(initial_state == "treated") |>
  filterStrata(sex == "Female") |>
  tidy() |>
  head()
#> # A tibble: 6 × 10
#>   cdm_name initial_state sex    variable_name  variable_level probability
#>   <chr>    <chr>         <chr>  <chr>          <chr>                <dbl>
#> 1 GiBleed  treated       Female prob_treated   0                    1    
#> 2 GiBleed  treated       Female prob_untreated 0                    0    
#> 3 GiBleed  treated       Female prob_treated   15                   0.305
#> 4 GiBleed  treated       Female prob_untreated 15                   0.695
#> 5 GiBleed  treated       Female prob_treated   22                   0.208
#> 6 GiBleed  treated       Female prob_untreated 22                   0.792
#> # ℹ 4 more variables: follow_up_days <chr>, state_hierarchy <chr>,
#> #   state_step <chr>, transitions <chr>

cdmDisconnect(cdm)
```
