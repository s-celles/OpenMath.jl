# Non-strict Content MathML — design note (Phase 7)

[`read_mathml`](@ref) reads **Strict Content MathML**, which is the encoding
OpenMath 2.0 endorses (MathML 4 §4.1.3): every application is an `apply` whose
first child is a `csymbol`, every number carries a type, and there is nothing
else. That is a small language, and the mapping to OpenMath is an isomorphism.

Almost no MathML in the world is written that way. The *non-strict* dialect has
`<plus/>`, `<pi/>`, `<cn base="16">`, `<lambda>`, `<piecewise>` and about eighty
other spellings, and a reader that refuses all of it is a reader most documents
cannot reach.

The temptation is to guess: recognise `<plus/>`, map it to `arith1#plus`, and
carry on. This package does not, because **MathML 4 Appendix F defines the
transformation normatively**. There is a specified answer, so a guess is never
required and never acceptable. `strict = false` follows Appendix F, and where
Appendix F asks for more than is implemented the input is **refused naming the
section** rather than transformed approximately.

```julia
OpenMath.parse(source; format = :mathml, strict = false)
```

## What is implemented

| Section | Rule | Status |
|:--|:--|:--|
| F.4.3 | `<lambda>` → `OMBIND` with `fns1#lambda` | ✅ |
| F.4.4 | `<piecewise>`, `<piece>`, `<otherwise>` → `piece1` | ✅ |
| F.7.1 | `<cn type="constant">` → `nums1` symbol | ✅ |
| F.7.1 | `<cn>` with `<sep/>` → `rational`, `complex_cartesian`, `complex_polar`, `bigfloat` | ✅ |
| F.7.1 | `<cn base="b">` → `nums1#based_integer` / `based_float` | ✅ |
| F.8 | operator element → `csymbol` (76 names) | ✅ |
| F.8.1 | `minus` takes its symbol from its arity | ✅ |
| F.9.1 | an untyped `<cn>` takes its type from its lexical form | ✅ |
| F.2.5 | `<root/>` with no `<degree>` is the square root | ✅ |

## What is not, and why that is stated rather than approximated

| Section | Rule | Refused with |
|:--|:--|:--|
| F.2 | idiomatic qualifiers — `<degree>`, `<lowlimit>`, `<uplimit>`, `<bvar>` on an `apply` | "needs MathML 4 Appendix F.2, idiomatic qualifiers" |
| F.2.1–F.2.7 | derivatives, integrals, limits, sums, moments | the section that governs it |
| F.3 | `<condition>` → `domainofapplication` | "F.3, rewrite to domainofapplication" |
| F.5.2 | `<forall>`, `<exists>` | "F.5.2, quantifiers" |

These share one shape: a qualifier changes the *meaning* of the operator it
qualifies, so they cannot be handled element by element. `<apply><sum/>
<bvar><ci>i</ci></bvar><lowlimit>…` is not a `sum` applied to four things; it is
a `sum` over a set built from the qualifiers. Implementing that properly is a
piece of work, and implementing it improperly is worse than refusing, because a
wrong integral is silent.

So each is listed in `_F_UNIMPLEMENTED` with the section that governs it, and the
error names it. A reader who hits one learns what to write instead; a
contributor who wants to add one learns exactly which rule to read.

### `<root/>` is the exception that proves the rule

F.2.5 is a qualifier rule and is listed above as unimplemented — but its
*degenerate* case is not a guess. `<root/>` with no `<degree>` is the square
root, so the missing `2` is supplied. The qualifier form is still refused,
because `<degree>` is in the unimplemented table, so the rule cannot fire where
the answer would be uncertain.

This was **found by the oracle, not written from the specification**: see below.

## How this was checked

Two gates, and they check different things.

**The MathML.jl oracle** (`just oracle-mathml`) takes the *same non-strict
document* and sends it two ways — directly through MathML.jl, and through
Appendix F into OpenMath and back out via the Symbolics phrasebook — then
compares the two `Num`s. 21 vectors, 19 agreeing; the two that do not are
`floor` and `ceiling`, where MathML.jl returns a smooth Fourier surrogate rather
than the step function, which is a documented divergence (E4) and not a defect
on either side.

That shared-document path is what found the `root` arity defect. The oracle also
carries 21 *hand-written* pairs, where the OpenMath side is written out by hand
— and those passed, because writing the pair by hand means supplying the
`arith1#root(x, 2)` the transformation was failing to produce. **A differential
check is only as strong as the input both sides are made to share**; the same
lesson as E3 and E7, in a third place.

**The vocabulary gate** (`test/unit/mathml_appendix_f.jl`) asserts that every
symbol this transformation can produce is one [`base_vocabulary`](@ref) knows.
Appendix F and the phrasebook were written from different documents, in
different files, and nothing but this gate makes them agree — when it was first
run it failed on six symbols: `nums1#based_integer`, `based_float`, `bigfloat`,
`complex_polar`, `nums1#gamma` and `set1#emptyset`. A document could transform
perfectly and then be refused by the phrasebook. Those six are now defined.

`fns1#lambda` and the three `piece1` symbols are deliberately *outside* the
vocabulary, and the gate asserts their absence too: a binder and a piecewise are
not applications of a function, and are interpreted structurally rather than by
looking the head up.

## The round trip is one-way

Appendix F is a *normalisation*, so it does not invert. `<plus/>` and
`<csymbol cd="arith1">plus</csymbol>` both become `arith1#plus`, and writing
that back produces the strict form. This package writes strict Content MathML
only, which is the encoding the OpenMath standard endorses, and there is no
setting that makes it emit `<plus/>`.
