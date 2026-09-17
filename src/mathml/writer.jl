# SPDX-License-Identifier: MIT
#
# The Strict Content MathML encoding (MathML 4 §4.1.3), which the OpenMath
# standard endorses alongside its own XML, the binary format and JSON: it
# "endorses two encodings in XML (an innate one described here, and one in Strict
# Content MathML)".
#
# This is a relabelling of the XML encoding, not a translation, so it reuses the
# same machinery: an explicit work stack, the same `cdbase` rule, the same
# round-trip test for choosing how to write a float.
#
# The word *Strict* carries the weight. The normative correspondence is with
# Strict Content MathML; the full Content MathML language has constructs with no
# OpenMath counterpart, and pretending otherwise is the usual way this bridge goes
# wrong. Non-strict input is refused rather than guessed at (REQ-MML-004).

"""The XML namespace of MathML elements."""
const MATHML_NS = "http://www.w3.org/1998/Math/MathML"

"""
    OpenMath.mathml(obj; pretty = false) -> String

Encode `obj` as Strict Content MathML (MathML 4 §4.1.3).

# Examples
```jldoctest
julia> using OpenMath

julia> OpenMath.mathml(OMObject(OMS"arith1#plus"(OMInteger(1))))
"<math xmlns=\\"http://www.w3.org/1998/Math/MathML\\"><apply><csymbol cd=\\"arith1\\">plus</csymbol><cn type=\\"integer\\">1</cn></apply></math>"
```
"""
function mathml(obj::Union{OMObject, OMNode}; pretty::Bool = false)
    io = IOBuffer()
    write_mathml(io, obj; pretty = pretty)
    return String(take!(io))
end

"""
    write_mathml(io, obj; pretty = false) -> Int

Write the Strict Content MathML encoding of `obj` to `io`.
"""
function write_mathml(io::IO, obj::Union{OMObject, OMNode}; pretty::Bool = false)
    document = obj isa OMObject ? obj : OMObject(obj)
    check_limit(:max_depth, depth(document.object), limits().max_depth)

    base = document.cdbase === nothing ? CD_BASE : document.cdbase
    n = write(io, "<math xmlns=\"", MATHML_NS, "\"")
    document.cdbase === nothing ||
        (n += write(io, " cdbase=\"", _escaped_attribute(document.cdbase), "\""))
    document.id === nothing ||
        (n += write(io, " id=\"", _escaped_attribute(document.id), "\""))
    n += write(io, ">")

    stack = _Pending[_lit("</math>"), _pending(document.object, base, 1)]
    pretty && insert!(stack, 1, _lit("\n"))
    while !isempty(stack)
        item = pop!(stack)
        if item.literal !== nothing
            n += write(io, item.literal)
        else
            n += _mml_emit!(io, stack, item.node, item.base, item.indent, pretty)
        end
    end
    return n
end

Base.istextmime(::MIME"application/mathml+xml") = true

function Base.show(io::IO, ::MIME"application/mathml+xml", obj::OMObject)
    write_mathml(io, obj)
    return nothing
end
Base.show(io::IO, m::MIME"application/mathml+xml", obj::OMNode) = show(io, m, OMObject(obj))

# `cdbase` scopes the same way it does in the OpenMath XML encoding, and §4.1.3
# makes the OpenMath base the default, so an ordinary symbol carries no attribute.
function _mml_base(own::Union{Nothing, String}, inherited::String)
    own === nothing && return ("", inherited)
    own == inherited && return ("", inherited)
    return (" cdbase=\"" * _escaped_attribute(own) * "\"", own)
end

function _mml_id(id::Union{Nothing, String})
    id === nothing ? "" : " id=\"" * _escaped_attribute(id) * "\""
end

function _mml_emit!(io::IO, stack::Vector{_Pending}, node, base::String, indent::Int,
        pretty::Bool)
    n = 0
    if node isa OMInteger
        n += write(io, "<cn", _mml_id(node.id), " type=\"integer\">", string(node.value),
            "</cn>")

    elseif node isa OMFloat
        # §4.1.3 makes `type` mandatory, from {integer, real, double, hexdouble}.
        # MathML has no literal for NaN or the infinities in a strict `cn` either,
        # so `hexdouble` carries them — the same answer as XML's hex= and JSON's
        # hexadecimal, and decided the same way: write it, read it back, fall
        # through if anything was lost.
        kind, value = _float_attribute(node.value)
        if kind == "dec"
            n += write(io, "<cn", _mml_id(node.id), " type=\"double\">", value, "</cn>")
        else
            n += write(io, "<cn", _mml_id(node.id), " type=\"hexdouble\">", value, "</cn>")
        end

    elseif node isa OMString
        n += write(io, "<cs", _mml_id(node.id), ">")
        n += _escape_text(io, node.value)
        n += write(io, "</cs>")

    elseif node isa OMBytes
        n += write(io, "<cbytes", _mml_id(node.id), ">", base64_encode(node.value),
            "</cbytes>")

    elseif node isa OMVariable
        n += write(io, "<ci", _mml_id(node.id), ">")
        n += _escape_text(io, node.name)
        n += write(io, "</ci>")

    elseif node isa OMReference
        n += write(io, "<share", _mml_id(node.id), " href=\"",
            _escaped_attribute(node.href), "\"/>")

    elseif node isa OMSymbol
        attr, _ = _mml_base(node.cdbase, base)
        n += write(io, "<csymbol", _mml_id(node.id), attr, " cd=\"",
            _escaped_attribute(node.cd), "\">")
        n += _escape_text(io, node.name)
        n += write(io, "</csymbol>")

    elseif node isa OMForeign
        n += write(io, "<annotation-xml", _mml_id(node.id))
        node.encoding === nothing ||
            (n += write(io, " encoding=\"", _escaped_attribute(node.encoding), "\""))
        _check_foreign(node.value)
        n += write(io, ">", node.value, "</annotation-xml>")

    elseif node isa OMApplication
        attr, inner = _mml_base(node.cdbase, base)
        n += write(io, "<apply", _mml_id(node.id), attr, ">")
        _push_children!(stack, "</apply>", Any[node.applicant; node.arguments], inner,
            indent, pretty)

    elseif node isa OMError
        attr, inner = _mml_base(node.cdbase, base)
        n += write(io, "<cerror", _mml_id(node.id), attr, ">")
        _push_children!(stack, "</cerror>", Any[node.head; node.arguments], inner,
            indent, pretty)

    elseif node isa OMBinding
        attr, inner = _mml_base(node.cdbase, base)
        n += write(io, "<bind", _mml_id(node.id), attr, ">")
        kids = Any[node.binder, _MMLBoundVariables(node.variables), node.body]
        _push_children!(stack, "</bind>", kids, inner, indent, pretty)

    elseif node isa _MMLBoundVariables
        # MathML gives each bound variable its own <bvar>, where OpenMath has one
        # <OMBVAR> holding all of them.
        n += write(io, "")
        kids = Any[_MMLBoundVariable(v) for v in node.variables]
        _push_children!(stack, "", kids, base, indent, pretty)

    elseif node isa _MMLBoundVariable
        n += write(io, "<bvar>")
        _push_children!(stack, "</bvar>", Any[_bound_variable_node(node.variable)],
            base, indent, pretty)

    elseif node isa OMAttribution
        attr, inner = _mml_base(node.cdbase, base)
        n += write(io, "<semantics", _mml_id(node.id), attr, ">")
        kids = Any[node.object]
        for p in node.attributes
            push!(kids, _MMLAnnotation(p))
        end
        _push_children!(stack, "</semantics>", kids, inner, indent, pretty)

    elseif node isa _MMLAnnotation
        p = node.pair
        n += write(io, "<annotation-xml cd=\"", _escaped_attribute(p.key.cd),
            "\" name=\"", _escaped_attribute(p.key.name), "\"")
        keybase = p.key.cdbase
        keybase === nothing ||
            (n += write(io, " cdbase=\"", _escaped_attribute(keybase), "\""))
        n += write(io, ">")
        _push_children!(stack, "</annotation-xml>", Any[p.value], base, indent, pretty)

    else
        throw(OpenMathConversionError(typeof(node), "no MathML encoding for this value"))
    end
    return n
end

# Wrappers for the shapes MathML has and OpenMath does not.
struct _MMLBoundVariables
    variables::Vector{OMBoundVariable}
end

struct _MMLBoundVariable
    variable::OMBoundVariable
end

struct _MMLAnnotation
    pair::OMAttributePair
end
