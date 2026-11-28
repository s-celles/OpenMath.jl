# Differential testing

A test this package writes about itself can only check what its author thought
of. A *differential* test hands the same input to an independent implementation
and compares the answers, so a disagreement is evidence that one side — either
side — is wrong. This page describes the differential tests run against this
package, how to reproduce them, and what they found.

They report; they do not gate. A disagreement is a finding to triage: a defect
here, a defect there (recorded in `upstream-bugs.md` and reported upstream), or a
deliberate divergence (recorded where the decision is documented).

## The oracles

| Recipe | Compares with | On | How |
|:--|:--|:--|:--|
| `just oracle` | the Rust [`openmath` crate](https://github.com/FlexiFormal/OpenMath) | the conformance corpus | canonical forms, XML and JSON |
| `just oracle-gap` | GAP's `openmath` package | the binary encoding | decoded objects |
| `just oracle-mathml` | [MathML.jl](https://github.com/SciML/MathML.jl) | 21 hand-written pairs | structural equality of `Symbolics` expressions |
| `just oracle-numeric` | MathML.jl, and Giac as a MathML *producer* | 90 elements; the OSR rules | numeric values, below |

Each runs in an environment of its own under the gitignored `refs/`, never in the
test environment: MathML.jl pins `Symbolics` to an exact version, and the Rust
crate and Giac.jl are GPL-3.0, so they stay behind a process boundary.

## The numeric MathML oracle

Content MathML has two Julia readers: MathML.jl, which reads the non-strict
dialect straight into `Symbolics`, and this package, which reads it through MathML
4 Appendix F into OpenMath and then interprets it with the `Symbolics`
[phrasebook](design/phrasebook.md). Comparing their outputs *structurally* — as
`just oracle-mathml` does — fails on expressions that are equal but built
differently (`log(x)/log(10)` against `log10(x)`), which rules out any corpus not
written by hand. Comparing them *numerically* does not.

### Two corpora

**`elements`** — one non-strict document per Content MathML element that either
reader has a table entry for: 90 of them, from `<plus/>` to `<csymbol>`. There is
no truth here; the two readers are compared with each other, and the interesting
rows are those where one reads what the other does not.

**`osr`** — the integration rules of
[OpenSymbolicRules/Integration](https://github.com/OpenSymbolicRules/Integration)
(MIT, derived from the Rubi rules), which are published as OpenMath 2.0 JSON. The
corpus is pinned to commit `1132471` and checked against its SHA-256 on every
run, so a change upstream is an error, not a new result. Every integrand and
every antiderivative with no integral left in it is used: 1546 expressions, of
which 11 do not interpret (a domain error while building them) and 80 have no
sampled point where the truth is finite, leaving 1455 compared. Here the OpenMath object *is* the
truth, and each reader is judged against it:

```
  OSR object ──────────────────────────────▶ phrasebook ─▶ truth
      ├─▶ rendered as non-strict MathML ─┬─▶ MathML.jl ──▶ compare
      │                                  └─▶ OpenMath.jl ▶ compare
      └─▶ Giac export_mathml(_, content) ┬─▶ MathML.jl ──▶ compare
                                         └─▶ OpenMath.jl ▶ compare
```

The *rendered* route is a small renderer in the harness, one MathML element per
OpenMath symbol, which always writes `<root>` with its `<degree>`. The *Giac*
route has [Giac](https://www-fourier.univ-grenoble-alpes.fr/~parisse/giac.html),
through Giac.jl, write the MathML instead, so the documents under test come from
an implementation nobody here wrote: an `id` on every element, operator elements
included; `cn type="double"`; a cube root as `<ci type="function">NTHROOT</ci>`;
`sec(x)` rewritten as `1/cos(x)`. The two routes complement each other: Giac
writes a square root as `<root/>` without a `<degree>`, so only the rendered
route reaches the `<degree>` path.

Variables are renamed `v_<name>` before anything else, in the truth and in both
documents alike, because Giac reads `e` and `i` as constants.

### The comparison

Each expression is evaluated at three random points (seeded), every variable in
`[0.3, 1.7]`, by substituting with `Symbolics.substitute(…; fold = Val(true))`
and comparing with a relative tolerance of 1e-7. A point where the truth is not a
finite number is skipped; an expression with no comparable point is reported as
such and never counted as agreeing. A reader's verdict is *right*, *WRONG value*,
*does not evaluate*, or *refused* with its error.

Three things went wrong in the first versions of this harness, and each one
produced results that looked plausible:

- **`Num <: Number`.** A check meant to catch "already a plain number" caught
  every symbolic expression, every evaluation failed, and with "agree" as the
  default verdict, 1535 expressions were reported as agreeing — including 148
  that were wrong. The verdict is now *not comparable* unless at least one point
  was compared.
- **No constant folding.** `Symbolics` 7 leaves `log(0.7)` symbolic after a
  substitution unless asked to fold, which looked like a phrasebook defect and
  was not.
- **Name clashes.** `using Giac` exports a `substitute` that shadows `Symbolics`',
  which made every evaluation fail again; the calls are qualified.

### Reproducing

```console
$ just oracle-numeric-setup      # environments in refs/, corpus fetched and checked
$ just oracle-numeric elements
$ just oracle-numeric-giac       # optional: Giac writes the OSR MathML (GPL-3.0, own process)
$ just oracle-numeric osr
```

The Giac step uses the registered Giac.jl, and with it giac 2.0.0. A second
setup uses the development Giac instead — Giac.jl's `chore/giac-2.1.0` branch
and the giac 2.1.0 libraries the JuliaGiac maintainer builds locally until they
are registered:

```console
$ just oracle-numeric-giac-dev-setup   # Julia 1.12 only, as those libraries are
$ just oracle-numeric-giac-dev         # then `just oracle-numeric osr` as above
```

It is a preview: those libraries are rebuilt in place, so a result from it says
which Giac produced it — the oracle prints the version the documents record.

### Results, 2026-11-28

MathML.jl 0.1.25, OpenMath.jl 0.1.0, Giac.jl 0.14.3 (the engine reports
`giac 2.0.0`), Symbolics 7.49.0, Julia 1.13.3.

**`osr`**, 1455 expressions compared:

| Route | Reader | right | WRONG value | refused | does not evaluate |
|:--|:--|--:|--:|--:|--:|
| rendered | MathML.jl | 1305 | **148** | 0 | 2 |
| rendered | OpenMath.jl | 1305 | 0 | 150 | 0 |
| Giac 2.0.0 | MathML.jl | 1393 | 0 | 62 | 0 |
| Giac 2.0.0 | OpenMath.jl | 1393 | 0 | 62 | 0 |
| Giac 2.1.0 dev | MathML.jl | 1455 | 0 | 0 | 0 |
| Giac 2.1.0 dev | OpenMath.jl | 1455 | 0 | 0 | 0 |

*Giac 2.0.0* is the registered Giac.jl 0.14.3. *Giac 2.1.0 dev* is
`just oracle-numeric-giac-dev`, recorded as: giac source `9f04834a25b2`,
`GIAC_jll` 200.100.0+0 artifact `f5d1f0c38c40`, Giac.jl `chore/giac-2.1.0` tree
`982b3c7bc175` — a build that includes JuliaGiac/giac#25.

**`elements`**, 90 elements: 70 agree, 15 are read by this package only, 3 by
MathML.jl only, 11 by neither, 4 differ in kind (MathML.jl returns a one-element
`Vector{Num}` for a unary `<real/>`, `<imaginary/>`, `<conjugate/>` and
`<ident/>`), and 2 are not numerically comparable (an `Equation`, a vector).

### What it found

**In this package**, all fixed:

- nine symbols of the `Symbolics` phrasebook — `gcd`, `lcm`, `quotient`,
  `factorial`, `round`, `trunc`, `not`, `implies`, and the number constructors
  behind `<cn base="16">` and `<cn type="e-notation">` — raised a `MethodError`
  on any argument; see the [phrasebook note](design/phrasebook.md);
- `interpret` let a `MethodError` escape on an application with the wrong number
  of arguments, which is what Giac's three-operand `<divide/>` reached.

**In this package**, not yet done: the 150 refusals are `<root>` with a
`<degree>`, a qualifier of Appendix F.2 this package does not implement yet.

**In MathML.jl** (`upstream-bugs.md`): all 148 wrong values are `<root>` with a
`<degree>`, which it computes as a power — about one expression in ten of a
real corpus, silently
([SciML/MathML.jl#134](https://github.com/SciML/MathML.jl/issues/134), fix
proposed in [#133](https://github.com/SciML/MathML.jl/pull/133)). The elements
it does not read are listed in
[#132](https://github.com/SciML/MathML.jl/issues/132).

**In Giac**: `(a/b)/c` is exported as a `<divide/>` of three operands, which
MathML does not allow; 62 expressions, refused by both readers (71 of the 1546
documents). Reproduced on giac 2.1.0 too; the cause is in `src/markup.cc`.
JuliaGiac/giac#25 fixes it, and a giac 2.1.0 build with it takes the count to 0:
both readers then read all 1455 documents right (`upstream-bugs.md`).

What none of this shows is as important: no wrong value came from this package,
on either route, and MathML.jl gave no wrong value on anything but `<root>` with
a `<degree>`.
