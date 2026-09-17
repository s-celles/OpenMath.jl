# Object model

Every OpenMath 2.0 object kind has its own concrete type. [`kind`](@ref) returns
the tag the standard uses.

| Julia type | Tag | Standard |
|---|---|---|
| [`OMInteger`](@ref) | `OMI` | §2.1.1 |
| [`OMFloat`](@ref) | `OMF` | §2.1.1 |
| [`OMString`](@ref) | `OMSTR` | §2.1.1 |
| [`OMBytes`](@ref) | `OMB` | §2.1.1 |
| [`OMVariable`](@ref) | `OMV` | §2.1.1 |
| [`OMSymbol`](@ref) | `OMS` | §2.1.1 |
| [`OMApplication`](@ref) | `OMA` | §2.1.1 |
| [`OMBinding`](@ref) | `OMBIND` | §2.1.1 |
| [`OMError`](@ref) | `OME` | §2.1.1 |
| [`OMAttribution`](@ref) | `OMATTR` | §2.1.1 |
| [`OMForeign`](@ref) | `OMFOREIGN` | §2.1.1 |
| [`OMReference`](@ref) | `OMR` | §3.1.2 |

## Illegal states are unrepresentable

Several constraints of the grammar are carried by the type signatures rather than
checked afterwards, which is strictly stronger:

- [`OMError`](@ref) takes an [`OMSymbol`](@ref) head.
- [`OMBinding`](@ref) takes [`OMBoundVariable`](@ref)s.
- [`OMForeign`](@ref) is **not** an [`OMNode`](@ref). Foreign content is not an
  OpenMath object, and the grammar admits it only as an attribute value or an
  error argument. Those positions are typed [`OMOrForeign`](@ref).

What [`validate`](@ref) reports is everything about the *graph* that types cannot
express: reference cycles, dangling references, duplicate `id`s, `cdbase` URI
syntax, and the depth and node budgets.

## Equality

`==` is structural and disregards `id`, because an `id` anchors an `OMR`
reference and carries no mathematical content. Use [`isequal_with_ids`](@ref)
when you are testing the fidelity of a round-trip.

```jldoctest
julia> using OpenMath

julia> OMInteger(1; id = "a") == OMInteger(1; id = "b")
true

julia> isequal_with_ids(OMInteger(1; id = "a"), OMInteger(1; id = "b"))
false
```

Floats compare by `isequal`, not `==`: the hexadecimal encoding distinguishes
`NaN` from `NaN` with a different payload, and `+0.0` from `-0.0`, so the object
model has to as well.

```jldoctest
julia> using OpenMath

julia> OMFloat(NaN) == OMFloat(NaN)
true

julia> OMFloat(0.0) == OMFloat(-0.0)
false
```

## Names

Symbol, variable and content dictionary names must match the `Name` production of
standard §2.3. Constructors check this, so an invalid name cannot enter the model.

```jldoctest
julia> using OpenMath

julia> OMVariable("has space")
ERROR: OpenMathNameError: invalid variable name "has space" at character 4 (' '); see the OpenMath 2.0 standard §2.3
```
