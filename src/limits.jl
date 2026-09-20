# SPDX-License-Identifier: MIT

"""
    OMLimits(; max_depth, max_nodes, max_bytes)

Resource ceilings applied to parsing and to the normalisation passes.

OpenMath travels over SCSCP sockets and in web payloads, so every entry point is
treated as accepting hostile input. The depth ceiling exists specifically so that
deeply nested documents raise [`OpenMathLimitError`](@ref) rather than a
`StackOverflowError`, which Julia cannot reliably catch (REQ-SEC-002).

# Examples
```jldoctest
julia> using OpenMath

julia> limits().max_depth
10000

julia> with_limits(OMLimits(; max_depth = 5)) do
           limits().max_depth
       end
5
```
"""
Base.@kwdef struct OMLimits
    max_depth::Int = 10_000
    max_nodes::Int = 10_000_000
    max_bytes::Int = 1 << 30
end

const _LIMITS = Ref(OMLimits())

"""
    limits() -> OMLimits

The limits in force for the current dynamic scope.

# Examples
```jldoctest
julia> using OpenMath

julia> limits().max_depth
10000
```
"""
limits() = _LIMITS[]

"""
    with_limits(f, l::OMLimits)

Run `f()` with `l` in force, restoring the previous limits afterwards — including
when `f` throws.

# Examples
```jldoctest
julia> using OpenMath

julia> with_limits(OMLimits(; max_depth = 5)) do
           limits().max_depth
       end
5
```
"""
function with_limits(f, l::OMLimits)
    old = _LIMITS[]
    _LIMITS[] = l
    try
        return f()
    finally
        _LIMITS[] = old
    end
end

"""
    check_limit(limit::Symbol, value::Integer, maximum::Integer)

Raise [`OpenMathLimitError`](@ref) when `value` exceeds `maximum`.
"""
@inline function check_limit(limit::Symbol, value::Integer, maximum::Integer)
    value > maximum && throw(OpenMathLimitError(limit, Int(value), Int(maximum)))
    return nothing
end
