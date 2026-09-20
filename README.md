# OpenMath.jl

[![CI](https://github.com/s-celles/OpenMath.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/s-celles/OpenMath.jl/actions/workflows/CI.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

A Julia implementation of the [OpenMath 2.0](https://openmath.org/) standard.

OpenMath encodes the *semantics* of mathematical objects rather than their
appearance. An OpenMath object is a small, fully specified tree whose leaves take
their meaning from **Content Dictionaries** — machine-readable documents defining
symbols such as `arith1#plus` or `calculus1#diff`. It is the interchange format
behind OMDoc, MMT and SCSCP, and it has a normative correspondence with W3C
Content MathML.

> **Status: v0.1.0, unreleased.** All four encodings the standard endorses are
> implemented and tested — XML (§3.1), binary (§3.2), JSON (§3.3) and Strict
> Content MathML (MathML 4 §4.1.3) — along with the object model, validation, the
> normalisation passes, Content Dictionaries and a `Symbolics.jl` phrasebook.
>
> Not registered in the General registry and not tagged, so install from the
> repository. The API may change in any minor release while the series is `0.x`;
> see [Compatibility](https://s-celles.github.io/OpenMath.jl/dev/compat/) and
> [`ROADMAP.md`](ROADMAP.md).

## Installation

```julia
julia> using Pkg; Pkg.add(url = "https://github.com/s-celles/OpenMath.jl")
```

## Usage

```julia
julia> using OpenMath

julia> e = OMS"arith1#plus"(OMInteger(1), OMVariable("x"))
OMA(OMS(arith1#plus), OMI(1), OMV(x))

julia> isvalid_openmath(e)
true

julia> canonicalize(e).applicant.cdbase
"http://www.openmath.org/cd"

julia> to_openmath(3 // 4)
OMA(OMS(nums1#rational), OMI(3), OMI(4))

julia> from_openmath(to_openmath([1, 2, 3]))
3-element Vector{Int64}:
 1
 2
 3
```

Your own types join in by adding one method:

```julia
julia> struct Celsius; value::Float64; end

julia> OpenMath.to_openmath(c::Celsius) =
           OMS"http://example.org/cd#units#celsius"(to_openmath(c.value));

julia> to_openmath(Celsius(21.5))
OMA(OMS(http://example.org/cd#units#celsius), OMF(21.5))
```

## Design notes

Two decisions are worth knowing about up front, because they differ from a naive
transcription of the standard.

**Illegal states are unrepresentable.** `OMError` takes an `OMSymbol` head,
`OMBinding` takes `OMBoundVariable`s, and `OMForeign` is deliberately *not* an
`OMNode` — foreign content is not an OpenMath object, and the grammar admits it
only as an attribute value or an error argument. The grammar constraints of
standard §2.1.1 therefore hold by construction, and the readers reject the
corresponding malformed documents at the parse boundary. What `validate` reports
is everything about the *graph* that types cannot express: reference cycles,
dangling references, duplicate ids, `cdbase` URI syntax and size.

**Hostile input is the default assumption.** OpenMath travels over SCSCP sockets
and in web payloads. Names are `String`, never `Symbol`, because Julia never
garbage-collects interned symbols and a parsed document would otherwise be an
unbounded memory leak. Every traversal uses an explicit stack, so a deeply nested
document raises a catchable `OpenMathLimitError` rather than a `StackOverflowError`:

```julia
julia> deep = foldl((a, _) -> OMS"arith1#plus"(a), 1:500_000; init = OMInteger(0));

julia> depth(deep)
500001
```

Limits are configurable and scoped:

```julia
julia> with_limits(OMLimits(; max_depth = 10)) do
           canonicalize(deep)
       end
ERROR: OpenMathLimitError: max_depth exceeded (500001 > 10); raise it with `with_limits`
```

## Development

The project is built around a verifier with a machine-readable contract:

```console
$ just verify fast        # inner loop, under ten seconds
$ just verify standard    # before claiming a piece of work done
$ just verify-json        # the same, as JSON
$ just test               # the whole suite
$ just quality            # Aqua, SPDX headers, dependency hygiene, no-eval
$ just docs               # documentation, fails on any warning
```

Requirements are written in [EARS](https://alistairmavin.com/ears/) syntax with
MoSCoW priorities in [`specs/requirements.md`](specs/requirements.md); the design
is in [`spec.md`](spec.md) and the delivery plan in [`ROADMAP.md`](ROADMAP.md).

Supported Julia versions: **1.10 (LTS)** and **1.13**.

## Related work

- [`openmath`](https://github.com/FlexiFormal/OpenMath) — the Rust reference
  implementation (GPL-3.0-or-later), used here as a conformance oracle only.
  This package is a clean-room implementation from the published standard.
- [`MathML.jl`](https://github.com/SciML/MathML.jl) — Content MathML for Julia,
  and the technical reference for this package's Julia-side stack.

## License

MIT — see [`LICENSE.md`](LICENSE.md).
