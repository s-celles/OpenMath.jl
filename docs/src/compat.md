# Versioning and compatibility

This package follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and is in its `0.x` series, where the rules are the ones SemVer actually
specifies for `0.x` rather than the ones people assume.

## What is public

**The public API is exactly what `OpenMath` exports.** `names(OpenMath)` is the
list, and it is not a summary of the list — it *is* the list.

```jldoctest
julia> using OpenMath

julia> length(names(OpenMath)) > 70
true
```

Everything else is internal, including everything reachable as
`OpenMath.something` that is not exported. That is not a discouragement, it is a
statement of what this package will and will not keep still: an internal name may
be renamed, change signature, or disappear in any release, with no entry in the
changelog. Several are documented, because a reader following a design note
needs to know what they do — `OpenMath.sniff_format`, `OpenMath.scan_json`,
`OpenMath.appendix_f_operators` and the rest. Being documented does not make
them public.

If you depend on an internal name, say so in an issue. Moving it into the public
API is usually easy, and is much easier than discovering the dependency after
the fact.

Every exported symbol carries a **runnable example**, checked on every
documentation build, and a test asserts that this remains true. A docstring is a
claim; a doctest is a claim the build checks.

## What may change, and when

While the series is `0.x`, **a minor version may break anything**. That is
SemVer's rule for `0.x`, not a liberty taken here, and Julia's `Pkg` implements
it: a `[compat]` entry of `"0.4"` admits `0.4.7` and refuses `0.5.0`.

| | may change | examples |
|:--|:--|:--|
| **patch** — `0.4.1 → 0.4.2` | nothing in the public API | a defect fixed, a message reworded, performance |
| **minor** — `0.4.7 → 0.5.0` | anything | a symbol removed, a signature changed, a default flipped |

Two things this package treats as breaking even though a case could be made
otherwise, because a reader would be surprised otherwise:

- **A change in what a document decodes to.** If a well-formed document that
  decoded to one object now decodes to another, that is breaking, even when the
  new answer is the more correct one. It has happened: `arith1#root` applied to
  one argument, `transc1#log` applied to one argument.
- **A newly rejected document.** Tightening validation so that input previously
  accepted is now refused is breaking, even when the input was always invalid.

Two that are **not** breaking, stated so the line is visible:

- **The text of an error message.** Messages are written to be read by people and
  are improved often. Match on the exception *type*, never on its text.
- **The byte-for-byte output of a writer**, so long as it decodes to the same
  object. The writers are deterministic and idempotent, and that is what is
  promised; whitespace and attribute order are not. If you need byte stability,
  pin an exact version.

## What would have to be true for `1.0.0`

A `1.0.0` is a promise to keep the API still for a long time, so it is worth
declaring only once there is evidence the API *can* hold still. The conditions
are written here rather than left to a mood:

1. **The API has not changed across several minor releases.** Not "we intend to
   stop changing it" — a record of not having changed it.
2. **A second implementation has been interoperated with on every encoding.**
   Three exist today: the `openmath` crate, GAP's `openmath` package and
   MathML.jl, and between them they cover all four encodings — but `just oracle`
   and `just oracle-gap` are opt-in and their results are not yet a standing
   record.
3. **The conformance report covers the harvested Content Dictionary corpus**, not
   only the 84 items in the repository. That needs the licence question of
   §6.2 settled, not just the code.
4. **At least one real dependant.** An API is a guess until somebody else has
   built against it, and this package has had none yet.

Until then, `0.x` is the honest label.

## Julia versions

Julia **1.10** (LTS) and **1.13** are both supported and both blocking in CI,
across Linux, macOS and Windows. `just verify-lts` runs the suite on 1.10
locally, which exists because the "single source of truth" once covered 1.13
only and the first CI run found three defects every local run had passed.

Dropping an LTS is a **minor** version change, announced in the changelog.
