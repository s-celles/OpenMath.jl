<!-- SPDX-License-Identifier: MIT -->

# Regression corpus

Items here are written automatically: when a property in `test/property/` is
falsified, `test/harness/regression.jl` records the shrunk counterexample and
writes it as an ordinary corpus item, with `provenance = "shrunk-counterexample"`.

That is the mechanism by which the harness compounds. The property layer explores
the space of objects; the corpus remembers the particular objects that once broke
something. A property that has been falsified once will be falsified the same way
again, but only if somebody writes it down — so nobody has to.

Two consequences follow from these being ordinary corpus items:

- they are checked by the conformance driver like any other, in every encoding,
  including ones that did not exist when the counterexample was found;
- they are covered by `corpus/MANIFEST.sha256`, so once written they cannot be
  quietly edited or deleted to make a test pass.

Nothing in here is hand-written. If you want to add a case deliberately, put it in
`corpus/standard/` with the provenance that actually describes where it came from.
