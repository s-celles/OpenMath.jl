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
| F.2.6 | `<log/>` with no `<logbase>` is base 10 | ✅ |
| F.4 | `<set>`, `<list>`, `<vector>`, `<matrix>`, `<matrixrow>` as containers | ✅ |

## What is not, and why that is stated rather than approximated

| Section | Rule | Refused with |
|:--|:--|:--|
| F.2 | idiomatic qualifiers — `<degree>`, `<lowlimit>`, `<uplimit>`, `<bvar>` on an `apply` | "needs MathML 4 Appendix F.2, idiomatic qualifiers" |
| F.2.1–F.2.7 | derivatives, integrals, limits, sums, moments | the section that governs it |
| F.3 | `<condition>` → `domainofapplication` | "F.3, rewrite to domainofapplication" |
| F.5.2 | `<forall>`, `<exists>` | "F.5.2, quantifiers" |
| F.2.6 | `<logbase>` | "F.2.6, logarithms" |
| F.4 | `<interval>` | "F.4, container markup" |

These share one shape: a qualifier changes the *meaning* of the operator it
qualifies, so they cannot be handled element by element. `<apply><sum/>
<bvar><ci>i</ci></bvar><lowlimit>…` is not a `sum` applied to four things; it is
a `sum` over a set built from the qualifiers. Implementing that properly is a
piece of work, and implementing it improperly is worse than refusing, because a
wrong integral is silent.

So each is listed in `_F_UNIMPLEMENTED` with the section that governs it, and the
error names it. A reader who hits one learns what to write instead; a
contributor who wants to add one learns exactly which rule to read.

### The degenerate cases are the exception that proves the rule

F.2.5 and F.2.6 are qualifier rules, listed above as unimplemented — but their
*degenerate* cases are not guesses.

`<root/>` with no `<degree>` is the square root, and `<log/>` with no
`<logbase>` is base 10 (MathML 4 §4.3). Both OpenMath symbols take that argument
explicitly: `arith1#root(x, 2)`, and `transc1#log(10, x)` — base first, as the
`transc1` CD's own FMP says, reading `log(a, c) = b` when `a^b = c`. So the
missing argument is supplied.

Each is safe for the same reason: the qualifier that would make the answer
uncertain is itself in the unimplemented table, so the rule is refused before it
can fire on a case it would get wrong.

Both were **found by the oracle, not written from the specification**: see below.

### Containers are elements, not just symbols

`<set>`, `<list>`, `<vector>`, `<matrix>` and `<matrixrow>` are operator names
*and* container elements. They were in the §F.8 table and nowhere else, so
`<set/>` heading an `apply` worked and `<set>1 2</set>` — the way anybody
actually writes one — fell through to "unhandled element". Half-present is worse
than either state.

They are now distinguished by position: first child of an `<apply>` is the
symbol, anything else is an application of it. `type="multiset"` selects
`multiset1#multiset`, because a multiset keeps its repeats and dropping the
attribute would silently turn it into a set. An attribute value with no OpenMath
counterpart — `<list order="lexicographic">` — is **refused rather than
dropped**.

### A refusal names the section it comes from

Several elements that are perfectly good Content MathML — `<logbase>`,
`<interval>` — were refused as "not Content MathML at all". The refusal was
right and the reason was false, which is worse than a generic message: it tells
a reader to stop looking for a rule that exists. Every refusal now names the
Appendix F section that governs it, and "not Content MathML at all" is reserved
for what really is not, such as presentation markup.

### What is *not* checked: arity

`<apply><sum/><ci>x</ci></apply>` transforms to `arith1#sum(x)`, and `arith1#sum`
takes a range and a function — two arguments. That object is malformed, and this
reader does not say so, exactly as it does not object to `arith1#plus` with one
argument. Arity is a property of the Content Dictionary, checked by
[`validate`](@ref) and not by the transformation; F.8's table is what the
specification gives and this implements it. A `<sum/>` written the normal way,
with `<bvar>` and `<lowlimit>`, is refused by F.2 before it gets here.

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

The `log` vector was added *after* the rule was written, and disagreed
immediately — not on the base, which was right, but on the form: `log(x)/log(10)`
against MathML.jl's `log10(x)`. The same number, a different expression, and
enough to stop the round trip being the identity. The phrasebook now maps
`transc1#log(10, x)` onto `log10` and `transc1#log(2, x)` onto `log2`, which are
the bases Symbolics keeps whole, exactly as `arith1#root(a, 2)` maps onto `sqrt`.

**The vocabulary gate** (`test/unit/mathml_appendix_f.jl`) asserts that every
symbol this transformation can produce is one [`base_vocabulary`](@ref) knows.
Appendix F and the phrasebook were written from different documents, in
different files, and nothing but this gate makes them agree — when it was first
run it failed on six symbols: `nums1#based_integer`, `based_float`, `bigfloat`,
`complex_polar`, `nums1#gamma` and `set1#emptyset`. A document could transform
perfectly and then be refused by the phrasebook. Those six are now defined, and
`multiset1#multiset` with them.

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

## Why there is no `MathML.jl` extension

An earlier plan had an `ext/OpenMathMathMLExt.jl` bridging `MathML.jl`'s
`Symbolics` output into OpenMath, for callers holding non-strict Content MathML
from SBML or the SciML stack. Appendix F changed the premise, so the plan was
re-surveyed rather than executed, and withdrawn on three findings.

**It would buy one element.** Comparing the two tables, `MathML.jl` (v0.1.24)
reads two names we do not: `prod`, which is not a MathML element and raises
`KeyError` there anyway, and `<diff>` — F.2.1, implemented with its author's own
`# won't work for all cases` against `bvar` and `degree`.

**It would contain no code.** This already works, with nothing but what the
package ships, because the `Symbolics` extension supplies `to_openmath(::Num)`:

```julia
to_openmath(only(MathML.parse_str(source)))
```

**And the route is lossier than ours.** `MathML.jl` reads every untyped `<cn>` as
a `Float64`:

| | `<apply><plus/><ci>x</ci><cn>2</cn></apply>` |
|:--|:--|
| via `MathML.jl` | `arith1#plus(OMF(2.0), OMV(x))` |
| via Appendix F | `arith1#plus(OMV(x), OMI(2))` |

The integer and the argument order are both gone, where F.9.1 is explicit that an
untyped `<cn>` whose lexical form is an integer *is* an integer.

If derivatives matter, the honest successor is **F.2.1 itself**, which is now the
only reason left to have wanted the extension.
