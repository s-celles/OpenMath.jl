# Security

`OpenMath.jl` decodes documents that arrive over the network — SCSCP sessions,
HTTP payloads, files of unknown provenance. Every entry point is treated as
accepting hostile input.

## Explicit stacks, not native recursion

A `StackOverflowError` cannot be caught reliably in Julia and can take down the
process. Every traversal therefore uses an explicit stack, and depth is checked
before any bounded recursion is entered.

```jldoctest
julia> using OpenMath

julia> deep = foldl((a, _) -> OMS"arith1#plus"(a), 1:500_000; init = OMInteger(0));

julia> depth(deep)
500001
```

## Configurable limits

[`OMLimits`](@ref) ceilings are scoped with [`with_limits`](@ref) and restored
even when the body throws.

```jldoctest
julia> using OpenMath

julia> nested = OMS"arith1#plus"(OMS"arith1#times"(OMInteger(1)));

julia> depth(nested)
3

julia> with_limits(OMLimits(; max_depth = 2)) do
           canonicalize(nested)
       end
ERROR: OpenMathLimitError: max_depth exceeded (3 > 2); raise it with `with_limits`
```

## Names are never interned

Julia never garbage-collects interned `Symbol`s. Turning attacker-controlled
names from a parsed document into symbols would be an unbounded memory leak, so
[`OMVariable`](@ref) and [`OMSymbol`](@ref) hold `String`s.

## Parsed content is never evaluated

A parsed OpenMath object is data. It never reaches `eval`, `include_string` or
`Meta.parse`, and a quality gate in the test suite enforces this over the whole
source tree.

Please report vulnerabilities privately; see `SECURITY.md` in the repository.

## Every traversal, without exception

The claim above — that every traversal uses an explicit stack — was not true for
one of them until Phase 8. The JSON reader built its tree by recursion, survived
about 10 000 levels on a default stack and not 20 000, and Julia's message on the
way out was "program state may be corrupted".

It was unreachable at the default limits, because `max_depth` is 10 000 and the
JSON scanner counts *JSON* nesting — roughly four levels per OpenMath level — so
a document was refused at about 2 500 OpenMath levels. It became reachable by
raising `max_depth`, which is the documented way to accept a deep document.

The builder now uses an explicit stack like the others, and a 200 000-level JSON
document parses. `test/unit/cross_encoding.jl` asserts the property over all four
encodings at once, which is where it should have been all along: the conformance
driver checks that the encodings agree about *objects*, and both readers agreed
about objects right up to the point where one of them stopped producing any.
