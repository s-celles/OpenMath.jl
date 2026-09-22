# SPDX-License-Identifier: MIT
#
# The Content Dictionary format (`.ocd`) and the Small Type System signature
# format (`.sts`).
#
# Both are XML, and both embed complete `<OMOBJ>` documents, so this reuses the
# tokenizer from `src/xml/` and hands the embedded documents to `read_xml`. No new
# parsing machinery, and the embedded objects get exactly the same treatment — the
# same limits, the same errors, the same refusal to resolve entities — as any
# other document this package reads.

"""
    CDDefinition

One symbol defined by a Content Dictionary: its role, its prose description, the
formal mathematical properties (`FMP`) that constrain it, and its examples. The
properties and examples are ordinary OpenMath documents.

# Examples
```jldoctest
julia> using OpenMath

julia> fieldnames(CDDefinition)
(:name, :role, :description, :properties, :examples)
```
"""
struct CDDefinition
    name::String
    role::String
    description::String
    properties::Vector{OMObject}
    examples::Vector{OMObject}
end

Base.show(io::IO, d::CDDefinition) = print(io, "CDDefinition(", d.name, ", ", d.role, ")")

"""
    ContentDictionary

A parsed Content Dictionary. `cdbase` falls back to [`CD_BASE`](@ref) when the
file declares none, because that is what an unqualified symbol resolves against.

# Examples
```jldoctest
julia> using OpenMath

julia> fieldnames(ContentDictionary)[1:3]
(:name, :cdbase, :status)
```
"""
struct ContentDictionary
    name::String
    cdbase::String
    status::String
    version::String
    revision::String
    description::String
    definitions::Dict{String, CDDefinition}
end

function Base.show(io::IO, cd::ContentDictionary)
    print(io, "ContentDictionary(", cd.name,
        ", ", length(cd.definitions), " definitions, ", cd.status, ")")
end

"""
    STSSignatures

The signatures a `.sts` file declares for one dictionary. Each signature is
itself an OpenMath object, built from the `sts` Content Dictionary.

# Examples
```jldoctest
julia> using OpenMath

julia> fieldnames(STSSignatures)
(:cd, :signatures)
```
"""
struct STSSignatures
    cd::String
    signatures::Dict{String, OMObject}
end

function Base.show(io::IO, s::STSSignatures)
    print(io, "STSSignatures(", s.cd, ", ",
        length(s.signatures), " signatures)")
end

function _cderr(msg::AbstractString, at::Union{Nothing, Int} = nothing)
    throw(OpenMathParseError(msg; offset = at))
end

# Capture the full source of the element whose start tag was just returned,
# including its own tags, and leave the parser positioned after it. The
# tokenizer owns how that is computed — this used to read `p.data` and `p.pos`,
# which only worked because one particular tokenizer tracked a byte position.
_element_source(p::XMLPullParser, ev::XMLStartElement) = element_source!(p, ev)

function _maybe_file(source::AbstractString, ext::AbstractString)
    (endswith(source, ext) && isfile(source)) ? read(source, String) : String(source)
end

# Elements whose character data we keep. Everything else is skipped, including
# `CDComment`, which holds the licence text.
const _CD_TEXT = ("CDName", "CDBase", "CDStatus", "CDVersion", "CDRevision",
    "Description", "Name", "Role")

"""
    parse_cd(source) -> ContentDictionary

Parse a Content Dictionary, from its XML text or from the path of a `.ocd` file.

# Examples
```jldoctest
julia> using OpenMath

julia> cd = OpenMath.parse_cd(\"\"\"
           <CD xmlns="http://www.openmath.org/OpenMathCD">
           <CDName>mycd</CDName><CDStatus>experimental</CDStatus>
           <CDDefinition><Name>widget</Name><Role>application</Role></CDDefinition>
           </CD>\"\"\");

julia> cd.definitions["widget"].role
"application"
```
"""
function parse_cd(source::AbstractString)
    p = XMLPullParser(_maybe_file(source, ".ocd"))

    fields = Dict{String, String}()
    defs = Dict{String, CDDefinition}()

    open_elements = String[]          # the element names currently open
    capture = ""                      # which text element we are inside, if any
    buffer = IOBuffer()

    in_definition = false
    dfields = Dict{String, String}()
    dprops = OMObject[]
    dexamples = OMObject[]
    seen_root = false

    # `symbol` rather than `name`: the outer scope binds `name` too, and a closure
    # that reuses the enclosing name captures it instead of shadowing it.
    function flush_definition()
        in_definition || return nothing
        symbol = get(dfields, "Name", "")
        isempty(symbol) && _cderr("a <CDDefinition> has no <Name>")
        defs[symbol] = CDDefinition(symbol, get(dfields, "Role", ""),
            get(dfields, "Description", ""), dprops, dexamples)
        in_definition = false
        return nothing
    end

    while true
        ev = next_event!(p)

        if ev isa XMLDocumentEnd
            break

        elseif ev isa XMLStartElement
            tag = localname(ev.name)
            if !seen_root
                tag == "CD" ||
                    _cderr("expected a <CD> document element, found <$(ev.name)>", ev.offset)
                seen_root = true
                push!(open_elements, tag)
                continue
            end

            if tag == "CDDefinition"
                flush_definition()
                in_definition = true
                empty!(dfields)
                dprops = OMObject[]
                dexamples = OMObject[]
            elseif tag == "OMOBJ"
                # Inside an FMP it is a property, inside an Example an example.
                target = "Example" in open_elements ? dexamples : dprops
                push!(target, read_xml(_element_source(p, ev)))
                continue                                    # source consumed
            elseif tag in _CD_TEXT
                capture = tag
                take!(buffer)
            end
            ev.selfclosed || push!(open_elements, tag)

        elseif ev isa XMLEndElement
            tag = localname(ev.name)
            isempty(open_elements) || pop!(open_elements)
            if tag == capture
                text = strip(String(take!(buffer)))
                (in_definition && tag in ("Name", "Role", "Description")) ?
                (dfields[tag] = text) : (fields[tag] = get(fields, tag, text))
                capture = ""
            elseif tag == "CDDefinition"
                flush_definition()
            end

        elseif ev isa XMLCharacters
            isempty(capture) || write(buffer, ev.text)
        end
    end
    flush_definition()

    name = get(fields, "CDName", "")
    isempty(name) && _cderr("the dictionary declares no <CDName>")
    base = get(fields, "CDBase", "")
    return ContentDictionary(name, isempty(base) ? CD_BASE : base,
        get(fields, "CDStatus", ""), get(fields, "CDVersion", ""),
        get(fields, "CDRevision", ""), get(fields, "Description", ""), defs)
end

"""
    parse_sts(source) -> STSSignatures

Parse a Small Type System signature file, from its XML text or from the path of a
`.sts` file.
"""
function parse_sts(source::AbstractString)
    p = XMLPullParser(_maybe_file(source, ".sts"))
    cd = ""
    sigs = Dict{String, OMObject}()
    pending = ""
    seen_root = false

    while true
        ev = next_event!(p)
        ev isa XMLDocumentEnd && break
        ev isa XMLStartElement || continue
        tag = localname(ev.name)

        if !seen_root
            tag == "CDSignatures" ||
                _cderr("expected a <CDSignatures> document element, found <$(ev.name)>",
                    ev.offset)
            seen_root = true
            for a in ev.attributes
                a.name == "cd" && (cd = a.value)
            end
        elseif tag == "Signature"
            pending = ""
            for a in ev.attributes
                a.name == "name" && (pending = a.value)
            end
            isempty(pending) && _cderr("a <Signature> has no name attribute", ev.offset)
        elseif tag == "OMOBJ"
            obj = read_xml(_element_source(p, ev))
            isempty(pending) || (sigs[pending] = obj)
            pending = ""
        end
    end

    isempty(cd) && _cderr("the signature file declares no cd attribute")
    return STSSignatures(cd, sigs)
end

# --- arity from a signature ---------------------------------------------------

_is_sts(s, name) = s isa OMSymbol && s.cd == "sts" && s.name == name

# The `sts` dictionary defines `nary` and `nassoc` in the same words — "an
# arbitrary number of copies of the argument" — differing only in whether the
# operator is associative on them, which is about flattening and not about how
# many there may be. Either one means the arity is unbounded.
#
# Only `nassoc` was recognised, so every n-ary symbol in the official set came
# back with the arity of its own `nary(...)` wrapper: `list1#list` accepted
# exactly one element. A set rather than two comparisons, so a third combinator
# is one line and a deliberate one.
const _STS_UNBOUNDED = Set(["nary", "nassoc"])

_is_sts_unbounded(s) = any(n -> _is_sts(s, n), _STS_UNBOUNDED)

"""
    sts_arity(signature) -> Union{Nothing,Int}

The number of arguments a signature admits, or `nothing` when it is n-ary.

An STS signature reads `mapsto(T₁, …, Tₙ, Result)`: the last argument is the
result type, so the arity is one less than the number of arguments. A parameter
wrapped in `sts#nary` or `sts#nassoc` makes the symbol n-ary — the `sts`
dictionary defines both as "an arbitrary number of copies of the argument" — and
then there is no fixed arity to report.
"""
function sts_arity(sig::OMObject)
    a = sig.object
    a isa OMApplication || return nothing
    _is_sts(a.applicant, "mapsto") || return nothing
    length(a.arguments) >= 1 || return nothing
    params = a.arguments[1:(end - 1)]
    for p in params
        p isa OMApplication && _is_sts_unbounded(p.applicant) && return nothing
    end
    return length(params)
end
