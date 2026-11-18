# OmopMultistate: Multi-State Analyses Using the OMOP Common Data Model

Prepare cohort records from the Observational Medical Outcomes
Partnership (OMOP) Common Data Model for multi-state analyses. Define
permitted transitions between cohort-defined states, estimate state
occupation probabilities overall and across strata, and visualise the
results. Analyses use the 'survival' and 'mstate' packages and return
standard 'omopgenerics' summarised results.

## Details

Start with a cohort table containing one cohort per state and use
[`transMat()`](https://rdrr.io/pkg/mstate/man/transMat.html) to define
the permitted transitions. Prepare data for other models with
[`prepareMultistateData()`](https://ohdsi.github.io/OmopMultistate/reference/prepareMultiStateData.md),
or estimate state occupation probabilities with
[`summariseMultistateProbabilities()`](https://ohdsi.github.io/OmopMultistate/reference/summariseMultistateProbabilities.md).
Use [`tidy()`](https://generics.r-lib.org/reference/tidy.html) and
[`settings()`](https://darwin-eu.github.io/omopgenerics/reference/settings.html)
to inspect results and
[`plotMultistateProbabilities()`](https://ohdsi.github.io/OmopMultistate/reference/plotMultistateProbabilities.md)
to plot them.

## See also

Useful links:

- <https://ohdsi.github.io/OmopMultistate/>

- Report bugs at <https://github.com/OHDSI/OmopMultistate/issues>

## Author

**Maintainer**: Martí Català <marti.catalasabate@ndorms.ox.ac.uk>
([ORCID](https://orcid.org/0000-0003-3308-9905))

Authors:

- Martí Català <marti.catalasabate@ndorms.ox.ac.uk>
  ([ORCID](https://orcid.org/0000-0003-3308-9905))
