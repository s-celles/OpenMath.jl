# Decision D3 — the JSON backend

**Status**: settled, 2026-09-17. **Outcome**: a purpose-built scanner, in
`src/json/scanner.jl`. Neither `JSON.jl` nor `JSON3.jl` is a dependency.

## Why not a JSON library

The card offered `JSON.jl` v1 against `JSON3.jl`, with the 1.10 LTS as the
tie-breaker. Both are pure Julia, so REQ-PRJ-002 does not decide it the way it
decided [D1](xml-backend.md). What decides it is one line of the standard:

```json
{"kind": "OMI", "integer": -120}
```

`integer` is a **JSON number**, and OpenMath integers have no predefined range
(standard §2.1.1). So this is legal:

```json
{"kind": "OMI", "integer": 1606938044258990275541962092341162602522202993782792835301376}
```

A JSON parser that hands back a `Float64` — which is the default in most of them,
because the JSON spec says nothing about precision — has already destroyed that
value before our code sees it. REQ-JSN-003 is a **Must**, and satisfying it on top
of a general parser means either configuring an arbitrary-precision mode that
differs between the two candidates, or post-processing text the parser has already
thrown away.

The scanner here keeps every number as its **source text** and does not interpret
it until the reader knows which OpenMath field it belongs to. `"integer"` becomes
a `BigInt`, `"float"` becomes a `Float64`, and neither ever passes through the
other's type.

The same three arguments as D1 apply again:

- **REQ-SEC-001** — nothing outside the `OpenMathError` family escapes, for any
  byte sequence. Wrapping a third-party parser means catching everything, which
  loses the byte offset **REQ-API-007** wants.
- **REQ-SEC-002** — depth is bounded by an explicit stack, not by the native one.
- **REQ-PRJ-002** — the core keeps its promise of no mandatory dependency at all,
  which is stronger than the requirement asks.

## What the subset costs us

The scanner is ~300 lines: objects, arrays, strings with the six short escapes and
`\uXXXX` including surrogate pairs, numbers with JSON's leading-zero rule, and the
three literals. There is no streaming API, no lazy access, no `StructTypes`
integration — none of which this encoding needs.

## Cross-check

Our output was compared byte for byte against the reference implementation on
seven corpus items covering every composite kind. It matched exactly, including
member order, `"error"` for the `OME` head and `"base64"` for `OMB`. That is a
confirmation, not a dependency: `just oracle` is opt-in and no part of the package
requires it.

## Revisit if

- a caller needs to embed OpenMath inside a larger JSON document and wants to hand
  us an already-parsed value. That is an argument for an *optional* extension over
  a JSON library, not for making one a core dependency.
