# SPDX-License-Identifier: MIT
#
# The JSON writer (standard §3.3). Like the XML writer, emission runs on an
# explicit work stack so that an object that came from a parsed document cannot
# put the depth ceiling back in the hands of the native stack (REQ-SEC-003).

# The range every JSON consumer reads back exactly. Beyond it a JSON number is
# silently rounded through Float64 by a great many parsers, so the standard's
# `decimal` string is the only safe spelling (REQ-JSN-003).
const _JSON_EXACT_INT = BigInt(2)^53 - 1

struct _JPending
    literal::Union{Nothing, String}
    node::Any
    base::String
    indent::Int
end

_jlit(s::AbstractString) = _JPending(String(s), nothing, "", 0)
function _jnode(node, base::AbstractString, indent::Int)
    _JPending(nothing, node, String(base), indent)
end

"""
    OpenMath.json(obj; pretty = false) -> String

Encode `obj` in the OpenMath JSON encoding (standard §3.3).

`cdbase` is written only where the effective base changes, as in the XML
encoding. Integers outside the exactly-representable JSON range and floats with
no JSON literal (`NaN`, the infinities) take the standard's `decimal` and
`hexadecimal` spellings respectively, so that no value is lost.

# Examples
```jldoctest
julia> using OpenMath

julia> OpenMath.json(OMObject(OMS"arith1#plus"(OMInteger(1))))
"{\\"kind\\":\\"OMOBJ\\",\\"openmath\\":\\"2.0\\",\\"object\\":{\\"kind\\":\\"OMA\\",\\"applicant\\":{\\"kind\\":\\"OMS\\",\\"cd\\":\\"arith1\\",\\"name\\":\\"plus\\"},\\"arguments\\":[{\\"kind\\":\\"OMI\\",\\"integer\\":1}]}}"
```
"""
function json(obj::Union{OMObject, OMNode}; pretty::Bool = false)
    io = IOBuffer()
    write_json(io, obj; pretty = pretty)
    return String(take!(io))
end

"""
    write_json(io, obj; pretty = false) -> Int

Write the OpenMath JSON encoding of `obj` to `io`. Returns the byte count.

# Examples
```jldoctest
julia> using OpenMath

julia> io = IOBuffer();

julia> write_json(io, OMObject(OMInteger(1)))
69
```
"""
function write_json(io::IO, obj::Union{OMObject, OMNode}; pretty::Bool = false)
    document = obj isa OMObject ? obj : OMObject(obj)
    check_limit(:max_depth, depth(document.object), limits().max_depth)

    base = document.cdbase === nothing ? CD_BASE : document.cdbase
    n = write(io, "{\"kind\":\"OMOBJ\",\"openmath\":", _jstring(document.version))
    document.cdbase === nothing ||
        (n += write(io, ",\"cdbase\":", _jstring(document.cdbase)))
    document.id === nothing || (n += write(io, ",\"id\":", _jstring(document.id)))
    n += write(io, ",\"object\":")
    pretty && (n += write(io, _jnl(1)))

    stack = _JPending[_jlit("}"), _jnode(document.object, base, 1)]
    while !isempty(stack)
        item = pop!(stack)
        if item.literal !== nothing
            n += write(io, item.literal)
        else
            n += _jemit!(io, stack, item.node, item.base, item.indent, pretty)
        end
    end
    return n
end

Base.istextmime(::MIME"application/openmath+json") = true

function Base.show(io::IO, ::MIME"application/openmath+json", obj::OMObject)
    (write_json(io, obj); nothing)
end
function Base.show(io::IO, m::MIME"application/openmath+json", obj::OMNode)
    show(io, m, OMObject(obj))
end

_jnl(indent::Int) = "\n" * repeat("  ", indent)

function _jbase(own::Union{Nothing, String}, inherited::String)
    own === nothing && return ("", inherited)
    own == inherited && return ("", inherited)
    return (",\"cdbase\":" * _jstring(own), own)
end

_jid(id::Union{Nothing, String}) = id === nothing ? "" : ",\"id\":" * _jstring(id)

function _jemit!(io::IO, stack::Vector{_JPending}, node, base::String, indent::Int,
        pretty::Bool)
    n = 0
    if node isa OMInteger
        n += write(io, "{\"kind\":\"OMI\"", _jid(node.id), _jinteger(node.value), "}")

    elseif node isa OMFloat
        n += write(io, "{\"kind\":\"OMF\"", _jid(node.id), _jfloat(node.value), "}")

    elseif node isa OMString
        n += write(io, "{\"kind\":\"OMSTR\"", _jid(node.id), ",\"string\":",
            _jstring(node.value), "}")

    elseif node isa OMBytes
        n += write(io, "{\"kind\":\"OMB\"", _jid(node.id), ",\"base64\":\"",
            base64_encode(node.value), "\"}")

    elseif node isa OMVariable
        n += write(io, "{\"kind\":\"OMV\"", _jid(node.id), ",\"name\":",
            _jstring(node.name), "}")

    elseif node isa OMReference
        n += write(io, "{\"kind\":\"OMR\"", _jid(node.id), ",\"href\":",
            _jstring(node.href), "}")

    elseif node isa OMForeign
        n += write(io, "{\"kind\":\"OMFOREIGN\"", _jid(node.id), ",\"foreign\":",
            _jstring(node.value))
        node.encoding === nothing ||
            (n += write(io, ",\"encoding\":", _jstring(node.encoding)))
        n += write(io, "}")

    elseif node isa OMSymbol
        attr, _ = _jbase(node.cdbase, base)
        n += write(io, "{\"kind\":\"OMS\"", _jid(node.id), attr, ",\"cd\":",
            _jstring(node.cd), ",\"name\":", _jstring(node.name), "}")

    elseif node isa OMApplication
        attr, inner = _jbase(node.cdbase, base)
        n += write(io, "{\"kind\":\"OMA\"", _jid(node.id), attr, ",\"applicant\":")
        _jpush_tail!(stack, inner, indent, pretty,
            Any[node.applicant],
            Tuple{String, Vector{Any}}[(",\"arguments\":",
                Any[a for a in node.arguments])])

    elseif node isa OMError
        attr, inner = _jbase(node.cdbase, base)
        n += write(io, "{\"kind\":\"OME\"", _jid(node.id), attr, ",\"error\":")
        _jpush_tail!(stack, inner, indent, pretty,
            Any[node.head],
            Tuple{String, Vector{Any}}[(",\"arguments\":",
                Any[a for a in node.arguments])])

    elseif node isa OMBinding
        attr, inner = _jbase(node.cdbase, base)
        n += write(io, "{\"kind\":\"OMBIND\"", _jid(node.id), attr, ",\"binder\":")
        vars = Any[_bound_variable_node(v) for v in node.variables]
        _jpush_tail!(stack, inner, indent, pretty,
            Any[node.binder],
            Tuple{String, Vector{Any}}[(",\"variables\":", vars)],
            (",\"object\":", node.body))

    elseif node isa OMAttribution
        attr, inner = _jbase(node.cdbase, base)
        n += write(io, "{\"kind\":\"OMATTR\"", _jid(node.id), attr, ",\"attributes\":[")
        _jpush_attributes!(stack, node, inner, indent, pretty)

    else
        throw(OpenMathConversionError(typeof(node), "no JSON encoding for this value"))
    end
    return n
end

# Emits: <head value> then each named array, then an optional trailing member.
function _jpush_tail!(stack::Vector{_JPending}, base::String, indent::Int, pretty::Bool,
        head::Vector{Any},
        arrays::Vector{Tuple{String, Vector{Any}}},
        trailing::Union{Nothing, Tuple{String, Any}} = nothing)
    ops = _JPending[]
    push!(ops, _jnode(head[1], base, indent + 1))
    for (label, items) in arrays
        push!(ops, _jlit(label * "["))
        for (i, item) in enumerate(items)
            i == 1 || push!(ops, _jlit(","))
            pretty && push!(ops, _jlit(_jnl(indent + 1)))
            push!(ops, _jnode(item, base, indent + 1))
        end
        pretty && !isempty(items) && push!(ops, _jlit(_jnl(indent)))
        push!(ops, _jlit("]"))
    end
    if trailing !== nothing
        push!(ops, _jlit(trailing[1]))
        push!(ops, _jnode(trailing[2], base, indent + 1))
    end
    push!(ops, _jlit("}"))
    for i in length(ops):-1:1
        push!(stack, ops[i])
    end
    return nothing
end

function _jpush_attributes!(stack::Vector{_JPending}, node::OMAttribution,
        base::String, indent::Int, pretty::Bool)
    ops = _JPending[]
    for (i, p) in enumerate(node.attributes)
        i == 1 || push!(ops, _jlit(","))
        pretty && push!(ops, _jlit(_jnl(indent + 1)))
        push!(ops, _jlit("["))
        push!(ops, _jnode(p.key, base, indent + 1))
        push!(ops, _jlit(","))
        push!(ops, _jnode(p.value, base, indent + 1))
        push!(ops, _jlit("]"))
    end
    pretty && push!(ops, _jlit(_jnl(indent)))
    push!(ops, _jlit("],\"object\":"))
    push!(ops, _jnode(node.object, base, indent + 1))
    push!(ops, _jlit("}"))
    for i in length(ops):-1:1
        push!(stack, ops[i])
    end
    return nothing
end

# --- scalars ------------------------------------------------------------------

function _jinteger(v::Union{Int64, BigInt})
    abs(BigInt(v)) <= _JSON_EXACT_INT && return ",\"integer\":" * string(v)
    return ",\"decimal\":\"" * string(v) * "\""
end

# Same rule as the XML writer, and implemented the same way: write the literal,
# read it back, fall through to the IEEE-754 bit pattern if anything was lost.
# JSON simply has fewer literals available, so NaN and the infinities always fall
# through.
function _jfloat(x::Float64)
    if isfinite(x)
        s = string(x)
        v = tryparse(Float64, s)
        v !== nothing && isequal(v, x) && return ",\"float\":" * s
    end
    return ",\"hexadecimal\":\"" *
           uppercase(string(reinterpret(UInt64, x); base = 16, pad = 16)) * "\""
end

const _JSON_ESCAPES = Dict(UInt8('"') => "\\\"", UInt8('\\') => "\\\\",
    UInt8('\b') => "\\b", UInt8('\f') => "\\f",
    UInt8('\n') => "\\n", UInt8('\r') => "\\r",
    UInt8('\t') => "\\t")

function _jstring(s::AbstractString)
    io = IOBuffer()
    write(io, '"')
    for i in 1:ncodeunits(s)
        b = codeunit(s, i)
        e = get(_JSON_ESCAPES, b, nothing)
        if e !== nothing
            write(io, e)
        elseif b < 0x20
            # JSON forbids raw control characters; \u is the only spelling.
            write(io, "\\u", lowercase(string(b; base = 16, pad = 4)))
        else
            write(io, b)
        end
    end
    write(io, '"')
    return String(take!(io))
end
