# Phrasebooks — design note (Phase 6)

A *phrasebook*, in OpenMath's own terminology, is the translation between
OpenMath objects and the values of one particular system. This package already
has a fixed one — [`to_openmath`](@ref) and [`from_openmath`](@ref), extended by
dispatch — and Phase 6 turns it into a value you can carry, swap and scope, and
adds a `Symbolics.jl` phrasebook on top of it.

This note is written **before** the implementation, which is the point: harness
step **H2.5**, added after Phase 4 shipped two interoperability defects that no
self-referential test could catch.

## The oracle survey

E2 concluded that a differential oracle's yield tracks *coverage overlap* — not
the layer it sits in, and not how good the oracle is in the abstract. So the
candidates are ranked by how much of the same ground they cover.

| Candidate | What it maps | Overlap | Verdict |
|:--|:--|:--|:--|
| **[MathML.jl](https://github.com/SciML/MathML.jl)** (SciML, MIT) | non-strict Content MathML → `Symbolics.Num` | **Same target language, same symbol vocabulary**: 85 element names, drawn from the OpenMath CDs | **Primary oracle** |
| **GAP `openmath`** (installed, `just oracle-gap`) | OpenMath ↔ GAP values | Base types only — integers, rationals, lists, booleans, strings. GAP has no symbolic algebra, so `sin(x)` has no counterpart | **Secondary**, for the base phrasebook |
| `py-openmath` | OpenMath ↔ its own tree, plus "basic Python objects" | No symbolic target | ruled out |
| SymPy | — | No OpenMath support found in its documentation | ruled out |
| MMT / KWARC | OpenMath ↔ MMT terms | Different target language, no Julia path | ruled out |
| Maple, Mathematica phrasebooks | OpenMath ↔ CAS | Proprietary, unobtainable | ruled out |

**The prediction this makes**, recorded now so it can be checked later: MathML.jl
should find defects in the symbolic mapping, GAP should find them in the base
types, and nothing else is worth its cost. If MathML.jl finds nothing, E2's
hypothesis is wrong and should be written up as such.

### How MathML.jl is used, and how it is not

It reads the **non-strict** Content MathML dialect, which this package
deliberately refuses. So it cannot be handed our output. The differential test is
instead a shared *input* in two dialects:

```
one mathematical object
   ├─ written as non-strict Content MathML  →  MathML.jl  →  Symbolics expression
   └─ written as OpenMath                   →  us         →  Symbolics expression
                                                              compare
```

The vectors are written by hand, in pairs, which is the honest way round: neither
implementation generates the other's input, so agreement means something.

### Why it is not a test dependency

`MathML.jl` pins `Symbolics = "7.39.2"` — an exact version, not a range — and
depends on `EzXML`, hence on the `XML2_jll` binary artifact. Putting it in
`test/Project.toml` would pin this package's whole test environment to one
Symbolics patch release.

So it goes where the other oracles go: its own environment under gitignored
`refs/`, behind `just oracle-mathml`, out of CI. That is the same shape as
`oracle-gap` and for the same reason.

This also settles part of decision **D5**. The `Symbolics` support ships as a
package extension, not a companion package: the pinning problem is MathML.jl's,
not Symbolics', and a weak dependency inherits no pin.

## What the phrasebook has to be

**A value, not global state** (REQ-PHR-001). `to_openmath` dispatches on Julia
types, which is right for a default and wrong as the only mechanism: two callers
in one session may legitimately want `nums1#rational` to mean different things,
and a method table cannot hold both. A `Phrasebook` is therefore a value with
forward and backward maps keyed on `(cdbase, cd, name)`, with the dispatch-based
conversion as its default contents.

**Structural, never evaluating** (REQ-PHR-003). Building a Julia value from
parsed content must never route through `eval` or `include_string`. The symbol
`arith1#plus` is looked up in a map and the *function* found there is applied; the
name is never turned into code. This is already enforced by a quality gate, and
the gate is the reason to write it down here rather than to remember it.

**Loud about what it cannot do** (REQ-PHR-005). A symbol with no counterpart
raises, naming the symbol. Silently dropping an attribution or an unknown head is
how a phrasebook turns a faithful document into a plausible lie.

## Coverage target

The exit criterion is MathML.jl's table, symbol by symbol. Its 85 element names
map onto the OpenMath Content Dictionaries they were named after — `arith1`,
`transc1`, `relation1`, `logic1`, `nums1`, `fns1`, `calculus1`, `piece1`,
`rounding1`, `integer1`, `complex1`, `minmax1`, `linalg2`, `s_data1` — which is
the correspondence MathML 4 §4.1.3 exists to state. The docs will carry the table
both ways round.

## Where it stands

The base phrasebook covers **76 of MathML.jl's 85 element names**, which is all
of them that denote a symbol. The remaining nine are structure rather than
vocabulary: `apply`, `bvar`, `ci`, `cn` and `math` are MathML syntax with no
symbol behind them, and `diff`, `lambda`, `piecewise` and `degree` need the
symbolic layer — `calculus1#diff`, `fns1#lambda`, `piece1#piecewise` — which is
the `Symbolics` extension.

The correspondence is asserted element by element in
`test/unit/phrasebook.jl`, transcribed rather than computed, so the test fails if
the vocabulary shrinks. An exit criterion that is not executable is a wish.

## The Symbolics bridge

Shipped as the package extension `OpenMathSymbolicsExt`, loaded when `Symbolics`
is. The two directions are not the same problem, and the code is shaped that way.

**Symbolics → OpenMath is structural.** Walk the expression tree and relabel each
operator with the Content Dictionary symbol it corresponds to. Nothing is
interpreted, so nothing can be interpreted wrongly. Reached through
`to_openmath`, by dispatch, like every other Julia type.

**OpenMath → Symbolics goes through a phrasebook**, because a variable has to
become a Symbolics variable rather than a `Symbol`. That is what
`define_variable!` exists for: making it a method on `interpret` would be global,
and two callers in one session could then not disagree.

```julia
julia> using OpenMath, Symbolics

julia> @variables x y;

julia> to_openmath(sin(x) + y)
OMA(OMS(arith1#plus), OMV(y), OMA(OMS(transc1#sin), OMV(x)))

julia> p = OpenMath.symbolics_phrasebook();

julia> interpret(p, OMS"transc1#sin"(OMVariable("x")))
sin(x)
```

### Symbolics normalises first, and the encoding shows it

This is the thing to know before reading any output. `-x` is stored as `(-1) * x`
and comes out as `arith1#times`, never `arith1#unary_minus`. `x - y` is
`x + (-1)*y` and never produces `arith1#minus`. The argument order of a sum is
the normal form's, not the source's.

Both symbols are in the writer, for expressions that do reach it in that shape,
and the tests assert the normalised result rather than the intuitive one — which
is the honest way round.

### Derivatives need a lambda

OpenMath has no free-standing derivative operator. `calculus1#diff` applies to a
*function*, so the bound variable is carried by an `fns1#lambda` binding:

```julia
julia> to_openmath(Differential(x)(x^2))
OMA(OMS(calculus1#diff), OMBIND(OMS(fns1#lambda), [x], OMA(OMS(arith1#power), OMV(x), OMI(2))))
```

That is the whole of the correspondence, and it is why a derivative cannot be one
more row in the vocabulary table: it is the only entry that needs a binder.

### What raises

An operator with no Content Dictionary symbol — `sign`, `sinc` — raises
`OpenMathConversionError` naming it (REQ-PHR-005). Writing an approximation and
saying nothing is the failure this guards against.

## What the oracle found

`just oracle-mathml-setup` then `just oracle-mathml`, on 21 hand-written pairs:

```
oracle — MathML.jl, 21 paired vectors
  19/21 agree
    ✗ floor     MathML.jl gives -0.5 + 0.3183098861837907atan(cot(π*x)) + x, we give floor(x)
    ✗ ceiling   MathML.jl gives 0.5 + 0.3183098861837907atan(cot(π*x)) + x, we give ceil(x)
```

Both disagreements are `rounding1`, and neither is a defect on either side.
`x - ½ + atan(cot(πx))/π` is the Fourier approximation of the floor function:
smooth everywhere except the integers, where the real floor is discontinuous.
MathML.jl is built for SBML and SciML, where an expression usually ends up inside
a differential equation solver, and a differentiable surrogate is the useful
thing to hand back.

This package encodes what the Content Dictionary says, and `rounding1#floor` is
the floor function. So we keep `floor`, and the divergence is recorded rather
than reconciled: **a caller moving an expression between the two libraries gets
different answers at the integers**, deliberately, in both directions.

It is worth being precise about what this does and does not confirm. E2 predicted
that MathML.jl "should find defects in the symbolic mapping". It found
*divergences*, not defects — two places where two correct implementations
disagree because they are for different purposes. That is still something no
self-referential test could have produced, and it is still the highest-overlap
oracle available; but the prediction as written was not borne out, and the
hypothesis should be read as being about *disagreements* rather than about bugs.

## What the generated property found

The unit tests cover sixteen expressions written by hand. `P9` generates them
instead, from the mapped vocabulary, and found two things no hand-written case
did.

**`transc1#sin` applied to `OMI(-8)` was being evaluated.** A phrasebook whose
symbols map onto ordinary Julia functions computes `sin(-8)` the moment the
literal arrives as an `Int`, and `-0.9893…` came back where `sin(-8)` went in.
For plain Julia that is right; for a computer algebra system it is not, and
evaluation is an explicit non-goal (REQ-PHR-006). Fixed by
[`define_leaf!`](@ref), which is to literals what `define_variable!` is to
variables — the Symbolics phrasebook wraps numbers in `Num` so that applying a
mapped symbol *builds* rather than *computes*.

**A unary `arith1#times` was reaching the output.** Symbolics keeps sums and
products as nodes with a coefficient, and a unit coefficient leaves a
one-argument node behind, so `x^4` arrived as `*(x^4)` and was written
`arith1#times(arith1#power(x, 4))`. A product of one factor is that factor; the
`times` was a host-language artefact that no other producer would emit. The
writer now collapses it.

### The property is idempotence, not identity

Worth stating plainly, because it is a fact about Symbolics rather than a
weakening to make a test pass. Symbolics keeps several representations of one
mathematical object and `isequal` is structural: `x^4` may be `Mul(1, Pow(x, 4))`,
distinct from `Pow(x, 4)` though equal as mathematics, and `2//1` normalises to
`2` on the way back in.

Neither distinction survives a trip through OpenMath, and neither should —
OpenMath encodes the object, not the host's spelling of it. So the first round
trip may land on a different representative, and every one after that is a fixed
point. That is what a lossless encoding promises here, and it is what `P9`
asserts, over 500 generated expressions and 3000 in a brute-force run.

The identity does hold for expressions already in a normal form, which is every
one of the sixteen hand-written cases.
