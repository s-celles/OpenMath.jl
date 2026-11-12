# SPDX-License-Identifier: MIT
#
# The XML writer (standard §3.1).
#
# Emission is driven by an explicit work stack, like the reader: an object can
# have come from a parsed document and be arbitrarily deep, and recursion here
# would put the depth ceiling back in the hands of the native stack
# (REQ-SEC-003).

# One unit of pending output: either a literal string, or a node still to be
# expanded together with the cdbase it inherits and its indentation level.
struct _Pending
    literal::Union{Nothing, String}
    node::Any
    base::String
    indent::Int
end

_lit(s::AbstractString) = _Pending(String(s), nothing, "", 0)
function _pending(node, base::AbstractString, indent::Int)
    _Pending(nothing, node, String(base), indent)
end

# The argument is `OMNode`, not `OMOrForeign`. Foreign content is not an OpenMath
# object and cannot be a document root — that is the model's own rule (see
# `OMForeign`) — so the signature has to say so. It used to say `OMOrForeign`, and
# `OpenMath.xml(OMForeign(…))` therefore raised a bare MethodError from inside
# `OMObject`, outside the OpenMathError family the API promises. Found by JET.
"""
    OpenMath.xml(obj; pretty = false) -> String

Encode `obj` in the OpenMath XML encoding (standard §3.1).

`pretty` inserts indentation between elements. It never alters character data,
so an `OMSTR` survives it unchanged (REQ-XML-010).

The writer is faithful to the object it is given: it emits `cdbase` wherever a
node's base differs from the one it inherits, and nowhere else (REQ-XML-006). It
does not rewrite the tree, so for the *smallest* output apply
[`minimize_cdbase`](@ref) first — that hoists a base shared by a whole subtree
onto the enclosing element.

# Examples
```jldoctest
julia> using OpenMath

julia> OpenMath.xml(OMObject(OMS"arith1#plus"(OMInteger(1), OMVariable("x"))))
"<OMOBJ xmlns=\\"http://www.openmath.org/OpenMath\\" version=\\"2.0\\"><OMA><OMS cd=\\"arith1\\" name=\\"plus\\"/><OMI>1</OMI><OMV name=\\"x\\"/></OMA></OMOBJ>"
```
"""
function xml(obj::Union{OMObject, OMNode}; pretty::Bool = false)
    io = IOBuffer()
    write_xml(io, obj; pretty = pretty)
    return String(take!(io))
end

"""
    write_xml(io, obj; pretty = false) -> Int

Write the OpenMath XML encoding of `obj` to `io`. Returns the number of bytes
written.

# Examples
```jldoctest
julia> using OpenMath

julia> io = IOBuffer();

julia> write_xml(io, OMObject(OMInteger(1)))
82
```
"""
function write_xml(io::IO, obj::Union{OMObject, OMNode}; pretty::Bool = false)
    document = obj isa OMObject ? obj : OMObject(obj)
    check_limit(:max_depth, depth(document.object), limits().max_depth)

    base = document.cdbase === nothing ? CD_BASE : document.cdbase
    shell = IOBuffer()
    print(shell, "<OMOBJ xmlns=\"", XML_NS, "\" version=\"")
    _escape_attribute(shell, document.version)
    print(shell, "\"")
    document.cdbase === nothing || (print(shell, " cdbase=\"");
        _escape_attribute(shell, document.cdbase);
        print(shell, "\""))
    document.id === nothing || (print(shell, " id=\"");
        _escape_attribute(shell, document.id);
        print(shell, "\""))
    print(shell, ">")

    n = write(io, take!(shell))
    stack = _Pending[_lit("</OMOBJ>"), _pending(document.object, base, 1)]
    pretty && insert!(stack, 1, _lit("\n"))

    while !isempty(stack)
        item = pop!(stack)
        if item.literal !== nothing
            n += write(io, item.literal)
        else
            n += _emit!(io, stack, item.node, item.base, item.indent, pretty)
        end
    end
    return n
end

Base.istextmime(::MIME"application/openmath+xml") = true

function Base.show(io::IO, ::MIME"application/openmath+xml", obj::OMObject)
    (write_xml(io, obj); nothing)
end
function Base.show(io::IO, m::MIME"application/openmath+xml", obj::OMNode)
    show(io, m, OMObject(obj))
end

# --- one node -----------------------------------------------------------------

_nl(indent::Int) = "\n" * repeat("  ", indent)

# `cdbase` scopes lexically (standard §2.1.4), so it is emitted only where the
# effective base actually changes (REQ-XML-006). A node whose own cdbase equals
# what it inherits produces no attribute at all, which is why writing a
# `resolve_cdbase`d object is no more verbose than writing the original.
function _base_attribute(own::Union{Nothing, String}, inherited::String)
    own === nothing && return ("", inherited)
    own == inherited && return ("", inherited)
    return (" cdbase=\"" * _escaped_attribute(own) * "\"", own)
end

function _id_attribute(id::Union{Nothing, String})
    id === nothing ? "" : " id=\"" * _escaped_attribute(id) * "\""
end

function _emit!(io::IO, stack::Vector{_Pending}, node, base::String, indent::Int,
        pretty::Bool)
    n = 0
    if node isa OMInteger
        n += write(io, "<OMI", _id_attribute(node.id), ">", string(node.value), "</OMI>")

    elseif node isa OMFloat
        kind, value = _float_attribute(node.value)
        n += write(io, "<OMF", _id_attribute(node.id), " ", kind, "=\"", value, "\"/>")

    elseif node isa OMString
        n += write(io, "<OMSTR", _id_attribute(node.id), ">")
        n += _escape_text(io, node.value)
        n += write(io, "</OMSTR>")

    elseif node isa OMBytes
        n += write(io, "<OMB", _id_attribute(node.id), ">",
            base64_encode(node.value), "</OMB>")

    elseif node isa OMVariable
        n += write(io, "<OMV", _id_attribute(node.id), " name=\"",
            _escaped_attribute(node.name), "\"/>")

    elseif node isa OMReference
        n += write(io, "<OMR", _id_attribute(node.id), " href=\"",
            _escaped_attribute(node.href), "\"/>")

    elseif node isa OMForeign
        n += write(io, "<OMFOREIGN", _id_attribute(node.id))
        node.encoding === nothing ||
            (n += write(io, " encoding=\"", _escaped_attribute(node.encoding), "\""))
        # Foreign content is verbatim source (see `OMForeign`), so it is written
        # back unchanged and embedded markup survives. Content that is not a
        # well-formed fragment would produce a document nobody could read back,
        # so it is refused rather than silently escaped — escaping would change
        # the value, which is the one thing the round trip must not do.
        _check_foreign(node.value)
        n += write(io, ">", node.value, "</OMFOREIGN>")

    elseif node isa OMSymbol
        attr, _ = _base_attribute(node.cdbase, base)
        n += write(io, "<OMS", attr, _id_attribute(node.id), " cd=\"",
            _escaped_attribute(node.cd), "\" name=\"",
            _escaped_attribute(node.name), "\"/>")

    elseif node isa OMApplication
        attr, inner = _base_attribute(node.cdbase, base)
        n += write(io, "<OMA", attr, _id_attribute(node.id), ">")
        _push_children!(stack, "</OMA>",
            Any[node.applicant; node.arguments], inner, indent, pretty)

    elseif node isa OMError
        attr, inner = _base_attribute(node.cdbase, base)
        n += write(io, "<OME", attr, _id_attribute(node.id), ">")
        _push_children!(stack, "</OME>", Any[node.head; node.arguments], inner,
            indent, pretty)

    elseif node isa OMAttribution
        attr, inner = _base_attribute(node.cdbase, base)
        n += write(io, "<OMATTR", attr, _id_attribute(node.id), ">")
        kids = Any[_AttributeList(node.attributes), node.object]
        _push_children!(stack, "</OMATTR>", kids, inner, indent, pretty)

    elseif node isa OMBinding
        attr, inner = _base_attribute(node.cdbase, base)
        n += write(io, "<OMBIND", attr, _id_attribute(node.id), ">")
        kids = Any[node.binder, _VariableList(node.variables), node.body]
        _push_children!(stack, "</OMBIND>", kids, inner, indent, pretty)

    elseif node isa _AttributeList
        n += write(io, "<OMATP>")
        kids = Any[]
        for p in node.pairs
            push!(kids, p.key, p.value)
        end
        _push_children!(stack, "</OMATP>", kids, base, indent, pretty)

    elseif node isa _VariableList
        n += write(io, "<OMBVAR>")
        kids = Any[_bound_variable_node(v) for v in node.variables]
        _push_children!(stack, "</OMBVAR>", kids, base, indent, pretty)

    else
        throw(OpenMathConversionError(typeof(node),
            "no XML encoding for this value"))
    end
    return n
end

# An attributed bound variable is written as OMATTR(…, OMV(name)), which is the
# form standard §2.1.2 gives it.
function _bound_variable_node(v::OMBoundVariable)
    isempty(v.attributes) ? OMVariable(v.name) :
    OMAttribution(v.attributes, OMVariable(v.name))
end

struct _AttributeList
    pairs::Vector{OMAttributePair}
end

struct _VariableList
    variables::Vector{OMBoundVariable}
end

function _push_children!(stack::Vector{_Pending}, closing::String, kids::Vector{Any},
        base::String, indent::Int, pretty::Bool)
    pretty && push!(stack, _lit(_nl(indent - 1)))
    push!(stack, _lit(closing))
    for i in length(kids):-1:1
        push!(stack, _pending(kids[i], base, indent + 1))
        pretty && push!(stack, _lit(_nl(indent)))
    end
    return nothing
end

function _check_foreign(value::AbstractString)
    try
        # Wrapped in a synthetic root, because this is a *fragment*: `OMFOREIGN`
        # content is whatever sits between the tags, and "text" or "<a/><b/>" is
        # well-formed there and is not a well-formed document. Construction is
        # inside the `try` because one tokenizer parses lazily and the other
        # parses in its constructor.
        p = XMLPullParser("<x>" * String(value) * "</x>")
        while !(next_event!(p) isa XMLDocumentEnd)
        end
    catch err
        err isa OpenMathParseError || rethrow()
        throw(OpenMathConversionError(OMForeign,
            "foreign content is not a well-formed XML fragment and would produce " *
            "a document that cannot be read back ($(err.message)); it is the " *
            "verbatim source, so escape it yourself if it is meant to be text"))
    end
    return nothing
end

# --- OMF: dec or hex ----------------------------------------------------------

# REQ-XML-003 / REQ-XML-004. The rule is stated as a round-trip property, so it
# is implemented as one: write the decimal form, read it back, and fall through
# to the IEEE-754 bit pattern if anything was lost. That way the encoder cannot
# drift from the requirement.
function _float_attribute(x::Float64)
    if isfinite(x)
        s = string(x)
        v = tryparse(Float64, s)
        v !== nothing && isequal(v, x) && return ("dec", s)
    end
    return ("hex", uppercase(string(reinterpret(UInt64, x); base = 16, pad = 16)))
end

# --- escaping -----------------------------------------------------------------

# XML 1.0 §2.2 gives the characters a document may contain:
#
#   Char ::= #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
#
# A C0 control other than tab, newline and carriage return is not among them,
# and XML has no escape for one — `&#0;` is as ill-formed as a raw NUL. So an
# `OMSTR` holding one has no XML representation at all, and this writer used to
# emit it anyway: `OMSTR("\0")` produced a document that expat refuses and that
# our own reader read back happily, because reader and writer shared the fault
# and agreed with each other.
#
# Found by putting the package behind `XML.jl`, which refused to read what we
# had written. JSON and the binary encoding carry such a string exactly; only
# XML and the MathML encoding built on it cannot. See `docs/src/round-trip.md`.
function _check_xml_char(c::Char)
    u = UInt32(c)
    ok = u == 0x09 || u == 0x0a || u == 0x0d ||
         (0x20 <= u <= 0xd7ff) || (0xe000 <= u <= 0xfffd) ||
         (0x10000 <= u <= 0x10ffff)
    ok && return nothing
    throw(OpenMathConversionError(OMString,
        "U+" * uppercase(string(u; base = 16, pad = 4)) *
        " is not a character XML 1.0 §2.2 admits, and XML has no escape for " *
        "one, so this string has no XML representation; the JSON and binary " *
        "encodings carry it exactly"))
end

function _escape_text(io::IO, s::AbstractString)
    for c in s
        _check_xml_char(c)
    end
    n = 0
    for i in 1:ncodeunits(s)
        b = codeunit(s, i)
        if b == UInt8('&')
            n += write(io, "&amp;")
        elseif b == UInt8('<')
            n += write(io, "&lt;")
        elseif b == UInt8('>')
            # Not strictly required outside "]]>", but escaping every '>' keeps
            # that sequence from ever appearing and costs nothing.
            n += write(io, "&gt;")
        elseif b == UInt8('\r')
            # XML 1.0 §2.11: a parser normalises a literal CR, and CRLF, to a
            # single LF before the application sees it, so a raw carriage return
            # does not survive the round trip. A character reference does — §2.11
            # is about literal line breaks. Our own tokenizer did not normalise,
            # so this was invisible until a conforming parser read the output.
            n += write(io, "&#13;")
        else
            n += write(io, b)
        end
    end
    return n
end

function _escape_attribute(io::IO, s::AbstractString)
    for c in s
        _check_xml_char(c)
    end
    n = 0
    for i in 1:ncodeunits(s)
        b = codeunit(s, i)
        if b == UInt8('&')
            n += write(io, "&amp;")
        elseif b == UInt8('\r') || b == UInt8('\n') || b == UInt8('\t')
            # XML 1.0 §3.3.3: attribute-value normalisation turns a literal tab,
            # newline or carriage return into a space. A character reference is
            # exempt, so it is the only spelling that survives.
            n += write(io, "&#", string(Int(b)), ";")
        elseif b == UInt8('<')
            n += write(io, "&lt;")
        elseif b == UInt8('"')
            n += write(io, "&quot;")
        elseif b == UInt8('\n')
            n += write(io, "&#10;")
        elseif b == UInt8('\t')
            n += write(io, "&#9;")
        elseif b == UInt8('\r')
            n += write(io, "&#13;")
        else
            n += write(io, b)
        end
    end
    return n
end

function _escaped_attribute(s::AbstractString)
    io = IOBuffer()
    _escape_attribute(io, s)
    return String(take!(io))
end
