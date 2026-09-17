# SPDX-License-Identifier: MIT
#
# Normalisation passes (standard §2.1.4 for cdbase scoping, §3.1.2 for sharing).

# --- cdbase -------------------------------------------------------------------

"""
    resolve_cdbase(x; base = CD_BASE) -> typeof(x)

Push the inherited `cdbase` onto every symbol, and clear it from the composites
that merely carried it. `cdbase` scopes lexically in every encoding, so resolving
it is what makes two objects comparable regardless of where the attribute was
written (REQ-CAN-003).

# Examples
```jldoctest
julia> using OpenMath

julia> a = OMApplication(OMSymbol("mycd", "f"), [OMSymbol("mycd", "g")];
                         cdbase = "http://example.org/cd");

julia> resolve_cdbase(a).applicant.cdbase
"http://example.org/cd"
```
"""
function resolve_cdbase(x::OMOrForeign; base::AbstractString = CD_BASE)
    check_limit(:max_depth, depth(x), limits().max_depth)
    return _resolve(x, String(base))
end

function resolve_cdbase(x::OMObject; base::AbstractString = CD_BASE)
    OMObject(resolve_cdbase(x.object; base = x.cdbase === nothing ? base : x.cdbase),
        x.version, nothing, x.id)
end

_resolve(x::OMLeaf, ::String) = x
_resolve(x::OMForeign, ::String) = x
function _resolve(x::OMSymbol, b::String)
    OMSymbol(x.cdbase === nothing ? b : x.cdbase, x.cd, x.name, x.id)
end

function _resolve(x::OMApplication, b::String)
    nb = x.cdbase === nothing ? b : x.cdbase
    return OMApplication(_resolve(x.applicant, nb),
        OMNode[_resolve(a, nb) for a in x.arguments], nothing, x.id)
end

function _resolve(x::OMError, b::String)
    nb = x.cdbase === nothing ? b : x.cdbase
    return OMError(_resolve(x.head, nb),
        OMOrForeign[_resolve(a, nb) for a in x.arguments], nothing, x.id)
end

function _resolve(x::OMAttribution, b::String)
    nb = x.cdbase === nothing ? b : x.cdbase
    return OMAttribution(OMAttributePair[_resolve_pair(p, nb) for p in x.attributes],
        _resolve(x.object, nb), nothing, x.id)
end

function _resolve(x::OMBinding, b::String)
    nb = x.cdbase === nothing ? b : x.cdbase
    vars = OMBoundVariable[OMBoundVariable(v.name,
                               OMAttributePair[_resolve_pair(p, nb) for p in v.attributes])
                           for v in x.variables]
    return OMBinding(_resolve(x.binder, nb), vars, _resolve(x.body, nb), nothing, x.id)
end

function _resolve_pair(p::OMAttributePair, b::String)
    OMAttributePair(_resolve(p.key, b), _resolve(p.value, b))
end

"""
    minimize_cdbase(x; base = CD_BASE) -> typeof(x)

The inverse of [`resolve_cdbase`](@ref): hoist each `cdbase` to the outermost
object at which it applies, and drop it wherever it repeats what is inherited.
This is what a writer wants, since the standard expects `cdbase` to be emitted
only where it changes (REQ-CAN-004).

# Examples
```jldoctest
julia> using OpenMath

julia> a = OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1)]);

julia> minimize_cdbase(resolve_cdbase(a)) == a
true
```
"""
function minimize_cdbase(x::OMOrForeign; base::AbstractString = CD_BASE)
    check_limit(:max_depth, depth(x), limits().max_depth)
    return _minimize(x, String(base))
end

function minimize_cdbase(x::OMObject; base::AbstractString = CD_BASE)
    OMObject(minimize_cdbase(x.object; base = base), x.version, x.cdbase, x.id)
end

# The unique cdbase used anywhere in a subtree, or `nothing` when the subtree
# uses none or several. A unique one can be hoisted; a mixture cannot.
function _unique_cdbase(x::OMOrForeign)
    found = Ref{Union{Nothing, String}}(nothing)
    mixed = Ref(false)
    walk(x) do n
        n isa OMSymbol || return nothing
        n.cdbase === nothing && return nothing
        if found[] === nothing
            found[] = n.cdbase
        elseif found[] != n.cdbase
            mixed[] = true
        end
        return nothing
    end
    return mixed[] ? nothing : found[]
end

_minimize(x::OMLeaf, ::String) = x
_minimize(x::OMForeign, ::String) = x
function _minimize(x::OMSymbol, b::String)
    OMSymbol(x.cdbase == b ? nothing : x.cdbase, x.cd, x.name, x.id)
end

# For a composite: if the whole subtree agrees on one cdbase that differs from
# what is inherited, carry it here and let every descendant inherit it.
function _hoist(x::OMComposite, b::String)
    u = _unique_cdbase(x)
    (u === nothing || u == b) && return (nothing, b)
    return (u, u)
end

function _minimize(x::OMApplication, b::String)
    here, nb = _hoist(x, b)
    return OMApplication(_minimize(x.applicant, nb),
        OMNode[_minimize(a, nb) for a in x.arguments], here, x.id)
end

function _minimize(x::OMError, b::String)
    here, nb = _hoist(x, b)
    return OMError(_minimize(x.head, nb),
        OMOrForeign[_minimize(a, nb) for a in x.arguments], here, x.id)
end

function _minimize(x::OMAttribution, b::String)
    here, nb = _hoist(x, b)
    return OMAttribution(OMAttributePair[_minimize_pair(p, nb) for p in x.attributes],
        _minimize(x.object, nb), here, x.id)
end

function _minimize(x::OMBinding, b::String)
    here, nb = _hoist(x, b)
    vars = OMBoundVariable[OMBoundVariable(v.name,
                               OMAttributePair[_minimize_pair(p, nb) for p in v.attributes])
                           for v in x.variables]
    return OMBinding(_minimize(x.binder, nb), vars, _minimize(x.body, nb), here, x.id)
end

function _minimize_pair(p::OMAttributePair, b::String)
    OMAttributePair(_minimize(p.key, b), _minimize(p.value, b))
end

# --- attributions -------------------------------------------------------------

"""
    collapse_attributions(x) -> typeof(x)

Flatten `OMATTR(OMATTR(o, a), b)` into `OMATTR(o, [a…, b…])`, throughout `x`.
Innermost attributes come first, preserving the order in which they apply
(REQ-CAN-005).

Only an attribution that carries no `cdbase` of its own is merged, since merging
one that does would change what its attributes mean. [`canonicalize`](@ref)
therefore resolves `cdbase` before collapsing, so that the normal form does not
depend on where the base was written.

# Examples
```jldoctest
julia> using OpenMath

julia> k1 = OMAttributePair(OMS"ecc#a", OMInteger(1));

julia> k2 = OMAttributePair(OMS"ecc#b", OMInteger(2));

julia> collapse_attributions(OMAttribution([k2], OMAttribution([k1], OMVariable("x")))).attributes == [k1, k2]
true
```
"""
function collapse_attributions(x::OMOrForeign)
    check_limit(:max_depth, depth(x), limits().max_depth)
    return _collapse(x)
end

function collapse_attributions(x::OMObject)
    OMObject(collapse_attributions(x.object), x.version, x.cdbase, x.id)
end

_collapse(x::OMLeaf) = x
_collapse(x::OMForeign) = x

function _collapse(x::OMApplication)
    OMApplication(
        _collapse(x.applicant), OMNode[_collapse(a) for a in x.arguments], x.cdbase, x.id)
end

function _collapse(x::OMError)
    OMError(
        x.head, OMOrForeign[_collapse(a) for a in x.arguments], x.cdbase, x.id)
end

function _collapse(x::OMBinding)
    OMBinding(
        _collapse(x.binder),
        OMBoundVariable[OMBoundVariable(v.name,
                            OMAttributePair[_collapse_pair(p) for p in v.attributes])
                        for v in x.variables],
        _collapse(x.body), x.cdbase, x.id)
end

function _collapse(x::OMAttribution)
    attrs = OMAttributePair[]
    node = _collapse(x.object)
    while node isa OMAttribution && node.cdbase === nothing
        prepend!(attrs, node.attributes)
        node = node.object
    end
    append!(attrs, (_collapse_pair(p) for p in x.attributes))
    return OMAttribution(attrs, node, x.cdbase, x.id)
end

_collapse_pair(p::OMAttributePair) = OMAttributePair(p.key, _collapse(p.value))

# --- structure sharing --------------------------------------------------------

"""
    expand_references(x) -> typeof(x)

Replace every [`OMReference`](@ref) by a structural copy of the element carrying
the matching `id` (standard §3.1.2).

Raises [`OpenMathReferenceError`](@ref) on a cycle — "an OpenMath element may not
dominate itself" — or on a dangling reference, and [`OpenMathLimitError`](@ref)
if expansion would exceed `max_nodes` (REQ-CAN-008).

# Examples
```jldoctest
julia> using OpenMath

julia> shared = OMApplication(OMS"arith1#plus", [OMInteger(1)]; id = "s");

julia> e = expand_references(OMApplication(OMS"arith1#times",
                                           [shared, OMReference("#s")]));

julia> e.arguments[2] == shared
true
```
"""
function expand_references(x::OMOrForeign)
    targets = Dict{String, OMOrForeign}()
    walk(n -> (n.id === nothing || (targets[n.id] = n); nothing), x)
    isempty(targets) && !any(n -> n isa OMReference, collect_nodes(x)) && return x
    budget = Ref(0)
    return _expand(x, targets, String[], budget, limits().max_nodes)
end

function expand_references(x::OMObject)
    OMObject(expand_references(x.object), x.version, x.cdbase, x.id)
end

function _expand(x::OMOrForeign, targets, ancestors, budget, maxnodes)
    budget[] += 1
    check_limit(:max_nodes, budget[], maxnodes)

    if x isa OMReference
        target = reference_target(x)
        # An external reference names another document and cannot be resolved
        # without fetching it, so it survives expansion untouched. Treating it as
        # broken would make every document that cites another one unusable.
        target === nothing && return x
        target in ancestors && throw(OpenMathReferenceError(x.href, :cycle))
        haskey(targets, target) || throw(OpenMathReferenceError(x.href, :dangling))
        return _expand(targets[target], targets, push!(copy(ancestors), target),
            budget, maxnodes)
    end

    inner = x.id === nothing ? ancestors : push!(copy(ancestors), x.id)
    return _rebuild(x, n -> _expand(n, targets, inner, budget, maxnodes))
end

# Rebuild a composite with `g` applied to each child; leaves are returned as is.
_rebuild(x::OMLeaf, _) = x
_rebuild(x::OMForeign, _) = x

function _rebuild(x::OMApplication, g)
    OMApplication(
        _as_node(g(x.applicant)), OMNode[_as_node(g(a)) for a in x.arguments],
        x.cdbase, x.id)
end

function _rebuild(x::OMError, g)
    OMError(
        _as_symbol(g(x.head)), OMOrForeign[g(a) for a in x.arguments], x.cdbase, x.id)
end

function _rebuild(x::OMAttribution, g)
    OMAttribution(
        OMAttributePair[OMAttributePair(_as_symbol(g(p.key)), g(p.value))
                        for p in x.attributes],
        _as_node(g(x.object)), x.cdbase, x.id)
end

function _rebuild(x::OMBinding, g)
    OMBinding(
        _as_node(g(x.binder)),
        OMBoundVariable[OMBoundVariable(v.name,
                            OMAttributePair[OMAttributePair(_as_symbol(g(p.key)), g(p.value))
                                            for p in v.attributes]) for v in x.variables],
        _as_node(g(x.body)), x.cdbase, x.id)
end

function _as_node(x)
    x isa OMNode && return x
    throw(OpenMathReferenceError("", :foreign_in_object_position))
end

function _as_symbol(x)
    x isa OMSymbol && return x
    throw(OpenMathReferenceError("", :non_symbol_in_symbol_position))
end

# --- canonical form -----------------------------------------------------------

"""
    strip_ids(x) -> typeof(x)

Drop every `id`. After [`expand_references`](@ref) they anchor nothing.
"""
strip_ids(x::OMOrForeign) = _rebuild_stripped(x)
strip_ids(x::OMObject) = OMObject(strip_ids(x.object), x.version, x.cdbase, nothing)

_rebuild_stripped(x::OMInteger) = OMInteger(x.value, nothing)
_rebuild_stripped(x::OMFloat) = OMFloat(x.value, nothing)
_rebuild_stripped(x::OMString) = OMString(x.value, nothing)
_rebuild_stripped(x::OMBytes) = OMBytes(x.value, nothing)
_rebuild_stripped(x::OMVariable) = OMVariable(x.name, nothing)
_rebuild_stripped(x::OMSymbol) = OMSymbol(x.cdbase, x.cd, x.name, nothing)
_rebuild_stripped(x::OMReference) = OMReference(x.href, nothing)
_rebuild_stripped(x::OMForeign) = OMForeign(x.encoding, x.value, nothing)

function _rebuild_stripped(x::OMApplication)
    OMApplication(
        _rebuild_stripped(x.applicant),
        OMNode[_rebuild_stripped(a) for a in x.arguments], x.cdbase, nothing)
end

function _rebuild_stripped(x::OMError)
    OMError(
        _rebuild_stripped(x.head),
        OMOrForeign[_rebuild_stripped(a) for a in x.arguments], x.cdbase, nothing)
end

function _rebuild_stripped(x::OMAttribution)
    OMAttribution(
        OMAttributePair[OMAttributePair(_rebuild_stripped(p.key), _rebuild_stripped(p.value))
                        for p in x.attributes],
        _rebuild_stripped(x.object), x.cdbase, nothing)
end

function _rebuild_stripped(x::OMBinding)
    OMBinding(
        _rebuild_stripped(x.binder),
        OMBoundVariable[OMBoundVariable(v.name,
                            OMAttributePair[OMAttributePair(_rebuild_stripped(p.key),
                                                _rebuild_stripped(p.value))
                                            for p in v.attributes]) for v in x.variables],
        _rebuild_stripped(x.body), x.cdbase, nothing)
end

"""
    canonicalize(x; base = CD_BASE) -> typeof(x)

The normal form used for comparison: references expanded, attributions
flattened, `cdbase` resolved onto every symbol, `id`s dropped.

`canonicalize` is idempotent (REQ-CAN-002), which the property layer checks on
generated objects.

# Examples
```jldoctest
julia> using OpenMath

julia> canonicalize(OMApplication(OMS"arith1#plus", [OMInteger(1)])).applicant.cdbase
"http://www.openmath.org/cd"
```
"""
function canonicalize(x::OMOrForeign; base::AbstractString = CD_BASE)
    check_limit(:max_depth, depth(x), limits().max_depth)
    y = expand_references(x)
    check_limit(:max_depth, depth(y), limits().max_depth)
    # Resolving before collapsing is load-bearing, not a matter of taste.
    # `collapse_attributions` may only merge an `OMATTR` that carries no `cdbase`
    # of its own, so collapsing first makes the normal form depend on *where* the
    # base happened to be written: `OMATTR(OMATTR(x, a), b)` flattens when the
    # inner node has no base and does not when an equivalent document put one
    # there. Resolving first clears every composite base, so nesting collapses
    # uniformly. The property layer found this; see P5 in test/property.
    y = _resolve(y, String(base))
    y = _collapse(y)
    return _rebuild_stripped(y)
end

function canonicalize(x::OMObject; base::AbstractString = CD_BASE)
    OMObject(canonicalize(x.object;
            base = x.cdbase === nothing ? base : x.cdbase),
        x.version, nothing, nothing)
end
