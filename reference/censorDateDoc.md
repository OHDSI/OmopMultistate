# Helper for consistent documentation of `censorDate`.

Helper for consistent documentation of `censorDate`.

## Arguments

- censorDate:

  Name of the date column in `cohort` that identifies the end of
  follow-up, inclusive. If `NULL`, the end of each individual's
  observation period is used. Missing values in a supplied column also
  fall back to the observation period end. Supplied dates replace the
  observation-based dates; they are not automatically capped at
  observation end. Use the same date on all state records for a person
  when specifying a single follow-up endpoint. Individuals with no
  follow-up after their index date are excluded from the analysis.
