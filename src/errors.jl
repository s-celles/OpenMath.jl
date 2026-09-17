# SPDX-License-Identifier: MIT

"""
    OpenMathError

Supertype of every error raised by OpenMath.jl. Parsers guarantee that no other
exception type escapes for well-formed *or* hostile input (REQ-SEC-001).
"""
abstract type OpenMathError <: Exception end

"""
    OpenMathNameError(name, position, what)

A symbol name, variable name, content dictionary name or `cdbase` URI does not
match the production the standard requires (§2.3). `position` is the 1-based index
of the offending character, or `0` when the whole value is at fault.
"""
struct OpenMathNameError <: OpenMathError
    name::String
    position::Int
    what::String
end

function Base.showerror(io::IO, e::OpenMathNameError)
    print(io, "OpenMathNameError: invalid ", e.what, " ", repr(e.name))
    if e.position > 0
        print(io, " at character ", e.position)
        print(io, " (", repr(e.name[nextind(e.name, 0, e.position)]), ")")
    end
    print(io, "; see the OpenMath 2.0 standard §2.3")
    return nothing
end

"""
    OpenMathLimitError(limit, value, maximum)

A configured resource limit was reached. Raised instead of letting the process
exhaust its stack or memory (REQ-SEC-002).
"""
struct OpenMathLimitError <: OpenMathError
    limit::Symbol
    value::Int
    maximum::Int
end

function Base.showerror(io::IO, e::OpenMathLimitError)
    print(io, "OpenMathLimitError: ", e.limit, " exceeded (",
        e.value, " > ", e.maximum, "); raise it with `with_limits`")
    return nothing
end

"""
    OpenMathReferenceError(href, reason)

An `OMR` reference could not be resolved. `reason` is `:cycle` when the referent
dominates the reference, or `:dangling` when no node carries the target `id`.
"""
struct OpenMathReferenceError <: OpenMathError
    href::String
    reason::Symbol
end

function Base.showerror(io::IO, e::OpenMathReferenceError)
    what = e.reason === :cycle ?
           "reference cycle: an OpenMath element may not dominate itself" :
           "dangling reference: no element carries this id"
    print(io, "OpenMathReferenceError: ", what, " (", e.href, ")")
    return nothing
end

"""
    OpenMathConversionError(type, message)

A Julia value has no OpenMath representation, or an OpenMath object has no
representation in the requested Julia type.
"""
struct OpenMathConversionError <: OpenMathError
    type::String
    message::String
end

function OpenMathConversionError(T::Type, msg::AbstractString)
    OpenMathConversionError(string(T), String(msg))
end

function Base.showerror(io::IO, e::OpenMathConversionError)
    print(io, "OpenMathConversionError: ", e.message, " (", e.type, ")")
    return nothing
end

"""
    OpenMathParseError(message, offset, path)

An encoded document could not be decoded. Either `offset` (byte position) or
`path` (element path) locates the failure (REQ-API-007).
"""
struct OpenMathParseError <: OpenMathError
    message::String
    offset::Union{Nothing, Int}
    path::Union{Nothing, String}
end

function OpenMathParseError(msg::AbstractString; offset = nothing, path = nothing)
    OpenMathParseError(String(msg), offset, path)
end

function Base.showerror(io::IO, e::OpenMathParseError)
    print(io, "OpenMathParseError: ", e.message)
    e.offset === nothing || print(io, " at byte ", e.offset)
    e.path === nothing || print(io, " at ", e.path)
    return nothing
end
