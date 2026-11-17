# Helper for consistent documentation of `stateHierarchy`.

Helper for consistent documentation of `stateHierarchy`.

## Arguments

- stateHierarchy:

  Character vector of state names in the order used to resolve states
  that occur on the same date, with earlier entries occurring first. An
  empty character vector applies no hierarchy; unresolved ties between
  competing states cause an error. Include all states that need a
  distinct order. Unlisted states share the priority of the last listed
  state.
