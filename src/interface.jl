# SPDX-License-Identifier: MIT
#
# The conversion extension points (REQ-CVT-001, REQ-CVT-002). A third-party type
# becomes serialisable by adding a `to_openmath` method; nothing else is needed
# and no subtyping is required.

"""
    to_openmath(x) -> OMNode

The OpenMath representation of the Julia value `x`.

Extend by dispatch to make your own types serialisable:

```jldoctest
julia> using OpenMath

julia> struct Celsius; value::Float64; end

julia> OpenMath.to_openmath(c::Celsius) =
           OMS"http://example.org/cd#units#celsius"(to_openmath(c.value));

julia> to_openmath(Celsius(21.5))
OMA(OMS(http://example.org/cd#units#celsius), OMF(21.5))
```
"""
function to_openmath end

"""
    to_julia(x) -> Any
    to_julia(::Type{T}, x) -> T

The Julia value denoted by the OpenMath object `x`, using the built-in
correspondence. Extend by dispatch alongside [`to_openmath`](@ref).

Deliberately not a `Base.convert` method: Julia calls `convert` implicitly, when
a typed field or container is filled, so an object read from an untrusted source
could be converted without anyone asking for it.

# Examples
```jldoctest
julia> using OpenMath

julia> to_julia(OMInteger(7))
7

julia> to_julia(Float64, OMInteger(7))
7.0
```
"""
function to_julia end

to_openmath(x::OMNode) = x

# Bool is an Integer in Julia, so it must be matched first: the standard maps
# truth values to logic1, not to OMI.
to_openmath(x::Bool) = x ? OMSymbol("logic1", "true") : OMSymbol("logic1", "false")
to_openmath(x::Integer) = OMInteger(x)
to_openmath(x::AbstractFloat) = OMFloat(x)
to_openmath(x::AbstractString) = OMString(x)
to_openmath(x::Symbol) = OMVariable(String(x))
to_openmath(x::AbstractVector{UInt8}) = OMBytes(x)

function to_openmath(x::Rational)
    OMSymbol("nums1", "rational")(
        to_openmath(numerator(x)), to_openmath(denominator(x)))
end

function to_openmath(x::Complex)
    OMSymbol("nums1", "complex_cartesian")(
        to_openmath(real(x)), to_openmath(imag(x)))
end

function to_openmath(x::AbstractVector)
    OMSymbol("linalg2", "vector")((to_openmath(e) for e in x)...)
end

function to_openmath(x::AbstractMatrix)
    OMSymbol("linalg2", "matrix")(
        (OMSymbol("linalg2", "matrixrow")((to_openmath(e) for e in view(x, i, :))...)
    for i in axes(x, 1))...)
end

to_openmath(::Nothing) = OMSymbol("nums1", "NaN")

function to_openmath(x)
    throw(OpenMathConversionError(typeof(x),
        "no to_openmath method; define `OpenMath.to_openmath(::$(typeof(x)))`"))
end

# --- back ---------------------------------------------------------------------

to_julia(x::OMInteger) = x.value
to_julia(x::OMFloat) = x.value
to_julia(x::OMString) = x.value
to_julia(x::OMBytes) = x.value
to_julia(x::OMVariable) = Symbol(x.name)
to_julia(x::OMObject) = to_julia(x.object)

# Symbols and applications are where a *vocabulary* is needed rather than a type
# correspondence, so both go through the phrasebook in force. That is what makes
# the vocabulary replaceable (REQ-PHR-001) without `to_julia` growing a
# keyword argument that every caller would have to thread through.
to_julia(x::OMSymbol) = interpret(current_phrasebook(), x)
to_julia(x::OMApplication) = interpret(current_phrasebook(), x)

function to_julia(x::Union{OMOrForeign, OMObject})
    throw(OpenMathConversionError(typeof(x),
        "no to_julia method for $(kind(x))"))
end

to_julia(::Type{T}, x) where {T} = convert(T, to_julia(x))
