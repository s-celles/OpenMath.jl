# SPDX-License-Identifier: MIT
#
# Uniform traversal. Every function here uses an explicit stack: OpenMath objects
# arrive from the network and may be arbitrarily deep, and a StackOverflowError
# cannot be caught reliably in Julia (REQ-SEC-003).

"""
    kind(x) -> Symbol

The OpenMath tag of `x`, as the standard names it: `:OMI`, `:OMF`, `:OMSTR`,
`:OMB`, `:OMV`, `:OMS`, `:OMA`, `:OMBIND`, `:OME`, `:OMATTR`, `:OMFOREIGN` or
`:OMR`.

# Examples
```jldoctest
julia> using OpenMath

julia> kind(OMInteger(1)), kind(OMSymbol("arith1", "plus"))
(:OMI, :OMS)
```
"""
kind(::OMInteger) = :OMI
kind(::OMFloat) = :OMF
kind(::OMString) = :OMSTR
kind(::OMBytes) = :OMB
kind(::OMVariable) = :OMV
kind(::OMSymbol) = :OMS
kind(::OMApplication) = :OMA
kind(::OMBinding) = :OMBIND
kind(::OMError) = :OME
kind(::OMAttribution) = :OMATTR
kind(::OMForeign) = :OMFOREIGN
kind(::OMReference) = :OMR

"""
    children(x) -> Vector{OMOrForeign}

The immediate sub-objects of `x`, in document order. Leaves have none.
"""
children(::OMLeaf) = OMOrForeign[]
children(::OMForeign) = OMOrForeign[]

children(x::OMApplication) = OMOrForeign[x.applicant; x.arguments]
children(x::OMError) = OMOrForeign[x.head; x.arguments]

function children(x::OMAttribution)
    out = OMOrForeign[]
    for a in x.attributes
        push!(out, a.key, a.value)
    end
    push!(out, x.object)
    return out
end

function children(x::OMBinding)
    out = OMOrForeign[x.binder]
    for v in x.variables, a in v.attributes

        push!(out, a.key, a.value)
    end
    push!(out, x.body)
    return out
end

children(x::OMObject) = OMOrForeign[x.object]

"""
    walk(f, x)

Apply `f` to `x` and to every sub-object, in pre-order document order.

# Examples
```jldoctest
julia> using OpenMath

julia> seen = Symbol[];

julia> walk(n -> push!(seen, kind(n)),
            OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1)]));

julia> seen
3-element Vector{Symbol}:
 :OMA
 :OMS
 :OMI
```
"""
function walk(f, x::Union{OMOrForeign, OMObject})
    stack = OMOrForeign[x isa OMObject ? x.object : x]
    while !isempty(stack)
        node = pop!(stack)
        f(node)
        cs = children(node)
        for i in length(cs):-1:1
            push!(stack, cs[i])
        end
    end
    return nothing
end

"""
    collect_nodes(x) -> Vector{OMOrForeign}

Every sub-object of `x` including `x` itself, in pre-order.
"""
function collect_nodes(x::Union{OMOrForeign, OMObject})
    out = OMOrForeign[]
    walk(n -> push!(out, n), x)
    return out
end

"""
    count_nodes(x) -> Int

The number of objects in `x`, counting `x` itself.

# Examples
```jldoctest
julia> using OpenMath

julia> count_nodes(OMApplication(OMSymbol("arith1", "plus"),
                                 [OMInteger(1), OMInteger(2)]))
4
```
"""
function count_nodes(x::Union{OMOrForeign, OMObject})
    n = 0
    walk(_ -> (n += 1), x)
    return n
end

"""
    depth(x) -> Int

The length of the longest path from `x` to a leaf, counting both ends.
"""
function depth(x::Union{OMOrForeign, OMObject})
    root = x isa OMObject ? x.object : x
    best = 0
    stack = Tuple{OMOrForeign, Int}[(root, 1)]
    while !isempty(stack)
        node, d = pop!(stack)
        d > best && (best = d)
        for c in children(node)
            push!(stack, (c, d + 1))
        end
    end
    return best
end

"""
    map_openmath(f, x)

Rebuild `x` bottom-up, replacing every sub-object `n` by `f(n)` after its own
children have been rebuilt.

The recursion is bounded by the configured `max_depth`, which is checked first,
so this cannot overflow the native stack (REQ-SEC-002).
"""
function map_openmath(f, x::OMOrForeign)
    check_limit(:max_depth, depth(x), limits().max_depth)
    return _map_checked(f, x)
end

_map_checked(f, x::OMLeaf) = f(x)
_map_checked(f, x::OMForeign) = f(x)

function _map_checked(f, x::OMApplication)
    f(OMApplication(
        _map_node(f, x.applicant), OMNode[_map_node(f, a) for a in x.arguments],
        x.cdbase, x.id))
end

function _map_checked(f, x::OMError)
    f(OMError(
        _map_symbol(f, x.head), OMOrForeign[_map_checked(f, a) for a in x.arguments],
        x.cdbase, x.id))
end

function _map_checked(f, x::OMAttribution)
    f(OMAttribution(
        OMAttributePair[_map_pair(f, p) for p in x.attributes],
        _map_node(f, x.object), x.cdbase, x.id))
end

function _map_checked(f, x::OMBinding)
    f(OMBinding(
        _map_node(f, x.binder),
        OMBoundVariable[OMBoundVariable(v.name,
                            OMAttributePair[_map_pair(f, p) for p in v.attributes])
                        for v in x.variables],
        _map_node(f, x.body), x.cdbase, x.id))
end

function _map_pair(f, p::OMAttributePair)
    OMAttributePair(_map_symbol(f, p.key), _map_checked(f, p.value))
end

function _map_node(f, x::OMNode)
    r = _map_checked(f, x)
    r isa OMNode || throw(OpenMathConversionError(typeof(r),
        "map_openmath produced foreign content in an object position"))
    return r
end

function _map_symbol(f, x::OMSymbol)
    r = _map_checked(f, x)
    r isa OMSymbol || throw(OpenMathConversionError(typeof(r),
        "map_openmath produced a non-symbol in a symbol position"))
    return r
end
