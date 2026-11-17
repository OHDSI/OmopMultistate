# Helper for consistent documentation of `strata`.

Helper for consistent documentation of `strata`.

## Arguments

- strata:

  List of character vectors defining stratifications. Each character
  vector identifies one or more columns in `cohort`; a separate model is
  fitted for each combination of values. For example,
  `list("sex", c("sex", "age_group"))` requests models by sex and by sex
  and age group jointly. An unstratified model is always included. Each
  column must be constant within a person across all cohort records.
  Missing values are labelled `"Missing"`.
