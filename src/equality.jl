# SPDX-License-Identifier: MIT
#
# Structural equality (REQ-OM-004). `id` is a serialisation artefact — it anchors
# OMR references — and carries no mathematical content, so it is excluded. Use
# `isequal_with_ids` when byte fidelity is what you are testing.
#
# Floats compare by `isequal`, not `==`: the hex encoding distinguishes NaN from
# NaN-with-a-different-payload and +0.0 from -0.0, so the object model must too.

Base.:(==)(::OMNode, ::OMNode) = false

Base.:(==)(a::OMInteger, b::OMInteger) = a.value == b.value
Base.:(==)(a::OMFloat, b::OMFloat) = isequal(a.value, b.value)
Base.:(==)(a::OMString, b::OMString) = a.value == b.value
Base.:(==)(a::OMBytes, b::OMBytes) = a.value == b.value
Base.:(==)(a::OMVariable, b::OMVariable) = a.name == b.name
Base.:(==)(a::OMReference, b::OMReference) = a.href == b.href

function Base.:(==)(a::OMSymbol, b::OMSymbol)
    a.cd == b.cd && a.name == b.name && a.cdbase == b.cdbase
end

Base.:(==)(a::OMForeign, b::OMForeign) = a.encoding == b.encoding && a.value == b.value

Base.:(==)(a::OMAttributePair, b::OMAttributePair) = a.key == b.key && a.value == b.value

function Base.:(==)(a::OMBoundVariable, b::OMBoundVariable)
    a.name == b.name && a.attributes == b.attributes
end

function Base.:(==)(a::OMApplication, b::OMApplication)
    a.cdbase == b.cdbase && a.applicant == b.applicant && a.arguments == b.arguments
end

function Base.:(==)(a::OMBinding, b::OMBinding)
    a.cdbase == b.cdbase && a.binder == b.binder &&
        a.variables == b.variables && a.body == b.body
end

function Base.:(==)(a::OMError, b::OMError)
    a.cdbase == b.cdbase && a.head == b.head && a.arguments == b.arguments
end

function Base.:(==)(a::OMAttribution, b::OMAttribution)
    a.cdbase == b.cdbase && a.attributes == b.attributes && a.object == b.object
end

function Base.:(==)(a::OMObject, b::OMObject)
    a.version == b.version && a.cdbase == b.cdbase && a.object == b.object
end

# --- hashing ------------------------------------------------------------------

Base.hash(x::OMInteger, h::UInt) = hash(x.value, hash(:OMI, h))
Base.hash(x::OMFloat, h::UInt) = hash(x.value, hash(:OMF, h))
Base.hash(x::OMString, h::UInt) = hash(x.value, hash(:OMSTR, h))
Base.hash(x::OMBytes, h::UInt) = hash(x.value, hash(:OMB, h))
Base.hash(x::OMVariable, h::UInt) = hash(x.name, hash(:OMV, h))
Base.hash(x::OMReference, h::UInt) = hash(x.href, hash(:OMR, h))
Base.hash(x::OMSymbol, h::UInt) = hash(x.name, hash(x.cd, hash(x.cdbase, hash(:OMS, h))))
Base.hash(x::OMForeign, h::UInt) = hash(x.value, hash(x.encoding, hash(:OMFOREIGN, h)))
Base.hash(x::OMAttributePair, h::UInt) = hash(x.value, hash(x.key, h))
Base.hash(x::OMBoundVariable, h::UInt) = hash(x.attributes, hash(x.name, h))
function Base.hash(x::OMApplication, h::UInt)
    hash(x.arguments, hash(x.applicant, hash(x.cdbase, hash(:OMA, h))))
end
function Base.hash(x::OMBinding, h::UInt)
    hash(x.body, hash(x.variables, hash(x.binder, hash(x.cdbase, hash(:OMBIND, h)))))
end
function Base.hash(x::OMError, h::UInt)
    hash(x.arguments, hash(x.head, hash(x.cdbase, hash(:OME, h))))
end
function Base.hash(x::OMAttribution, h::UInt)
    hash(x.object, hash(x.attributes, hash(x.cdbase, hash(:OMATTR, h))))
end
function Base.hash(x::OMObject, h::UInt)
    hash(x.object, hash(x.cdbase, hash(x.version, hash(:OMOBJ, h))))
end

# --- id-sensitive comparison --------------------------------------------------

"""
    isequal_with_ids(a, b) -> Bool

Like `==`, but also requires the `id` attributes to match. Use this when testing
byte fidelity of a round-trip; use `==` when testing mathematical content.

# Examples
```jldoctest
julia> using OpenMath

julia> OMInteger(1; id = "a") == OMInteger(1; id = "b")
true

julia> isequal_with_ids(OMInteger(1; id = "a"), OMInteger(1; id = "b"))
false
```
"""
function isequal_with_ids(a, b)
    a == b || return false
    return _ids(a) == _ids(b)
end

_ids(x::OMObject) = pushfirst!(_ids(x.object), x.id)
function _ids(x::OMOrForeign)
    out = Union{Nothing, String}[]
    walk(n -> push!(out, n.id), x)
    return out
end
