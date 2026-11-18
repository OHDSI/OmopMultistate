# Plot Multi-State Occupation Probabilities

Display the probabilities from
[`summariseMultistateProbabilities()`](https://ohdsi.github.io/OmopMultistate/reference/summariseMultistateProbabilities.md)
as stacked step areas, with state occupation shown as percentages.

## Usage

``` r
plotMultistateProbabilities(result, style = NULL, timeScale = "days")
```

## Arguments

- result:

  A `summarised_result` object produced by
  [`summariseMultistateProbabilities()`](https://ohdsi.github.io/OmopMultistate/reference/summariseMultistateProbabilities.md).

- style:

  Plot style passed to
  [`visOmopResults::themeVisOmop()`](https://darwin-eu.github.io/visOmopResults/reference/themeVisOmop.html).
  It can be the name of a built-in style, a path to a YAML style file,
  or `NULL` to use the default style.

- timeScale:

  Character string specifying the time scale of the x-axis: either
  `"days"` or `"years"`. Years are calculated as days divided by
  `365.25`; this changes only the plot axis.

## Value

A `ggplot2` plot that can be customised with additional layers, labels,
or themes.

## Details

States are stacked in transition-matrix order. Varying result columns,
including initial states, strata, and analysis settings, create separate
panels. Use
[`filterGroup()`](https://darwin-eu.github.io/omopgenerics/reference/filterGroup.html)
and
[`filterStrata()`](https://darwin-eu.github.io/omopgenerics/reference/filterStrata.html)
before plotting to select the initial states and populations to display.
Keep all destination states when displaying the complete probability
distribution.

Plotting requires the suggested packages `visOmopResults`, `ggplot2`,
and `scales`.

## See also

[`summariseMultistateProbabilities()`](https://ohdsi.github.io/OmopMultistate/reference/summariseMultistateProbabilities.md),
[`filterGroup()`](https://darwin-eu.github.io/omopgenerics/reference/filterGroup.html),
[`filterStrata()`](https://darwin-eu.github.io/omopgenerics/reference/filterStrata.html),
[`visOmopResults::themeVisOmop()`](https://darwin-eu.github.io/visOmopResults/reference/themeVisOmop.html)

## Examples

``` r
library(CohortConstructor)
library(dplyr)
#> 
#> Attaching package: ‘dplyr’
#> The following objects are masked from ‘package:stats’:
#> 
#>     filter, lag
#> The following objects are masked from ‘package:base’:
#> 
#>     intersect, setdiff, setequal, union
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
    days = 0L, indexDate = "cohort_end_date", cohortDate = "cohort_start_date"
  ) |>
  renameCohort("untreated")
cdm <- bind(cdm$treated, cdm$untreated, name = "states")

# Model first discontinuation: untreated is an absorbing state.
# Matrix state names must match the cohort names.
trans <- transMat(
  x = list(2, integer()),
  names = c("treated", "untreated")
)

cdm$states <- PatientProfiles::addSex(cdm$states)
result <- summariseMultistateProbabilities(
  cohort = cdm$states,
  trans = trans,
  strata = list("sex"),
  followUpDays = 365,
  stateHierarchy = c("treated", "untreated")
)
#> `cohort_table_name` eliminated from settings as all elements are NA.

# Show the overall probabilities for people starting treatment.
result |>
  filterGroup(initial_state == "treated") |>
  filterStrata(sex == "overall") |>
  plotMultistateProbabilities()


# Compare the sex strata in separate panels, with time displayed in years.
result |>
  filterGroup(initial_state == "treated") |>
  filterStrata(sex != "overall") |>
  plotMultistateProbabilities(timeScale = "years")


cdmDisconnect(cdm)
```
