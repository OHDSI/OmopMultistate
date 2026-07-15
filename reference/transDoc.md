# Helper for consistent documentation of `trans`.

Helper for consistent documentation of `trans`.

## Arguments

- trans:

  Transition matrix describing the states and transitions in the
  multi-state model. If S is the number of states in the multi-state
  model, trans should be an S x S matrix, with (i,j)-element a positive
  integer if a transition from i to j is possible in the multi-state
  model, NA otherwise. In particular, all diagonal elements should be
  NA. The integers indicating the possible transitions in the
  multi-state model should be sequentially numbered, 1,...,K, with K the
  number of transitions.
