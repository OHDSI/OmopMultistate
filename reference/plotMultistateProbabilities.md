# Plot Multi-State Occupation Probabilities extracted by `summariseMultistateProbabilities()`

Plot Multi-State Occupation Probabilities extracted by
[`summariseMultistateProbabilities()`](https://oxford-pharmacoepi.github.io/OmopMultistate/reference/summariseMultistateProbabilities.md)

## Usage

``` r
plotMultistateProbabilities(result, style = NULL, timeScale = "days")
```

## Arguments

- result:

  A `summarised_result` object produced by
  [`summariseMultistateProbabilities()`](https://oxford-pharmacoepi.github.io/OmopMultistate/reference/summariseMultistateProbabilities.md).

- style:

  Plot style passed to
  [`visOmopResults::themeVisOmop()`](https://darwin-eu.github.io/visOmopResults/reference/themeVisOmop.html).
  It can be the name of a built-in style, a path to a YAML style file,
  or `NULL` to use the default style.

- timeScale:

  Character string specifying the time scale of the x-axis: either
  `"days"` or `"years"`.

## Value

A ggplot2 object with the visualisation of the probabilities over time.
