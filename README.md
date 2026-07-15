
<!-- README.md is generated from README.Rmd. Please edit that file -->

# OmopMultistate <img src="man/figures/logo.png" align="right" height="126" alt="" />

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/oxford-pharmacoepi/OmopMultistate/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/oxford-pharmacoepi/OmopMultistate/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/oxford-pharmacoepi/OmopMultistate/graph/badge.svg)](https://app.codecov.io/gh/oxford-pharmacoepi/OmopMultistate)
<!-- badges: end -->

**OmopMultistate** estimates how individuals move between clinically
meaningful states over time using cohort records from the OMOP Common
Data Model. Each state is represented by a cohort definition, while a
transition matrix declares which movements between states are possible.

The package provides a workflow to:

- prepare an OMOP `cohort_table` in the long format used by
  [mstate](https://hputter.github.io/mstate/);
- estimate state occupation probabilities overall or for specific
  initial states;
- repeat the analysis across user-defined strata; and
- return results as a standard `summarised_result` object and visualise
  them over time.

## Ecosystem

*OmopMultistate* is part of the ecosystem of packages defined by
[omopgenerics](https://darwin-eu.github.io/omopgenerics/). For more
details on the ecosystem you can read the [Tidy R programming with the
OMOP Common Data
Model](https://ohdsi.github.io/Tidy-R-programming-with-OMOP/) book.

## Tested sources

| Source | Driver | CDM reference | Status |
|----|----|----|----|
| Local R data frame | N/A | `omopgenerics::cdmFromTables()` | ![](https://img.shields.io/github/actions/workflow/status/oxford-pharmacoepi/OmopMultistate/test-weekly.yaml?branch=main&job=local-omopgenerics) |
| In-memory DuckDB database | duckdb | `CDMConnector::cdmFromCon()` | ![](https://img.shields.io/github/actions/workflow/status/oxford-pharmacoepi/OmopMultistate/test-weekly.yaml?branch=main&job=duckdb-CDMConnector) |

## Installation

You can install the development version of OmopMultistate from
[GitHub](https://github.com/) with:

``` r
# install.packages("pak")
pak::pak("oxford-pharmacoepi/OmopMultistate")
```

## Example

The following example uses a small mock OMOP CDM containing three
states: `treated`, `untreated`, and the absorbing state `death`.

``` r
library(OmopMultistate)
library(omock)

cdm <- mockCdmFromDataset(datasetName = "synpuf-1k", source = "duckdb")
```

First we will do the simplest possible case, we analyse discontinuation
of **acetaminophen**. So we will create 3 cohorts: acetaminophen,
discontinuation of acetaminophen (untreated) and death. We will use
[CohortConstructor]() to create the cohorts.

``` r
library(CohortConstructor)
#> Warning: package 'CohortConstructor' was built under R version 4.4.3
library(CodelistGenerator)
#> Warning: package 'CodelistGenerator' was built under R version 4.4.3

codes <- getDrugIngredientCodes(cdm = cdm, name = "acetaminophen", nameStyle = "{concept_name}")

# acetaminophen cohort
cdm$acetaminophen <- conceptCohort(cdm = cdm, conceptSet = codes, name = "acetaminophen")
#> ℹ Subsetting table drug_exposure using 6620 concepts with domain: drug.
#> ℹ Combining tables.
#> ℹ Creating cohort attributes.
#> ℹ Applying cohort requirements.
#> ℹ Merging overlapping records.
#> ✔ Cohort acetaminophen created.

# death cohort
cdm$death_cohort <- deathCohort(cdm = cdm, name = "death_cohort")
#> ℹ Applying cohort requirements.
#> ✔ Cohort death_cohort created.

# untreated cohort
cdm$untreated <- cdm$acetaminophen |>
  padCohortEnd(days = 1L, name = "untreated") |>
  padCohortDate(days = 0L, indexDate = "cohort_end_date", cohortDate = "cohort_start_date") |>
  renameCohort("untreated")

# bind them together
cdm <- bind(cdm$acetaminophen, cdm$death_cohort, cdm$untreated, name = "my_study")
```

Now we will focus on defining the transitions, the individuals can move
from:

- `acetaminophen` to `untreated`
- `acetaminophen` to `death_cohort`
- `untreated` to `acetaminophen`
- `untreated` to `death_cohort`

``` r
trans <- transMat(
  x = list(c(2, 3), c(1, 3), c()),
  names = c("acetaminophen", "untreated", "death_cohort")
)

trans
#>                to
#> from            acetaminophen untreated death_cohort
#>   acetaminophen            NA         1            2
#>   untreated                 3        NA            4
#>   death_cohort             NA        NA           NA
```

You can fit prepare the data in long format (same than [mstate]()) so
latter you can fit any other model:

``` r
msData <- prepareMultistateData(cohort = cdm$my_study, trans = trans)
#> ℹ 26 records not reached due to `event occurred before start event`.
#> Warning: There was 1 warning in `dplyr::filter()`.
#> ℹ In argument: `.data$Tstop == min(.data$Tstop, na.rm = TRUE)`.
#> Caused by warning in `min()`:
#> ! no non-missing arguments to min; returning Inf
#> ℹ 45 records not reached due to `transition not allowed`.

msData |>
  head(10)
#> An object of class 'msdata'
#> 
#> Data:
#>    subject_id from to trans Tstart Tstop status     from_name      to_name
#> 1           2    1  2     1      0    60      1 acetaminophen    untreated
#> 2           2    1  3     2      0    60      0 acetaminophen death_cohort
#> 3           6    1  2     1      0    33      1 acetaminophen    untreated
#> 4           6    1  3     2      0    33      0 acetaminophen death_cohort
#> 5          16    1  2     1      0    30      1 acetaminophen    untreated
#> 6          16    1  3     2      0    30      0 acetaminophen death_cohort
#> 7          32    1  2     1      0    30      1 acetaminophen    untreated
#> 8          32    1  3     2      0    30      0 acetaminophen death_cohort
#> 9          40    1  2     1      0    30      1 acetaminophen    untreated
#> 10         40    1  3     2      0    30      0 acetaminophen death_cohort
```

If we are interested in summarising the probabilities over time we can
use the `summariseMultistateProbabilities` function:

``` r
result <- summariseMultistateProbabilities(cohort = cdm$my_study, trans = trans)
#> ℹ 26 records not reached due to `event occurred before start event`.
#> Warning: There was 1 warning in `dplyr::filter()`.
#> ℹ In argument: `.data$Tstop == min(.data$Tstop, na.rm = TRUE)`.
#> Caused by warning in `min()`:
#> ! no non-missing arguments to min; returning Inf
#> ℹ 45 records not reached due to `transition not allowed`.
```

``` r
tidy(result)
#> # A tibble: 9,384 × 9
#>    cdm_name  initial_state variable_name      variable_level probability
#>    <chr>     <chr>         <chr>              <chr>                <dbl>
#>  1 synpuf-1k overall       prob_acetaminophen 0                    1    
#>  2 synpuf-1k overall       prob_death_cohort  0                    0    
#>  3 synpuf-1k overall       prob_untreated     0                    0    
#>  4 synpuf-1k overall       prob_acetaminophen 10                   0.770
#>  5 synpuf-1k overall       prob_death_cohort  10                   0    
#>  6 synpuf-1k overall       prob_untreated     10                   0.230
#>  7 synpuf-1k overall       prob_acetaminophen 12                   0.772
#>  8 synpuf-1k overall       prob_death_cohort  12                   0    
#>  9 synpuf-1k overall       prob_untreated     12                   0.228
#> 10 synpuf-1k overall       prob_acetaminophen 13                   0.774
#> # ℹ 9,374 more rows
#> # ℹ 4 more variables: cohort_table_name <chr>, follow_up_days <chr>,
#> #   state_hierarchy <chr>, state_step <chr>
```

You can visualise now the results:

``` r
result |>
  filterGroup(initial_state == "acetaminophen") |>
  plotMultistateProbabilities()
```

<img src="man/figures/README-plot-probabilities-1.png" alt="" width="100%" />
