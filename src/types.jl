# SPDX-License-Identifier: MIT
#
# The OpenMath 2.0 object model (standard §2.1), designed from the standard.
#
# Two deliberate properties of this model:
#
#  * Illegal states are unrepresentable wherever the type system can say so.
#    `OMError` takes an `OMSymbol` head, `OMBinding` takes `OMBoundVariable`s and
#    `OMForeign` is deliberately *not* an `OMNode`, so the grammar constraints of
#    §2.1.1 hold by construction. Readers reject the corresponding malformed
#    documents at the parse boundary.
#
#  * Names are `String`, never `Symbol`. Julia never garbage-collects interned
#    symbols, so turning attacker-controlled names from a parsed document into
#    symbols would be an unbounded memory leak (REQ-SEC-001).

"""The base URI of the official OpenMath Content Dictionaries."""
const CD_BASE = "http://www.openmath.org/cd"

"""The XML namespace of OpenMath elements."""
const XML_NS = "http://www.openmath.org/OpenMath"

"""
    OMNode

Supertype of every OpenMath *object*. Note that `OMForeign` is not an `OMNode`:
foreign content is not an OpenMath object, and the grammar admits it only as an
attribute value or an `OMError` argument.
"""
abstract type OMNode end

"""Supertype of the atomic OpenMath objects."""
abstract type OMLeaf <: OMNode end

"""Supertype of the OpenMath objects built from other objects."""
abstract type OMComposite <: OMNode end

# ---------------------------------------------------------------- OMFOREIGN ---

"""
    OMForeign(encoding, value; id = nothing)

Non-OpenMath content carried inside an OpenMath object (standard §2.1.1). The
optional `encoding` describes how `value` should be interpreted.

`value` is the **verbatim source** of the foreign content, not decoded text.
The standard allows arbitrary XML there — presentation MathML is the common case
— so decoding entity references would make embedded markup indistinguishable
from text that merely looks like markup, and the round trip would stop being
lossless (REQ-OM-003). A writer therefore emits `value` unchanged, and refuses an
object whose foreign content is not a well-formed XML fragment rather than
producing a document that cannot be read back.
"""
struct OMForeign
    encoding::Union{Nothing, String}
    value::String
    id::Union{Nothing, String}
end

function OMForeign(encoding::Union{Nothing, AbstractString}, value::AbstractString;
        id::Union{Nothing, AbstractString} = nothing)
    OMForeign(encoding === nothing ? nothing : String(encoding), String(value),
        id === nothing ? nothing : String(id))
end

"""
    OMOrForeign

The positions in which the grammar allows either an OpenMath object or foreign
content: attribute values and `OMError` arguments.
"""
const OMOrForeign = Union{OMNode, OMForeign}

# -------------------------------------------------------------------- OMS -----

"""
    OMSymbol(cd, name; cdbase = nothing, id = nothing)

A symbol, defined by a Content Dictionary `cd` and a `name`, optionally
disambiguated by a `cdbase` URI (standard §2.1.1).

An `OMSymbol` is callable and builds an application:

```jldoctest
julia> using OpenMath

julia> OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x"))
OMA(OMS(arith1#plus), OMI(1), OMV(x))
```
"""
struct OMSymbol <: OMLeaf
    cdbase::Union{Nothing, String}
    cd::String
    name::String
    id::Union{Nothing, String}
end

function OMSymbol(cd::AbstractString, name::AbstractString;
        cdbase::Union{Nothing, AbstractString} = nothing,
        id::Union{Nothing, AbstractString} = nothing,
        validate_cdbase::Bool = true)
    checkname(cd, "content dictionary name")
    checkname(name, "symbol name")
    cdbase === nothing || !validate_cdbase || checkcdbase(cdbase)
    return OMSymbol(cdbase === nothing ? nothing : String(cdbase),
        String(cd), String(name),
        id === nothing ? nothing : String(id))
end

# --------------------------------------------------------- attributes / OMATP -

"""
    OMAttributePair(key, value)

One key/value pair of an attribution (`OMATP` in the XML encoding). The key is
always a symbol; the value may be foreign content.
"""
struct OMAttributePair
    key::OMSymbol
    value::OMOrForeign
end

"""
    OMBoundVariable(name, attributes = OMAttributePair[])

A variable bound by an [`OMBinding`](@ref). A non-empty `attributes` list is the
`OMATTR(…, OMV(name))` form of standard §2.1.2.
"""
struct OMBoundVariable
    name::String
    attributes::Vector{OMAttributePair}
end

function OMBoundVariable(name::AbstractString,
        attributes::AbstractVector = OMAttributePair[])
    checkname(name, "variable name")
    return OMBoundVariable(String(name), Vector{OMAttributePair}(attributes))
end

# ------------------------------------------------------------------- leaves ---

"""
    OMInteger(value; id = nothing)

An integer of unbounded magnitude (standard §2.1.1). Values that fit are stored
as `Int64`, so `OMInteger(5)` and `OMInteger(big(5))` are the same object.
"""
struct OMInteger <: OMLeaf
    value::Union{Int64, BigInt}
    id::Union{Nothing, String}
end

_narrow(v::Integer) = typemin(Int64) <= v <= typemax(Int64) ? Int64(v) : BigInt(v)

function OMInteger(value::Integer; id::Union{Nothing, AbstractString} = nothing)
    OMInteger(_narrow(value), id === nothing ? nothing : String(id))
end

"""
    OMFloat(value; id = nothing)

A double-precision floating-point number (standard §2.1.1). `NaN`, the infinities
and both signed zeros are distinct values here, because the `hex` encoding
distinguishes their bit patterns.
"""
struct OMFloat <: OMLeaf
    value::Float64
    id::Union{Nothing, String}
end

function OMFloat(value::Real; id::Union{Nothing, AbstractString} = nothing)
    OMFloat(Float64(value), id === nothing ? nothing : String(id))
end

"""
    OMString(value; id = nothing)

A Unicode character string (standard §2.1.1).
"""
struct OMString <: OMLeaf
    value::String
    id::Union{Nothing, String}
end

function OMString(value::AbstractString; id::Union{Nothing, AbstractString} = nothing)
    OMString(String(value), id === nothing ? nothing : String(id))
end

"""
    OMBytes(value; id = nothing)

A sequence of bytes (standard §2.1.1), base64-encoded in the XML encoding.
"""
struct OMBytes <: OMLeaf
    value::Vector{UInt8}
    id::Union{Nothing, String}
end

function OMBytes(value::AbstractVector{UInt8}; id::Union{Nothing, AbstractString} = nothing)
    OMBytes(Vector{UInt8}(value), id === nothing ? nothing : String(id))
end

"""
    OMVariable(name; id = nothing)

A variable (standard §2.1.1). `name` must match the `Name` production of §2.3.
"""
struct OMVariable <: OMLeaf
    name::String
    id::Union{Nothing, String}
end

function OMVariable(name::AbstractString; id::Union{Nothing, AbstractString} = nothing)
    checkname(name, "variable name")
    return OMVariable(String(name), id === nothing ? nothing : String(id))
end

"""
    OMReference(href; id = nothing)

A reference to another OpenMath object (standard §3.1.2).

Two kinds, and the difference matters. An **internal** reference has a
fragment-only `href` such as `"#s1"` and points at an element carrying that `id`
in the same document; [`expand_references`](@ref) resolves it, and a missing
target is an error. An **external** reference carries any other URI and points
into a *different* document — the binary encoding gives the two separate tokens,
30 and 31, precisely because they are not the same thing. An external reference
cannot be resolved without fetching, so the passes leave it alone rather than
treating it as broken.

See [`isinternal`](@ref).
"""
struct OMReference <: OMLeaf
    href::String
    id::Union{Nothing, String}
end

function OMReference(href::AbstractString; id::Union{Nothing, AbstractString} = nothing)
    OMReference(String(href), id === nothing ? nothing : String(id))
end

"""
    isinternal(r::OMReference) -> Bool

Whether `r` points inside its own document, that is, whether its `href` is a bare
fragment. External references name another document and cannot be resolved here.

# Examples
```jldoctest
julia> using OpenMath

julia> isinternal(OMReference("#s1")), isinternal(OMReference("scscp://host/q9t4eX"))
(true, false)
```
"""
isinternal(r::OMReference) = startswith(r.href, '#')

"""
    reference_target(r::OMReference) -> Union{Nothing,String}

The `id` an internal reference names, or `nothing` for an external one.
"""
reference_target(r::OMReference) = isinternal(r) ? String(SubString(r.href, 2)) : nothing

# --------------------------------------------------------------- composites ---

"""
    OMApplication(applicant, arguments; cdbase = nothing, id = nothing)

The application of `applicant` to `arguments` (standard §2.1.1). The standard
requires at least the applicant, which this type enforces by construction.
"""
struct OMApplication <: OMComposite
    applicant::OMNode
    arguments::Vector{OMNode}
    cdbase::Union{Nothing, String}
    id::Union{Nothing, String}
end

function OMApplication(applicant::OMNode, arguments::AbstractVector;
        cdbase::Union{Nothing, AbstractString} = nothing,
        id::Union{Nothing, AbstractString} = nothing)
    cdbase === nothing || checkcdbase(cdbase)
    return OMApplication(applicant, Vector{OMNode}(arguments),
        cdbase === nothing ? nothing : String(cdbase),
        id === nothing ? nothing : String(id))
end

(s::OMSymbol)(arguments::OMNode...) = OMApplication(s, collect(OMNode, arguments))

"""
    OMBinding(binder, variables, body; cdbase = nothing, id = nothing)

A binding object (standard §2.1.1): `binder` binds `variables` in `body`.
"""
struct OMBinding <: OMComposite
    binder::OMNode
    variables::Vector{OMBoundVariable}
    body::OMNode
    cdbase::Union{Nothing, String}
    id::Union{Nothing, String}
end

function OMBinding(binder::OMNode, variables::AbstractVector, body::OMNode;
        cdbase::Union{Nothing, AbstractString} = nothing,
        id::Union{Nothing, AbstractString} = nothing)
    cdbase === nothing || checkcdbase(cdbase)
    return OMBinding(binder, Vector{OMBoundVariable}(variables), body,
        cdbase === nothing ? nothing : String(cdbase),
        id === nothing ? nothing : String(id))
end

"""
    OMError(head, arguments; cdbase = nothing, id = nothing)

An error object (standard §2.1.1). `head` is always a symbol; arguments may be
foreign content.
"""
struct OMError <: OMComposite
    head::OMSymbol
    arguments::Vector{OMOrForeign}
    cdbase::Union{Nothing, String}
    id::Union{Nothing, String}
end

function OMError(head::OMSymbol, arguments::AbstractVector;
        cdbase::Union{Nothing, AbstractString} = nothing,
        id::Union{Nothing, AbstractString} = nothing)
    cdbase === nothing || checkcdbase(cdbase)
    return OMError(head, Vector{OMOrForeign}(arguments),
        cdbase === nothing ? nothing : String(cdbase),
        id === nothing ? nothing : String(id))
end

"""
    OMAttribution(attributes, object; cdbase = nothing, id = nothing)

An attributed object (standard §2.1.1). Nesting is preserved on parse and
flattened by [`collapse_attributions`](@ref).
"""
struct OMAttribution <: OMComposite
    attributes::Vector{OMAttributePair}
    object::OMNode
    cdbase::Union{Nothing, String}
    id::Union{Nothing, String}
end

function OMAttribution(attributes::AbstractVector, object::OMNode;
        cdbase::Union{Nothing, AbstractString} = nothing,
        id::Union{Nothing, AbstractString} = nothing)
    cdbase === nothing || checkcdbase(cdbase)
    return OMAttribution(Vector{OMAttributePair}(attributes), object,
        cdbase === nothing ? nothing : String(cdbase),
        id === nothing ? nothing : String(id))
end

# ------------------------------------------------------------------- OMOBJ ----

"""
    OMObject(object; version = "2.0", cdbase = nothing, id = nothing, warnings = String[])

The document root of an encoded OpenMath object (`OMOBJ`).

`warnings` records the deviations a `:lenient` parse accepted (REQ-API-005). It
is diagnostic only and takes no part in equality.
"""
struct OMObject
    object::OMNode
    version::String
    cdbase::Union{Nothing, String}
    id::Union{Nothing, String}
    warnings::Vector{String}
end

function OMObject(object::OMNode; version::AbstractString = "2.0",
        cdbase::Union{Nothing, AbstractString} = nothing,
        id::Union{Nothing, AbstractString} = nothing,
        warnings::AbstractVector = String[])
    cdbase === nothing || checkcdbase(cdbase)
    return OMObject(object, String(version),
        cdbase === nothing ? nothing : String(cdbase),
        id === nothing ? nothing : String(id),
        Vector{String}(warnings))
end

# Positional form used by the normalisation passes, which never carry warnings.
function OMObject(object::OMNode, version::AbstractString,
        cdbase::Union{Nothing, AbstractString}, id::Union{Nothing, AbstractString})
    OMObject(object, String(version),
        cdbase === nothing ? nothing : String(cdbase),
        id === nothing ? nothing : String(id), String[])
end

# --------------------------------------------------------------- OMS"…" -------

# Split a `cd#name` or `cdbase#cd#name` literal. Kept separate from the macro so
# that it can be tested directly.
function parse_oms_literal(s::AbstractString)
    i = findlast(==('#'), s)
    i === nothing && throw(ArgumentError(
        "OMS\"…\" expects \"cd#name\" or \"cdbase#cd#name\", got $(repr(String(s)))"))
    name = SubString(s, nextind(s, i))
    rest = SubString(s, 1, prevind(s, i))
    j = findlast(==('#'), rest)
    if j === nothing
        isempty(rest) && throw(ArgumentError(
            "OMS\"…\" has an empty content dictionary name in $(repr(String(s)))"))
        return (nothing, String(rest), String(name))
    end
    return (String(SubString(rest, 1, prevind(rest, j))),
        String(SubString(rest, nextind(rest, j))),
        String(name))
end

"""
    OMS"cd#name"
    OMS"cdbase#cd#name"

Build an [`OMSymbol`](@ref) from a literal, validated at macro-expansion time.

# Examples
```jldoctest
julia> using OpenMath

julia> OMS"arith1#plus"
OMS(arith1#plus)
```
"""
macro OMS_str(s)
    cdbase, cd, name = parse_oms_literal(s)
    checkname(cd, "content dictionary name")
    checkname(name, "symbol name")
    cdbase === nothing || checkcdbase(cdbase)
    return cdbase === nothing ? :(OMSymbol($cd, $name)) :
           :(OMSymbol($cd, $name; cdbase = $cdbase))
end
