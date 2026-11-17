# Helper for consistent documentation of `followUpDays`.

Helper for consistent documentation of `followUpDays`.

## Arguments

- followUpDays:

  Maximum number of days of follow-up for which to estimate state
  occupation probabilities. Use `Inf` to include all available
  follow-up. This limits the time points returned after model fitting;
  it does not censor the input data or refit the model at this horizon.
