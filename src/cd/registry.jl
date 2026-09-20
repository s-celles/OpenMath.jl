# SPDX-License-Identifier: MIT
#
# The symbol registry: `(cdbase, cd)` → dictionary, and the validation that needs
# it.
#
# The dictionaries are not shipped with this package (REQ-CD-003, decision D4).
# A registry is therefore empty until something loads one, and says so plainly
# rather than reaching the network or pretending an unknown symbol is an invalid
# one.

"""
    CDRegistry()

A collection of Content Dictionaries, keyed by `(cdbase, cd)` — the pair that
identifies a dictionary, since the same name under a different base is a
different dictionary (standard §2.1.4).

Populate it with [`register!`](@ref) or [`load_cd_directory`](@ref).

# Examples
```jldoctest
julia> using OpenMath

julia> OpenMath.isempty_registry(CDRegistry())
true
```
"""
struct CDRegistry
    dictionaries::Dict{Tuple{String, String}, ContentDictionary}
    signatures::Dict{Tuple{String, String}, STSSignatures}
end

function CDRegistry()
    CDRegistry(Dict{Tuple{String, String}, ContentDictionary}(),
        Dict{Tuple{String, String}, STSSignatures}())
end

"""
    isempty_registry(reg) -> Bool

Whether `reg` holds no dictionaries. Worth distinguishing from "this symbol is
unknown": with an empty registry every symbol is unknown, which says nothing.
"""
isempty_registry(reg::CDRegistry) = isempty(reg.dictionaries)

function Base.show(io::IO, reg::CDRegistry)
    if isempty_registry(reg)
        print(io, "CDRegistry(empty — the Content Dictionaries are not shipped with ",
            "this package; run `just corpus-fetch` or call `load_cd_directory`)")
    else
        print(io, "CDRegistry(", length(reg.dictionaries), " dictionaries, ",
            sum(length(cd.definitions) for (_, cd) in reg.dictionaries), " symbols)")
    end
    return nothing
end

"""
    register!(reg, cd::ContentDictionary)
    register!(reg, sts::STSSignatures, cdbase)

Add a dictionary, or a set of signatures, to `reg`.
"""
function register!(reg::CDRegistry, cd::ContentDictionary)
    reg.dictionaries[(cd.cdbase, cd.name)] = cd
    return reg
end

function register!(reg::CDRegistry, sts::STSSignatures, cdbase::AbstractString = CD_BASE)
    reg.signatures[(String(cdbase), sts.cd)] = sts
    return reg
end

"""
    load_cd_directory(dir) -> CDRegistry
    load_cd_directory!(reg, dir) -> CDRegistry

Parse every `.ocd` file in `dir` into a registry.

# Examples
```jldoctest
julia> using OpenMath

julia> OpenMath.isempty_registry(load_cd_directory(mktempdir()))   # no .ocd there
true
```
"""
load_cd_directory(dir::AbstractString) = load_cd_directory!(CDRegistry(), dir)

"""
    load_cd_directory!(reg, dir) -> CDRegistry

Parse every `.ocd` file in `dir` into `reg`, which is returned.

The mutating form is the one to use when several directories make up one
registry — the official set, the contributed one and a private one, say.

# Examples
```jldoctest
julia> using OpenMath

julia> reg = CDRegistry();

julia> load_cd_directory!(reg, mktempdir()) === reg
true
```
"""
function load_cd_directory!(reg::CDRegistry, dir::AbstractString)
    isdir(dir) || throw(ArgumentError("not a directory: $(repr(String(dir)))"))
    for f in sort!(readdir(dir; join = true))
        endswith(f, ".ocd") || continue
        register!(reg, parse_cd(f))
    end
    return reg
end

"""
    load_sts_directory!(reg, dir; cdbase = CD_BASE) -> CDRegistry

Parse every `.sts` file in `dir` and attach the signatures to `reg`.

# Examples
```jldoctest
julia> using OpenMath

julia> reg = CDRegistry();

julia> load_sts_directory!(reg, mktempdir()) === reg
true
```
"""
function load_sts_directory!(reg::CDRegistry, dir::AbstractString;
        cdbase::AbstractString = CD_BASE)
    isdir(dir) || throw(ArgumentError("not a directory: $(repr(String(dir)))"))
    for f in sort!(readdir(dir; join = true))
        endswith(f, ".sts") || continue
        register!(reg, parse_sts(f), cdbase)
    end
    return reg
end

# The base a symbol resolves against: its own if it has one, otherwise the
# official default — the same rule `resolve_cdbase` applies, so the registry and
# the pass cannot disagree.
_effective_base(s::OMSymbol) = s.cdbase === nothing ? CD_BASE : s.cdbase

"""
    lookup(reg, symbol) -> Union{Nothing,CDDefinition}

The definition of `symbol`, or `nothing` when no loaded dictionary defines it.

`nothing` is an answer, not an error: a symbol from a dictionary this registry
has never seen is an ordinary occurrence, and an empty registry answers `nothing`
for everything.

# Examples
```jldoctest
julia> using OpenMath

julia> reg = OpenMath.CDRegistry();

julia> lookup(reg, OMS"arith1#plus") === nothing
true
```
"""
function lookup(reg::CDRegistry, s::OMSymbol)
    cd = get(reg.dictionaries, (_effective_base(s), s.cd), nothing)
    cd === nothing && return nothing
    return get(cd.definitions, s.name, nothing)
end

"""
    describe(reg, symbol) -> String

The prose description of `symbol`, or `""` when it is not defined here.

# Examples
```jldoctest
julia> using OpenMath

julia> describe(CDRegistry(), OMS"arith1#plus")   # nothing is loaded
""
```
"""
function describe(reg::CDRegistry, s::OMSymbol)
    d = lookup(reg, s)
    return d === nothing ? "" : d.description
end

"""
    signature(reg, symbol) -> Union{Nothing,OMObject}

The Small Type System signature of `symbol`, itself an OpenMath object, or
`nothing` when none is loaded.

# Examples
```jldoctest
julia> using OpenMath

julia> signature(CDRegistry(), OMS"arith1#plus") === nothing
true
```
"""
function signature(reg::CDRegistry, s::OMSymbol)
    sts = get(reg.signatures, (_effective_base(s), s.cd), nothing)
    sts === nothing && return nothing
    return get(sts.signatures, s.name, nothing)
end

"""
    arity(reg, symbol) -> Union{Nothing,Int}

How many arguments `symbol` takes, or `nothing` when it is n-ary or has no
signature. See [`sts_arity`](@ref).

# Examples
```jldoctest
julia> using OpenMath

julia> arity(CDRegistry(), OMS"arith1#plus") === nothing
true
```
"""
function arity(reg::CDRegistry, s::OMSymbol)
    sig = signature(reg, s)
    return sig === nothing ? nothing : sts_arity(sig)
end

"""
    validate_against_cds(x, reg) -> Vector{OMValidationIssue}

Check every symbol in `x` against `reg`: that its dictionary is known, that the
dictionary defines it, and that an application of it respects the arity its
signature declares (REQ-VAL-009).

This is deliberately separate from [`validate`](@ref). A document using a private
dictionary is perfectly well formed; it is simply not resolvable here, and
conflating the two would make every private extension look broken.

# Examples
```jldoctest
julia> using OpenMath

julia> reg = OpenMath.CDRegistry();

julia> only(validate_against_cds(OMS"arith1#plus", reg)).code
:unknown_cd
```
"""
function validate_against_cds(x::Union{OMOrForeign, OMObject}, reg::CDRegistry)
    issues = OMValidationIssue[]
    reported_cds = Set{Tuple{String, String}}()

    walk(x) do node
        if node isa OMSymbol
            key = (_effective_base(node), node.cd)
            if !haskey(reg.dictionaries, key)
                # Once per dictionary, not once per symbol: a document using a
                # private dictionary would otherwise report an issue per node.
                if !(key in reported_cds)
                    push!(reported_cds, key)
                    push!(issues,
                        OMValidationIssue(:unknown_cd, "",
                            "no loaded dictionary $(repr(node.cd)) under $(repr(key[1]))",
                            "omstd20 §2.1.4"))
                end
            elseif lookup(reg, node) === nothing
                push!(issues,
                    OMValidationIssue(:unknown_symbol, "",
                        "$(node.cd) does not define $(repr(node.name))", "omstd20 §4.2"))
            end
        elseif node isa OMApplication && node.applicant isa OMSymbol
            n = arity(reg, node.applicant)
            if n !== nothing && n != length(node.arguments)
                push!(issues,
                    OMValidationIssue(:wrong_arity, "",
                        "$(node.applicant.cd)#$(node.applicant.name) takes $(n) " *
                        "argument$(n == 1 ? "" : "s"), applied to $(length(node.arguments))",
                        "omstd20 §4.3"))
            end
        end
        return nothing
    end

    return issues
end
