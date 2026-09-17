# SPDX-License-Identifier: MIT
#
# The Strict Content MathML reader (MathML 4 §4.1.3).
#
# Strict, in the sense the specification means it. The full Content MathML
# language has operator elements (`<plus/>`), untyped `<cn>`, `<sep/>`-separated
# rational and complex literals, and presentation markup, none of which has an
# OpenMath counterpart. Guessing at them is how this bridge usually goes wrong, so
# anything outside the strict subset is refused (REQ-MML-004) and normalising it
# stays an optional extension over `MathML.jl`.

const _MML_ELEMENTS = ("math", "cn", "ci", "cs", "cbytes", "csymbol", "apply", "bind",
    "bvar", "cerror", "semantics", "annotation-xml", "share")

const _MML_CN_TYPES = ("integer", "real", "double", "hexdouble")

mutable struct _MMLFrame
    tag::String
    attributes::Vector{XMLAttribute}
    offset::Int
    parent::Union{Nothing, _MMLFrame}
    text::Union{Nothing, IOBuffer}
    children::Vector{Any}
end

const _MML_TEXT = ("cn", "ci", "cs", "cbytes", "csymbol")

# Bound to a local, like the XML reader: a mutable struct field can change
# between the check and the use, so narrowing it in place is something neither a
# reader nor a static analyser should assume.
function _mml_text(f::_MMLFrame)
    buf = f.text
    buf === nothing && return ""
    return String(take!(buf))
end

function _mml_path(f::_MMLFrame)
    parts = String[]
    cur = f
    while cur !== nothing
        push!(parts, cur.tag)
        cur = cur.parent
    end
    return "/" * join(Iterators.reverse(parts), "/")
end

function _mmlerr(f::_MMLFrame, msg::AbstractString)
    throw(OpenMathParseError(msg; offset = f.offset, path = _mml_path(f)))
end

function _mml_attribute(f::_MMLFrame, name::AbstractString)
    for a in f.attributes
        a.name == name && return a.value
    end
    return nothing
end

"""
    read_mathml(src; mode = :strict) -> OMObject

Decode Strict Content MathML (MathML 4 §4.1.3) into an OpenMath object.

Constructs outside the strict subset are rejected rather than interpreted: the
normative correspondence is with *Strict* Content MathML, and the full language
has constructs with no OpenMath counterpart.
"""
function read_mathml(src::AbstractString; mode::Symbol = :strict)
    mode in (:strict, :lenient, :recover) ||
        throw(ArgumentError("mode must be :strict, :lenient or :recover, got $(repr(mode))"))

    p = XMLPullParser(src)
    stack = _MMLFrame[]
    result = nothing
    maxdepth = limits().max_depth

    while true
        ev = next_event!(p)

        if ev isa XMLDocumentEnd
            isempty(stack) || throw(OpenMathParseError(
                "unexpected end of document inside <$(stack[end].tag)>"; offset = ev.offset))
            break

        elseif ev isa XMLStartElement
            tag = localname(ev.name)
            parent = isempty(stack) ? nothing : stack[end]
            tag in _MML_ELEMENTS || throw(OpenMathParseError(
                "<$(ev.name)> is not Strict Content MathML; the strict subset has " *
                "no operator elements or presentation markup (MathML 4 §4.1.3)";
                offset = ev.offset,
                path = (parent === nothing ? "" : _mml_path(parent)) * "/" * tag))

            check_limit(:max_depth, length(stack) + 1, maxdepth)
            frame = _MMLFrame(tag, ev.attributes, ev.offset, parent,
                tag in _MML_TEXT ? IOBuffer() : nothing, Any[])

            if tag == "annotation-xml" && !ev.selfclosed && _is_foreign(frame)
                raw = read_raw_until_end!(p, ev.name)
                parent === nothing && _mmlerr(frame, "<annotation-xml> has no parent")
                push!(parent.children,
                    OMForeign(_mml_attribute(frame, "encoding"), raw;
                        id = _mml_attribute(frame, "id")))
                continue
            end

            if ev.selfclosed
                node = _mml_build(frame)
                isempty(stack) ? (result = node) : push!(parent.children, node)
            else
                push!(stack, frame)
            end

        elseif ev isa XMLEndElement
            isempty(stack) && throw(OpenMathParseError(
                "end tag </$(ev.name)> without a matching start tag"; offset = ev.offset))
            frame = pop!(stack)
            node = _mml_build(frame)
            isempty(stack) ? (result = node) : push!(stack[end].children, node)

        elseif ev isa XMLCharacters
            if isempty(stack)
                isempty(strip(ev.text)) || throw(OpenMathParseError(
                    "character data outside the document element"; offset = ev.offset))
            elseif stack[end].text !== nothing
                buf = stack[end].text
                buf === nothing || write(buf, ev.text)
            elseif !isempty(strip(ev.text))
                _mmlerr(stack[end],
                    "<$(stack[end].tag)> may not contain character data")
            end
        end
    end

    result === nothing && throw(OpenMathParseError("the document is empty"; offset = 1))
    result isa OMObject ||
        throw(OpenMathParseError("the document element must be <math>"; offset = 1))
    return result
end

# An `annotation-xml` is foreign content when it carries no `cd`; with a `cd` it
# is the MathML spelling of an OMATTR key/value pair.
_is_foreign(f::_MMLFrame) = _mml_attribute(f, "cd") === nothing

function _mml_build(f::_MMLFrame)
    t = f.tag
    t == "cn" && return _mml_cn(f)
    t == "ci" && return OMVariable(_mml_name(f, _mml_text(f), "variable name");
        id = _mml_attribute(f, "id"))
    t == "cs" && return OMString(_mml_text(f); id = _mml_attribute(f, "id"))
    t == "cbytes" && return _mml_cbytes(f)
    t == "csymbol" && return _mml_csymbol(f)
    t == "share" && return _mml_share(f)
    t == "apply" && return _mml_apply(f)
    t == "bind" && return _mml_bind(f)
    t == "bvar" && return _MMLBoundVariable(_mml_bvar(f))
    t == "cerror" && return _mml_cerror(f)
    t == "semantics" && return _mml_semantics(f)
    t == "annotation-xml" && return _mml_annotation(f)
    t == "math" && return _mml_math(f)
    return _mmlerr(f, "unhandled element <$(t)>")
end

function _mml_name(f::_MMLFrame, text::AbstractString, what::AbstractString)
    isempty(strip(text)) && _mmlerr(f, "<$(f.tag)> has no $(what)")
    try
        checkname(strip(text), what)
    catch err
        err isa OpenMathNameError || rethrow()
        _mmlerr(f, sprint(showerror, err))
    end
    return String(strip(text))
end

function _mml_cn(f::_MMLFrame)
    kind = _mml_attribute(f, "type")
    # §4.1.3 makes `type` mandatory in the strict subset. An untyped <cn> is
    # ordinary Content MathML, not strict, and guessing the type is exactly the
    # kind of guess this reader refuses to make.
    kind === nothing && _mmlerr(f,
        "<cn> requires a type attribute in Strict Content MathML (§4.1.3)")
    kind in _MML_CN_TYPES || _mmlerr(f,
        "<cn type=$(repr(kind))> is outside the strict subset, which allows " *
        "only integer, real, double and hexdouble")
    text = strip(_mml_text(f))
    id = _mml_attribute(f, "id")

    if kind == "integer"
        v = tryparse(BigInt, text)
        v === nothing && _mmlerr(f, "<cn type=\"integer\"> content $(repr(String(text))) " *
                   "is not an integer")
        return OMInteger(v; id = id)
    elseif kind == "hexdouble"
        length(text) == 16 ||
            _mmlerr(f, "<cn type=\"hexdouble\"> needs exactly 16 hexadecimal digits")
        bits = tryparse(UInt64, text; base = 16)
        bits === nothing && _mmlerr(f, "<cn type=\"hexdouble\"> is not hexadecimal")
        return OMFloat(reinterpret(Float64, bits); id = id)
    end
    v = tryparse(Float64, text)
    v === nothing && _mmlerr(f, "<cn type=$(repr(kind))> content $(repr(String(text))) " *
               "is not a number")
    return OMFloat(v; id = id)
end

function _mml_cbytes(f::_MMLFrame)
    bytes = try
        base64_decode(_mml_text(f); offset = f.offset)
    catch err
        err isa OpenMathParseError || rethrow()
        _mmlerr(f, "<cbytes>: " * err.message)
    end
    return OMBytes(bytes; id = _mml_attribute(f, "id"))
end

function _mml_csymbol(f::_MMLFrame)
    cd = _mml_attribute(f, "cd")
    cd === nothing && _mmlerr(f, "<csymbol> requires a cd attribute (§4.1.3)")
    name = _mml_name(f, _mml_text(f), "symbol name")
    base = _mml_attribute(f, "cdbase")
    base === nothing || isvalidcdbase(base) ||
        _mmlerr(f, "cdbase $(repr(base)) is not an absolute URI")
    try
        return OMSymbol(cd, name; cdbase = base, id = _mml_attribute(f, "id"))
    catch err
        err isa OpenMathNameError || rethrow()
        _mmlerr(f, sprint(showerror, err))
    end
end

function _mml_share(f::_MMLFrame)
    href = _mml_attribute(f, "href")
    href === nothing && _mmlerr(f, "<share> requires an href attribute")
    isempty(href) && _mmlerr(f, "<share href=\"\"> is empty")
    return OMReference(href; id = _mml_attribute(f, "id"))
end

function _mml_objects(f::_MMLFrame)
    out = OMNode[]
    for c in f.children
        c isa OMNode || _mmlerr(f, "<$(f.tag)> may not contain $(typeof(c))")
        push!(out, c)
    end
    return out
end

_mml_cdbase(f::_MMLFrame) = _mml_attribute(f, "cdbase")

function _mml_apply(f::_MMLFrame)
    kids = _mml_objects(f)
    isempty(kids) && _mmlerr(f, "<apply> requires at least an applicant")
    return OMApplication(kids[1], kids[2:end]; cdbase = _mml_cdbase(f),
        id = _mml_attribute(f, "id"))
end

function _mml_bvar(f::_MMLFrame)
    length(f.children) == 1 || _mmlerr(f, "<bvar> must hold exactly one variable")
    v = f.children[1]
    v isa OMVariable && return OMBoundVariable(v.name)
    v isa OMAttribution && v.object isa OMVariable &&
        return OMBoundVariable(v.object.name, v.attributes)
    return _mmlerr(f, "<bvar> must hold a variable or an attributed variable")
end

function _mml_bind(f::_MMLFrame)
    length(f.children) >= 3 ||
        _mmlerr(f, "<bind> needs a binder, at least one <bvar> and a body")
    binder = f.children[1]
    binder isa OMNode || _mmlerr(f, "the binder of <bind> must be an object")
    body = f.children[end]
    body isa OMNode || _mmlerr(f, "the body of <bind> must be an object")
    vars = OMBoundVariable[]
    for c in f.children[2:(end - 1)]
        c isa _MMLBoundVariable || _mmlerr(f, "<bind> expects <bvar> between the " *
                   "binder and the body")
        push!(vars, c.variable)
    end
    isempty(vars) && _mmlerr(f, "<bind> needs at least one <bvar>")
    return OMBinding(binder, vars, body; cdbase = _mml_cdbase(f),
        id = _mml_attribute(f, "id"))
end

function _mml_cerror(f::_MMLFrame)
    isempty(f.children) && _mmlerr(f, "<cerror> requires a <csymbol> head")
    head = f.children[1]
    head isa OMSymbol || _mmlerr(f, "the head of <cerror> must be a <csymbol>")
    args = OMOrForeign[]
    for c in f.children[2:end]
        (c isa OMNode || c isa OMForeign) ||
            _mmlerr(f, "<cerror> may not contain $(typeof(c))")
        push!(args, c)
    end
    return OMError(head, args; cdbase = _mml_cdbase(f), id = _mml_attribute(f, "id"))
end

function _mml_annotation(f::_MMLFrame)
    cd = _mml_attribute(f, "cd")
    cd === nothing && _mmlerr(f, "an <annotation-xml> with no cd is foreign content")
    name = _mml_attribute(f, "name")
    name === nothing && _mmlerr(f, "<annotation-xml> requires a name attribute")
    length(f.children) == 1 || _mmlerr(f, "<annotation-xml> must hold one object")
    value = f.children[1]
    (value isa OMNode || value isa OMForeign) ||
        _mmlerr(f, "<annotation-xml> must hold an object or foreign content")
    key = OMSymbol(cd, name; cdbase = _mml_attribute(f, "cdbase"))
    return OMAttributePair(key, value)
end

function _mml_semantics(f::_MMLFrame)
    isempty(f.children) && _mmlerr(f, "<semantics> requires an object")
    object = f.children[1]
    object isa OMNode || _mmlerr(f, "<semantics> must attribute an object")
    pairs = OMAttributePair[]
    for c in f.children[2:end]
        c isa OMAttributePair ||
            _mmlerr(f, "<semantics> expects <annotation-xml> after the object")
        push!(pairs, c)
    end
    isempty(pairs) && _mmlerr(f, "<semantics> requires at least one annotation")
    return OMAttribution(pairs, object; cdbase = _mml_cdbase(f),
        id = _mml_attribute(f, "id"))
end

function _mml_math(f::_MMLFrame)
    kids = _mml_objects(f)
    length(kids) == 1 ||
        _mmlerr(f, "<math> must contain exactly one object, found $(length(kids))")
    base = _mml_cdbase(f)
    base === nothing || isvalidcdbase(base) ||
        _mmlerr(f, "cdbase $(repr(base)) is not an absolute URI")
    return OMObject(kids[1]; cdbase = base, id = _mml_attribute(f, "id"))
end
