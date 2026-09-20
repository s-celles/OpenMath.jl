# SPDX-License-Identifier: MIT
#
# The XML reader (standard §3.1).
#
# Assembly is driven by an explicit frame stack rather than recursive descent:
# document depth is attacker-controlled, and a StackOverflowError cannot be
# caught reliably in Julia (REQ-SEC-002, REQ-SEC-003).

# Groups are the two element types that are not OpenMath objects in their own
# right; they exist only to be consumed by their parent.
struct _ATPGroup
    pairs::Vector{OMAttributePair}
end

struct _BVARGroup
    variables::Vector{OMBoundVariable}
end

# `parent` rather than a materialised path: building "/OMOBJ/OMA/OMA/…" eagerly at
# every level is quadratic in document depth, which is attacker-controlled. The
# path is walked only when an error is actually raised.
#
# `text` is allocated only for the three elements that carry character data, so a
# deep document does not pay for an IOBuffer per frame.
mutable struct _Frame
    qname::String
    tag::String
    attributes::Vector{XMLAttribute}
    offset::Int
    parent::Union{Nothing, _Frame}
    text::Union{Nothing, IOBuffer}
    children::Vector{Any}
end

const _TEXT_ELEMENTS = ("OMI", "OMSTR", "OMB")

# Warnings are diagnostics, but they are produced per element from
# attacker-controlled input, so they need a ceiling and a once-only flag for the
# document-wide ones. Otherwise a hostile document in :lenient mode grows a
# warning list as large as itself.
const _MAX_WARNINGS = 100

mutable struct _Diagnostics
    warnings::Vector{String}
    suppressed::Int
    namespace_warned::Bool
end

_Diagnostics() = _Diagnostics(String[], 0, false)

function _warn!(d::_Diagnostics, msg::AbstractString)
    if length(d.warnings) >= _MAX_WARNINGS
        d.suppressed += 1
        return nothing
    end
    push!(d.warnings, String(msg))
    return nothing
end

function _collect_warnings(d::_Diagnostics)
    d.suppressed == 0 && return d.warnings
    return vcat(d.warnings, ["… and $(d.suppressed) further warnings, suppressed"])
end

const _OM_ELEMENTS = ("OMOBJ", "OMI", "OMF", "OMSTR", "OMB", "OMV", "OMS", "OMA",
    "OMBIND", "OMBVAR", "OME", "OMATTR", "OMATP", "OMFOREIGN", "OMR")

# Bound to a local rather than used through the field: a mutable struct field can
# in principle change between the check and the use, so narrowing it in place is
# something neither a reader nor a static analyser should assume.
function _text(f::_Frame)
    buf = f.text
    buf === nothing && return ""
    return String(take!(buf))
end

function _attribute(f::_Frame, name::AbstractString)
    for a in f.attributes
        a.name == name && return a.value
    end
    return nothing
end

function _path(f::_Frame)
    parts = String[]
    cur = f
    while cur !== nothing
        push!(parts, cur.tag)
        cur = cur.parent
    end
    return "/" * join(Iterators.reverse(parts), "/")
end

function _perr(f::_Frame, msg::AbstractString)
    throw(OpenMathParseError(msg; offset = f.offset, path = _path(f)))
end

"""
    read_xml(src; mode = :strict) -> OMObject

Decode the OpenMath XML encoding (standard §3.1).

`mode` is `:strict` (reject any deviation), `:lenient` (accept documented
deviations and record them in `result.warnings`) or `:recover`.

# Examples
```jldoctest
julia> using OpenMath

julia> ns = "xmlns=\\"http://www.openmath.org/OpenMath\\"";

julia> read_xml("<OMOBJ " * ns * " version=\\"2.0\\"><OMI>1</OMI></OMOBJ>")
OMOBJ(OMI(1))
```
"""
function read_xml(src::AbstractString; mode::Symbol = :strict)
    mode in (:strict, :lenient, :recover) ||
        throw(ArgumentError("mode must be :strict, :lenient or :recover, got $(repr(mode))"))
    return with_recovery(mode) do
        _read_xml(src, mode)
    end
end

function _read_xml(src::AbstractString, mode::Symbol)
    p = XMLPullParser(src)
    diag = _Diagnostics()
    scopes = Vector{Dict{String, String}}()
    stack = _Frame[]
    result = nothing
    maxdepth = limits().max_depth

    while true
        ev = next_event!(p)

        if ev isa XMLDocumentEnd
            isempty(stack) ||
                throw(OpenMathParseError(
                    "unexpected end of document inside <$(stack[end].tag)>";
                    offset = ev.offset))
            break

        elseif ev isa XMLStartElement
            _push_scope(scopes, ev.attributes)
            _check_namespace(scopes, ev, mode, diag)
            tag = localname(ev.name)
            parent = isempty(stack) ? nothing : stack[end]
            if !(tag in _OM_ELEMENTS)
                err = OpenMathParseError("unknown OpenMath element <$(ev.name)>";
                    offset = ev.offset,
                    path = (parent === nothing ? "" : _path(parent)) * "/" * tag)
                mode === :recover || throw(err)
                # Skip what we cannot name. Its content is not OpenMath as far as
                # this reader is concerned, so it is consumed the same way an
                # OMFOREIGN body is rather than tokenised into frames that would
                # each fail in turn.
                ev.selfclosed || read_raw_until_end!(p, ev.name)
                pop!(scopes)
                node = recovery_error(err)
                _warn!(diag, "recovered: " * sprint(showerror, err))
                if isempty(stack)
                    result = OMObject(node)
                else
                    # `stack[end]` rather than `parent`: they are the same frame,
                    # and `parent` is `Union{Nothing,_Frame}` because it was
                    # computed before this branch knew the stack was non-empty.
                    # JET could not prove the `nothing` unreachable, and it was
                    # right to say so — an unprovable branch is a branch.
                    _attach!(stack, node, stack[end])
                end
                continue
            end

            check_limit(:max_depth, length(stack) + 1, maxdepth)
            frame = _Frame(ev.name, tag, _content_attributes(ev.attributes), ev.offset,
                parent, tag in _TEXT_ELEMENTS ? IOBuffer() : nothing, Any[])

            if tag == "OMFOREIGN" && !ev.selfclosed
                # OMFOREIGN content is by definition not OpenMath: capture the
                # source verbatim rather than tokenising it.
                raw = read_raw_until_end!(p, ev.name)
                pop!(scopes)
                _attach!(stack,
                    OMForeign(_attribute(frame, "encoding"), raw;
                        id = _attribute(frame, "id")),
                    frame)
                continue
            end

            if ev.selfclosed
                pop!(scopes)
                node = _build_recovering(frame, mode, diag)
                isempty(stack) ? (result = node) : _attach!(stack, node, frame)
            else
                push!(stack, frame)
            end

        elseif ev isa XMLEndElement
            isempty(stack) && throw(OpenMathParseError(
                "end tag </$(ev.name)> without a matching start tag"; offset = ev.offset))
            frame = pop!(stack)
            pop!(scopes)
            node = _build_recovering(frame, mode, diag)
            isempty(stack) ? (result = node) : _attach!(stack, node, frame)

        elseif ev isa XMLCharacters
            if isempty(stack)
                isempty(strip(ev.text)) || throw(OpenMathParseError(
                    "character data outside the document element"; offset = ev.offset))
            elseif stack[end].text !== nothing
                buf = stack[end].text
                buf === nothing || write(buf, ev.text)
            elseif !isempty(strip(ev.text))
                f = stack[end]
                mode === :strict && _perr(f,
                    "<$(f.tag)> may not contain character data, found $(repr(strip(ev.text)))")
                _warn!(diag, "ignored character data inside <$(f.tag)>")
            end
        end
    end

    if result === nothing
        err = OpenMathParseError("the document is empty"; offset = 1)
        mode === :recover || throw(err)
        return recovered_document(sprint(showerror, err))
    end
    if !(result isa OMObject)
        err = OpenMathParseError(
            "the document element must be <OMOBJ>, found <$(_tag_of(result))>";
            offset = 1)
        mode === :recover || throw(err)
        # The root is not an OMOBJ, but what was read is still an object: wrap it
        # rather than discarding a document that only got its envelope wrong.
        return OMObject(result, "2.0", nothing, nothing,
            [sprint(showerror, err)])
    end
    isempty(diag.warnings) && return result
    return OMObject(result.object, result.version, result.cdbase, result.id,
        _collect_warnings(diag))
end

_tag_of(x) = x isa OMOrForeign ? String(kind(x)) : string(typeof(x))

# `_build`, but in `:recover` an element that cannot be assembled becomes an
# error object in its own position, so the structure around it survives. That is
# the behaviour worth having: a corpus item with one bad integer is still an
# application of `arith1#plus` to something and a two.
function _build_recovering(f::_Frame, mode::Symbol, diag::_Diagnostics)
    mode === :recover || return _build(f, mode, diag)
    try
        return _build(f, mode, diag)
    catch err
        err isa OpenMathParseError || rethrow()
        _warn!(diag, "recovered: " * sprint(showerror, err))
        return recovery_error(err)
    end
end

function _attach!(stack::Vector{_Frame}, node, frame::_Frame)
    isempty(stack) && _perr(frame, "<$(frame.tag)> has no parent element")
    push!(stack[end].children, node)
    return nothing
end

# --- namespaces ---------------------------------------------------------------

# Each entry is the *fully resolved* prefix mapping at that depth, so a lookup is
# a single dictionary access. An element that declares no xmlns attribute — which
# is almost all of them — shares its parent's dictionary by reference rather than
# copying it, so this costs nothing in the common case.
#
# The obvious alternative, a stack of partial scopes searched from the top, is
# quadratic in document depth. Depth is attacker-controlled, so that is a denial
# of service, not merely a slow path.
function _push_scope(scopes, attributes)
    declares = false
    for a in attributes
        if a.name == "xmlns" || startswith(a.name, "xmlns:")
            declares = true
            break
        end
    end
    if !declares
        push!(scopes, isempty(scopes) ? _EMPTY_SCOPE : scopes[end])
        return nothing
    end
    bindings = isempty(scopes) ? Dict{String, String}() : copy(scopes[end])
    for a in attributes
        if a.name == "xmlns"
            bindings[""] = a.value
        elseif startswith(a.name, "xmlns:")
            bindings[String(SubString(a.name, 7))] = a.value
        end
    end
    push!(scopes, bindings)
    return nothing
end

const _EMPTY_SCOPE = Dict{String, String}()

function _content_attributes(attributes)
    XMLAttribute[a
                 for a in attributes
                 if a.name != "xmlns" && !startswith(a.name, "xmlns:")]
end

_lookup_ns(scopes, pre::AbstractString) = isempty(scopes) ? "" : get(scopes[end], pre, "")

function _check_namespace(scopes, ev::XMLStartElement, mode::Symbol, diag::_Diagnostics)
    uri = _lookup_ns(scopes, prefix(ev.name))
    uri == XML_NS && return nothing
    if isempty(uri)
        mode === :strict && throw(OpenMathParseError(
            "<$(ev.name)> is not in the OpenMath namespace $(XML_NS); " *
            "add xmlns=\"$(XML_NS)\" or parse with mode = :lenient";
            offset = ev.offset))
        # Document-wide, so it is reported once rather than per element.
        if !diag.namespace_warned
            diag.namespace_warned = true
            _warn!(diag, "no OpenMath namespace declared")
        end
        return nothing
    end
    throw(OpenMathParseError(
        "<$(ev.name)> is in namespace $(repr(uri)), expected $(XML_NS)";
        offset = ev.offset))
end

# --- element assembly ---------------------------------------------------------

function _build(f::_Frame, mode::Symbol, diag::_Diagnostics)
    t = f.tag
    t == "OMI" && return _build_omi(f)
    t == "OMF" && return _build_omf(f)
    t == "OMSTR" && return OMString(_text(f); id = _attribute(f, "id"))
    t == "OMB" && return _build_omb(f)
    t == "OMV" && return _build_omv(f)
    t == "OMS" && return _build_oms(f)
    t == "OMR" && return _build_omr(f)
    t == "OMFOREIGN" && return OMForeign(_attribute(f, "encoding"), "";
        id = _attribute(f, "id"))
    t == "OMA" && return _build_oma(f)
    t == "OMBIND" && return _build_ombind(f)
    t == "OMBVAR" && return _build_ombvar(f)
    t == "OMATP" && return _build_omatp(f)
    t == "OMATTR" && return _build_omattr(f)
    t == "OME" && return _build_ome(f)
    t == "OMOBJ" && return _build_omobj(f, diag)
    return _perr(f, "unknown OpenMath element <$(f.qname)>")
end

function _name_or_fail(f::_Frame, attr::AbstractString, what::AbstractString)
    v = _attribute(f, attr)
    v === nothing && _perr(f, "<$(f.tag)> requires a $(attr) attribute")
    try
        checkname(v, what)
    catch err
        err isa OpenMathNameError || rethrow()
        _perr(f, sprint(showerror, err))
    end
    return v
end

function _checked_cdbase(f::_Frame)
    v = _attribute(f, "cdbase")
    v === nothing && return nothing
    isvalidcdbase(v) || _perr(f, "cdbase $(repr(v)) is not an absolute URI")
    return v
end

function _build_omi(f::_Frame)
    s = strip(_text(f))
    isempty(s) && _perr(f, "<OMI> has no content")
    neg = false
    body = s
    if startswith(body, '-')
        neg = true
        body = SubString(body, 2)
    elseif startswith(body, '+')
        body = SubString(body, 2)
    end
    base = 10
    if startswith(body, 'x') || startswith(body, 'X')
        base = 16
        body = SubString(body, 2)
    end
    isempty(body) && _perr(f, "<OMI> content $(repr(String(s))) has no digits")
    v = tryparse(BigInt, body; base = base)
    v === nothing && _perr(f,
        "<OMI> content $(repr(String(s))) is not a base-$(base) integer (standard §3.1.1)")
    return OMInteger(neg ? -v : v; id = _attribute(f, "id"))
end

function _build_omf(f::_Frame)
    dec = _attribute(f, "dec")
    hex = _attribute(f, "hex")
    dec !== nothing && hex !== nothing && _perr(f, "<OMF> carries both dec and hex")
    # Each branch tests its own attribute rather than relying on the combined
    # check above having ruled the other one out. The control flow that made
    # `hex` non-nothing here used to be spread over three statements, which is
    # more than a reader should have to hold in their head — and more than a
    # static analyser can follow at all.
    if dec !== nothing
        v = tryparse(Float64, dec)
        v === nothing && _perr(f, "<OMF dec=$(repr(dec))> is not a decimal float")
        return OMFloat(v; id = _attribute(f, "id"))
    elseif hex !== nothing
        length(hex) == 16 || _perr(f,
            "<OMF hex=$(repr(hex))> must be exactly 16 hexadecimal digits")
        bits = tryparse(UInt64, hex; base = 16)
        bits === nothing && _perr(f, "<OMF hex=$(repr(hex))> is not hexadecimal")
        return OMFloat(reinterpret(Float64, bits); id = _attribute(f, "id"))
    end
    return _perr(f, "<OMF> requires a dec or hex attribute (standard §3.1.1)")
end

function _build_omb(f::_Frame)
    raw = _text(f)
    bytes = try
        base64_decode(raw; offset = f.offset)
    catch err
        err isa OpenMathParseError || rethrow()
        throw(OpenMathParseError("<OMB>: " * err.message; offset = err.offset,
            path = _path(f)))
    end
    return OMBytes(bytes; id = _attribute(f, "id"))
end

function _build_omv(f::_Frame)
    OMVariable(_name_or_fail(f, "name", "variable name"); id = _attribute(f, "id"))
end

function _build_oms(f::_Frame)
    cd = _name_or_fail(f, "cd", "content dictionary name")
    name = _name_or_fail(f, "name", "symbol name")
    return OMSymbol(cd, name; cdbase = _checked_cdbase(f), id = _attribute(f, "id"))
end

function _build_omr(f::_Frame)
    href = _attribute(f, "href")
    href === nothing && _perr(f, "<OMR> requires an href attribute (standard §3.1.2)")
    isempty(href) && _perr(f, "<OMR href=\"\"> is empty")
    return OMReference(href; id = _attribute(f, "id"))
end

function _objects(f::_Frame)
    out = OMNode[]
    for c in f.children
        c isa OMNode || _perr(f, "<$(f.tag)> may not contain $(_describe(c))")
        push!(out, c)
    end
    return out
end

_describe(x::OMForeign) = "<OMFOREIGN>"
_describe(::_ATPGroup) = "<OMATP>"
_describe(::_BVARGroup) = "<OMBVAR>"
_describe(x::OMObject) = "<OMOBJ>"
_describe(x) = string(typeof(x))

function _build_oma(f::_Frame)
    kids = _objects(f)
    isempty(kids) && _perr(f,
        "<OMA> requires at least an applicant: application(A₁,…,Aₙ) has n > 0 " *
        "(standard §2.1.1)")
    return OMApplication(kids[1], kids[2:end]; cdbase = _checked_cdbase(f),
        id = _attribute(f, "id"))
end

function _build_ombvar(f::_Frame)
    vars = OMBoundVariable[]
    for c in f.children
        if c isa OMVariable
            push!(vars, OMBoundVariable(c.name))
        elseif c isa OMAttribution && c.object isa OMVariable
            push!(vars, OMBoundVariable(c.object.name, c.attributes))
        else
            _perr(f,
                "<OMBVAR> may only contain variables or attributed variables " *
                "(standard §2.1.2), found $(_describe(c))")
        end
    end
    isempty(vars) && _perr(f, "<OMBVAR> is empty")
    return _BVARGroup(vars)
end

function _build_ombind(f::_Frame)
    length(f.children) == 3 || _perr(f,
        "<OMBIND> must contain a binder, an <OMBVAR> and a body, " *
        "found $(length(f.children)) children")
    binder, group, body = f.children
    binder isa OMNode || _perr(f, "the binder of <OMBIND> must be an object")
    group isa _BVARGroup || _perr(f, "<OMBIND> requires an <OMBVAR>")
    body isa OMNode || _perr(f, "the body of <OMBIND> must be an object")
    return OMBinding(binder, group.variables, body; cdbase = _checked_cdbase(f),
        id = _attribute(f, "id"))
end

function _build_omatp(f::_Frame)
    isodd(length(f.children)) &&
        _perr(f, "<OMATP> must contain an even number of children (key, value)…")
    pairs = OMAttributePair[]
    for i in 1:2:length(f.children)
        key = f.children[i]
        key isa OMSymbol || _perr(f,
            "the key of an <OMATP> pair must be an <OMS>, found $(_describe(key))")
        value = f.children[i + 1]
        (value isa OMNode || value isa OMForeign) || _perr(f,
            "the value of an <OMATP> pair must be an object or <OMFOREIGN>")
        push!(pairs, OMAttributePair(key, value))
    end
    isempty(pairs) && _perr(f, "<OMATP> is empty")
    return _ATPGroup(pairs)
end

function _build_omattr(f::_Frame)
    length(f.children) == 2 || _perr(f,
        "<OMATTR> must contain an <OMATP> and one object, " *
        "found $(length(f.children)) children")
    group, object = f.children
    group isa _ATPGroup || _perr(f, "<OMATTR> requires an <OMATP> first")
    object isa OMNode || _perr(f, "<OMATTR> must attribute an object")
    return OMAttribution(group.pairs, object; cdbase = _checked_cdbase(f),
        id = _attribute(f, "id"))
end

function _build_ome(f::_Frame)
    isempty(f.children) && _perr(f, "<OME> requires an <OMS> head (standard §2.1.1)")
    head = f.children[1]
    head isa OMSymbol || _perr(f,
        "the head of <OME> must be an <OMS>, found $(_describe(head))")
    args = OMOrForeign[]
    for c in f.children[2:end]
        (c isa OMNode || c isa OMForeign) ||
            _perr(f, "<OME> may not contain $(_describe(c))")
        push!(args, c)
    end
    return OMError(head, args; cdbase = _checked_cdbase(f), id = _attribute(f, "id"))
end

function _build_omobj(f::_Frame, ::_Diagnostics)
    kids = _objects(f)
    length(kids) == 1 || _perr(f,
        "<OMOBJ> must contain exactly one object, found $(length(kids))")
    version = _attribute(f, "version")
    return OMObject(kids[1]; version = version === nothing ? "2.0" : version,
        cdbase = _checked_cdbase(f), id = _attribute(f, "id"))
end
