# SPDX-License-Identifier: MIT
#
# Validation of the constraints the type system cannot express (REQ-VAL-001).
#
# The grammar constraints of standard §2.1.1 — an application has an applicant,
# an error head is a symbol, bound variables are variables, foreign content only
# occurs in legal positions — are enforced by the type signatures in `types.jl`
# instead, which is strictly stronger. What remains here is everything about the
# *graph*: reference integrity, id uniqueness, URI syntax and size.
#
# `validate` reports; it never throws (REQ-VAL-008).

"""
    OMValidationIssue(code, path, message, spec)

One well-formedness problem found by [`validate`](@ref). `path` locates the
offending sub-object, `spec` cites the clause it violates.
"""
struct OMValidationIssue
    code::Symbol
    path::String
    message::String
    spec::String
end

function Base.show(io::IO, i::OMValidationIssue)
    print(io, "OMValidationIssue(:", i.code, " at ", isempty(i.path) ? "/" : i.path,
        ": ", i.message, " [", i.spec, "])")
    return nothing
end

# Children paired with the path segment that reaches them, so an issue can say
# where it is rather than merely that it exists.
_labelled_children(::OMLeaf) = Tuple{String, OMOrForeign}[]
_labelled_children(::OMForeign) = Tuple{String, OMOrForeign}[]

function _labelled_children(x::OMApplication)
    out = Tuple{String, OMOrForeign}[("/applicant", x.applicant)]
    for (i, a) in enumerate(x.arguments)
        push!(out, ("/arguments[$i]", a))
    end
    return out
end

function _labelled_children(x::OMError)
    out = Tuple{String, OMOrForeign}[("/head", x.head)]
    for (i, a) in enumerate(x.arguments)
        push!(out, ("/arguments[$i]", a))
    end
    return out
end

function _labelled_children(x::OMAttribution)
    out = Tuple{String, OMOrForeign}[]
    for (i, p) in enumerate(x.attributes)
        push!(out, ("/attributes[$i]/key", p.key), ("/attributes[$i]/value", p.value))
    end
    push!(out, ("/object", x.object))
    return out
end

function _labelled_children(x::OMBinding)
    out = Tuple{String, OMOrForeign}[("/binder", x.binder)]
    for (i, v) in enumerate(x.variables), (j, p) in enumerate(v.attributes)

        push!(out, ("/variables[$i]/attributes[$j]/key", p.key),
            ("/variables[$i]/attributes[$j]/value", p.value))
    end
    push!(out, ("/body", x.body))
    return out
end

"""
    validate(x) -> Vector{OMValidationIssue}

Every well-formedness problem of `x`, in document order. An empty result means
`x` is well formed. This function terminates on every input and never throws.

# Examples
```jldoctest
julia> using OpenMath

julia> isempty(validate(OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1)])))
true

julia> only(validate(OMApplication(OMSymbol("arith1", "plus"),
                                   [OMReference("#nowhere")]))).code
:dangling_reference
```
"""
function validate(x::Union{OMOrForeign, OMObject})
    root = x isa OMObject ? x.object : x
    issues = OMValidationIssue[]
    lim = limits()

    # Pass 1 — collect ids, flag duplicates.
    ids = Dict{String, Int}()
    seen = 0
    walk(root) do n
        seen += 1
        n.id === nothing && return nothing
        ids[n.id] = get(ids, n.id, 0) + 1
        return nothing
    end

    # Pass 2 — the graph, with an ancestor-id set for cycle detection and a path.
    stack = Tuple{String, OMOrForeign, Vector{String}, Int}[("", root, String[], 1)]
    reported_dup = Set{String}()
    d = 0
    while !isempty(stack)
        path, node, ancestors, level = pop!(stack)
        d = max(d, level)

        if node.id !== nothing
            if ids[node.id] > 1 && !(node.id in reported_dup)
                push!(reported_dup, node.id)
                push!(issues,
                    OMValidationIssue(:duplicate_id, path,
                        "id $(repr(node.id)) is used $(ids[node.id]) times",
                        "omstd20 §3.1.2"))
            end
        end

        if node isa OMReference
            # Only an internal reference can dangle. An external one names another
            # document (standard §3.1.2, and tokens 30 vs 31 in the binary
            # encoding), so its target is not expected to be here.
            target = reference_target(node)
            if target === nothing
                # external: nothing to check without fetching
            elseif target in ancestors
                push!(issues,
                    OMValidationIssue(:reference_cycle, path,
                        "reference to $(repr(node.href)) is dominated by its own referent",
                        "omstd20 §3.1.2"))
            elseif !haskey(ids, target)
                push!(issues,
                    OMValidationIssue(:dangling_reference, path,
                        "no element carries the id $(repr(target))",
                        "omstd20 §3.1.2"))
            end
        end

        cdb = _cdbase_of(node)
        if cdb !== nothing && !isvalidcdbase(cdb)
            push!(issues,
                OMValidationIssue(:invalid_cdbase, path,
                    "cdbase $(repr(cdb)) is not an absolute URI", "omstd20 §2.1.4"))
        end

        inner = node.id === nothing ? ancestors : push!(copy(ancestors), node.id)
        cs = _labelled_children(node)
        for i in length(cs):-1:1
            seg, child = cs[i]
            push!(stack, (path * seg, child, inner, level + 1))
        end
    end

    if d > lim.max_depth
        push!(issues,
            OMValidationIssue(:max_depth_exceeded, "",
                "depth $d exceeds the configured maximum of $(lim.max_depth)",
                "OpenMath.jl REQ-SEC-002"))
    end
    if seen > lim.max_nodes
        push!(issues,
            OMValidationIssue(:max_nodes_exceeded, "",
                "node count $seen exceeds the configured maximum of $(lim.max_nodes)",
                "OpenMath.jl REQ-SEC-004"))
    end

    sort!(issues; by = i -> (i.path, String(i.code)))
    return issues
end

_cdbase_of(x::OMSymbol) = x.cdbase
_cdbase_of(x::OMApplication) = x.cdbase
_cdbase_of(x::OMBinding) = x.cdbase
_cdbase_of(x::OMError) = x.cdbase
_cdbase_of(x::OMAttribution) = x.cdbase
_cdbase_of(::OMOrForeign) = nothing

"""
    isvalid_openmath(x) -> Bool

Whether [`validate`](@ref) finds no problem with `x`.
"""
isvalid_openmath(x::Union{OMOrForeign, OMObject}) = isempty(validate(x))
