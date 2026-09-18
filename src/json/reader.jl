# SPDX-License-Identifier: MIT
#
# The JSON reader (standard §3.3). Builds OpenMath objects from the scanned JSON
# data model.

const _JSON_KINDS = ("OMOBJ", "OMI", "OMF", "OMSTR", "OMB", "OMV", "OMS", "OMA",
    "OMBIND", "OME", "OMATTR", "OMFOREIGN", "OMR")

_members(v) = v isa Vector{Pair{String, Any}} ? v : nothing

function _member(v::Vector{Pair{String, Any}}, name::AbstractString)
    for p in v
        p.first == name && return p.second
    end
    return nothing
end

# The path to the node being built, as a linked list rather than a string.
#
# It used to be a `String` grown with `path * "/applicant"` at every step, which
# allocates a string of length O(depth) per node — quadratic in total, and the
# dominant allocation in the JSON reader at 4.6 MB of the 4.7 MB a 1601-node
# document spent. It is also the defect the XML reader already had and fixed,
# which nothing propagated here: see `_Frame` in `src/xml/reader.jl`, and E1 №1,
# where the same shape caused an out-of-memory at 200 000 levels.
#
# The segment is kept as a name and an optional index so that even
# `"arguments[3]"` costs nothing until someone asks for it. Only `_jperr`
# materialises a string, and only on the way to throwing.
struct _JPath
    parent::Union{Nothing, _JPath}
    name::String
    index::Int          # 0 when the segment is not indexed
end

const _JROOT = _JPath(nothing, "", 0)

_sub(p::_JPath, name::AbstractString) = _JPath(p, String(name), 0)
_sub(p::_JPath, name::AbstractString, i::Integer) = _JPath(p, String(name), Int(i))

function _jpath_string(p::_JPath)
    parts = String[]
    q = p
    while q !== nothing && !isempty(q.name)
        push!(parts, q.index == 0 ? q.name : string(q.name, '[', q.index, ']'))
        q = q.parent
    end
    return "/" * join(Iterators.reverse(parts), "/")
end

function _jperr(path::_JPath, msg::AbstractString)
    throw(OpenMathParseError(msg; path = _jpath_string(path)))
end

function _string_member(obj, name::AbstractString, path::_JPath,
        what::AbstractString)
    v = _member(obj, name)
    v === nothing && _jperr(path, "$what requires a $(repr(name)) member")
    v isa String || _jperr(path, "$(repr(name)) must be a string")
    return v
end

"""
    read_json(src; mode = :strict) -> OMObject

Decode the OpenMath JSON encoding (standard §3.3).

`mode` is `:strict`, `:lenient` or `:recover`, as for [`read_xml`](@ref).
"""
function read_json(src::AbstractString; mode::Symbol = :strict)
    mode in (:strict, :lenient, :recover) ||
        throw(ArgumentError("mode must be :strict, :lenient or :recover, got $(repr(mode))"))

    value = scan_json(src)
    obj = _members(value)
    obj === nothing && _jperr(_JROOT, "the document must be a JSON object")
    kind = _member(obj, "kind")
    kind == "OMOBJ" ||
        _jperr(_JROOT, "the document element must be \"OMOBJ\", found $(repr(kind))")

    inner = _member(obj, "object")
    inner === nothing && _jperr(_JROOT, "<OMOBJ> requires an \"object\" member")

    version = _member(obj, "openmath")
    version === nothing || version isa String ||
        _jperr(_JROOT, "\"openmath\" must be a string")

    cdbase = _member(obj, "cdbase")
    cdbase === nothing || cdbase isa String || _jperr(_JROOT, "\"cdbase\" must be a string")
    cdbase === nothing || isvalidcdbase(cdbase) ||
        _jperr(_JROOT, "cdbase $(repr(cdbase)) is not an absolute URI")

    id = _member(obj, "id")
    id === nothing || id isa String || _jperr(_JROOT, "\"id\" must be a string")

    # Depth was already bounded by the scanner, so the build below is bounded too.
    node = _build_json(inner, _sub(_JROOT, "object"))
    node isa OMNode ||
        _jperr(_sub(_JROOT, "object"),
            "the document object may not be foreign content")

    return OMObject(node; version = version === nothing ? "2.0" : version,
        cdbase = cdbase, id = id)
end

mutable struct _JFrame2
    kind::String
    path::_JPath
    id::Union{Nothing, String}
    cdbase::Union{Nothing, String}
    requests::Vector{Tuple{Any, _JPath}}
    children::Vector{Any}
    groups::Int
    next::Int
end

function _jframe(kind, path, id, cdbase, requests, groups)
    _JFrame2(kind, path, id, cdbase, requests, Any[], groups, 1)
end

# Build an OpenMath object from the scanned JSON, on an explicit stack.
#
# The four composite kinds are the only place this descends, and it used to
# descend by recursion — the last recursive traversal in the package. On a
# default stack that survived about 10 000 levels and not 20 000, and Julia's
# message on the way out was "program state may be corrupted", which is the
# outcome REQ-SEC-002 exists to prevent. The XML reader, the binary reader and
# all four writers have always used explicit stacks; this one now does too, so
# depth is bounded by `max_depth` and by memory, as everywhere else.
function _build_json(value, path::_JPath)
    stack = _JFrame2[]
    pending::Union{Nothing, Tuple{Any, _JPath}} = (value, path)
    result::Any = nothing

    while true
        while pending !== nothing
            v, p = pending
            pending = nothing
            node = _build_json_node(stack, v, p)
            if node === nothing                     # a composite frame was pushed
                check_limit(:max_depth, length(stack), limits().max_depth)
                f = stack[end]
                pending = f.requests[1]
                f.next = 2
            else
                result = node
            end
        end

        isempty(stack) && return result
        f = stack[end]
        push!(f.children, result)
        result = nothing
        if f.next <= length(f.requests)
            pending = f.requests[f.next]
            f.next += 1
            continue
        end
        pop!(stack)
        result = _json_assemble(f)
    end
end

# One node: a leaf is returned, a composite pushes a frame and returns `nothing`.
function _build_json_node(stack::Vector{_JFrame2}, value, path::_JPath)
    obj = _members(value)
    obj === nothing &&
        _jperr(path, "expected a JSON object describing an OpenMath object")
    kind = _member(obj, "kind")
    kind isa String || _jperr(path, "every OpenMath object needs a \"kind\" member")
    kind in _JSON_KINDS || _jperr(path, "unknown OpenMath kind $(repr(kind))")

    id = _member(obj, "id")
    id === nothing || id isa String || _jperr(path, "\"id\" must be a string")

    kind == "OMI" && return _json_omi(obj, path, id)
    kind == "OMF" && return _json_omf(obj, path, id)
    kind == "OMSTR" && return OMString(_string_member(obj, "string", path, "OMSTR");
        id = id)
    kind == "OMB" && return _json_omb(obj, path, id)
    kind == "OMV" && return _json_name(OMVariable, obj, path, id)
    kind == "OMS" && return _json_oms(obj, path, id)
    kind == "OMR" && return OMReference(_string_member(obj, "href", path, "OMR"); id = id)
    kind == "OMFOREIGN" && return _json_foreign(obj, path, id)
    if kind == "OMA" || kind == "OMBIND" || kind == "OME" || kind == "OMATTR"
        push!(stack, _json_requests(kind, obj, path, id))
        return nothing
    end
    return _jperr(path, "an OMOBJ may not be nested inside another object")
end

function _json_cdbase(obj, path::_JPath)
    v = _member(obj, "cdbase")
    v === nothing && return nothing
    v isa String || _jperr(path, "\"cdbase\" must be a string")
    isvalidcdbase(v) || _jperr(path, "cdbase $(repr(v)) is not an absolute URI")
    return v
end

function _json_name(T, obj, path::_JPath, id)
    name = _string_member(obj, "name", path, "this object")
    try
        return T(name; id = id)
    catch err
        err isa OpenMathNameError || rethrow()
        _jperr(path, sprint(showerror, err))
    end
end

function _json_oms(obj, path::_JPath, id)
    cd = _string_member(obj, "cd", path, "OMS")
    name = _string_member(obj, "name", path, "OMS")
    try
        return OMSymbol(cd, name; cdbase = _json_cdbase(obj, path), id = id)
    catch err
        err isa OpenMathNameError || rethrow()
        _jperr(path, sprint(showerror, err))
    end
end

# §3.3 gives OMI three spellings. `integer` is a JSON number, which is why the
# scanner keeps its text: a value past 2^53 is still legal JSON and must not be
# rounded on the way in (REQ-JSN-003).
function _json_omi(obj, path::_JPath, id)
    n = _member(obj, "integer")
    if n !== nothing
        n isa JSONNumber || _jperr(path, "\"integer\" must be a JSON number")
        n.isintegral || _jperr(path, "\"integer\" must not have a fraction or exponent")
        v = tryparse(BigInt, n.text)
        v === nothing && _jperr(path, "\"integer\" is not an integer: $(repr(n.text))")
        return OMInteger(v; id = id)
    end
    d = _member(obj, "decimal")
    if d !== nothing
        d isa String || _jperr(path, "\"decimal\" must be a string")
        v = tryparse(BigInt, d)
        v === nothing && _jperr(path, "\"decimal\" is not an integer: $(repr(d))")
        return OMInteger(v; id = id)
    end
    h = _member(obj, "hexadecimal")
    if h isa String
        return OMInteger(_parse_hex_integer(h, path); id = id)
    elseif h !== nothing
        _jperr(path, "\"hexadecimal\" must be a string")
    end
    return _jperr(path, "OMI requires \"integer\", \"decimal\" or \"hexadecimal\"")
end

function _parse_hex_integer(s::AbstractString, path::_JPath)
    body = s
    neg = false
    if startswith(body, '-')
        neg = true
        body = SubString(body, 2)
    elseif startswith(body, '+')
        body = SubString(body, 2)
    end
    (startswith(body, 'x') || startswith(body, 'X')) ||
        _jperr(path, "a hexadecimal integer is written \"x1F\" or \"-x1F\", got $(repr(String(s)))")
    v = tryparse(BigInt, SubString(body, 2); base = 16)
    v === nothing && _jperr(path, "$(repr(String(s))) is not a hexadecimal integer")
    return neg ? -v : v
end

# JSON has no NaN or Infinity literal, so `hexadecimal` — the IEEE-754 bit
# pattern — is the only lossless spelling the standard offers for them.
function _json_omf(obj, path::_JPath, id)
    f = _member(obj, "float")
    if f !== nothing
        f isa JSONNumber || _jperr(path, "\"float\" must be a JSON number")
        v = tryparse(Float64, f.text)
        v === nothing && _jperr(path, "\"float\" is not a number: $(repr(f.text))")
        return OMFloat(v; id = id)
    end
    d = _member(obj, "decimal")
    if d !== nothing
        d isa String || _jperr(path, "\"decimal\" must be a string")
        v = tryparse(Float64, d)
        v === nothing && _jperr(path, "\"decimal\" is not a decimal float: $(repr(d))")
        return OMFloat(v; id = id)
    end
    h = _member(obj, "hexadecimal")
    # An `isa` branch rather than an assertion: it narrows the type for every
    # reader, human or static, without relying on `_jperr` being known to throw.
    if h isa String
        length(h) == 16 ||
            _jperr(path, "\"hexadecimal\" must be exactly 16 hex digits, got $(repr(h))")
        bits = tryparse(UInt64, h; base = 16)
        bits === nothing && _jperr(path, "$(repr(h)) is not hexadecimal")
        return OMFloat(reinterpret(Float64, bits), id === nothing ? nothing : String(id))
    elseif h !== nothing
        _jperr(path, "\"hexadecimal\" must be a string")
    end
    return _jperr(path, "OMF requires \"float\", \"decimal\" or \"hexadecimal\"")
end

function _json_omb(obj, path::_JPath, id)
    b = _member(obj, "base64")
    if b !== nothing
        b isa String || _jperr(path, "\"base64\" must be a string")
        bytes = try
            base64_decode(b)
        catch err
            err isa OpenMathParseError || rethrow()
            _jperr(path, "OMB: " * err.message)
        end
        return OMBytes(bytes; id = id)
    end
    v = _member(obj, "bytes")
    if v !== nothing
        v isa Vector{Any} || _jperr(path, "\"bytes\" must be an array")
        out = Vector{UInt8}(undef, length(v))
        for (i, e) in enumerate(v)
            (e isa JSONNumber && e.isintegral) ||
                _jperr(path, "\"bytes\" must contain integers")
            n = tryparse(Int, e.text)
            (n === nothing || n < 0 || n > 255) &&
                _jperr(path, "\"bytes\" entries must be in 0…255, got $(e.text)")
            out[i] = UInt8(n)
        end
        return OMBytes(out; id = id)
    end
    return _jperr(path, "OMB requires \"base64\" or \"bytes\"")
end

function _json_foreign(obj, path::_JPath, id)
    v = _member(obj, "foreign")
    v === nothing && _jperr(path, "OMFOREIGN requires a \"foreign\" member")
    v isa String || _jperr(path, "\"foreign\" must be a string")
    enc = _member(obj, "encoding")
    enc === nothing || enc isa String || _jperr(path, "\"encoding\" must be a string")
    return OMForeign(enc, v; id = id)
end

function _json_children(obj, name::AbstractString, path::_JPath,
        what::AbstractString)
    v = _member(obj, name)
    v === nothing && return Any[]
    v isa Vector{Any} || _jperr(path, "$what expects $(repr(name)) to be an array")
    return v
end

function _as_object(x, path::_JPath)
    x isa OMNode && return x
    return _jperr(path, "foreign content is not allowed here")
end

# --- composites, on an explicit stack ------------------------------------------
#
# The four composite kinds are the only place this reader ever descended, and it
# used to do so by recursion — the last recursive traversal in the package, and
# the reason a deep document could reach a `StackOverflowError` where the XML and
# binary readers cannot (E5). What follows is the same logic on a work stack.
#
# Each frame holds the children it still has to ask for, the ones already built,
# and enough shape to put them back together: `groups` is the count the assembly
# needs — bound variables for OMBIND, attribute pairs for OMATTR — since the rest
# of the layout is fixed per kind.

# What a composite needs built, in the order the assembly expects it back.
function _json_requests(kind::String, obj, path::_JPath, id)
    cdbase = _json_cdbase(obj, path)
    reqs = Tuple{Any, _JPath}[]

    if kind == "OMA"
        applicant = _member(obj, "applicant")
        applicant === nothing && _jperr(path, "OMA requires an \"applicant\" member")
        push!(reqs, (applicant, _sub(path, "applicant")))
        for (i, a) in enumerate(_json_children(obj, "arguments", path, "OMA"))
            push!(reqs, (a, _sub(path, "arguments", i)))
        end
        return _jframe(kind, path, id, cdbase, reqs, 0)

    elseif kind == "OMBIND"
        binder = _member(obj, "binder")
        binder === nothing && _jperr(path, "OMBIND requires a \"binder\" member")
        body = _member(obj, "object")
        body === nothing && _jperr(path, "OMBIND requires an \"object\" member")
        vars = _json_children(obj, "variables", path, "OMBIND")
        isempty(vars) && _jperr(path, "OMBIND requires at least one bound variable")
        push!(reqs, (binder, _sub(path, "binder")))
        for (i, v) in enumerate(vars)
            push!(reqs, (v, _sub(path, "variables", i)))
        end
        push!(reqs, (body, _sub(path, "object")))
        return _jframe(kind, path, id, cdbase, reqs, length(vars))

    elseif kind == "OME"
        head = _member(obj, "error")
        head === nothing && _jperr(path, "OME requires an \"error\" member")
        push!(reqs, (head, _sub(path, "error")))
        for (i, a) in enumerate(_json_children(obj, "arguments", path, "OME"))
            push!(reqs, (a, _sub(path, "arguments", i)))
        end
        return _jframe(kind, path, id, cdbase, reqs, 0)
    end

    body = _member(obj, "object")
    body === nothing && _jperr(path, "OMATTR requires an \"object\" member")
    pairs = _member(obj, "attributes")
    pairs isa Vector{Any} || _jperr(path, "OMATTR requires an \"attributes\" array")
    isempty(pairs) && _jperr(path, "OMATTR requires at least one attribute")
    for (i, pr) in enumerate(pairs)
        pp = _sub(path, "attributes", i)
        (pr isa Vector{Any} && length(pr) == 2) ||
            _jperr(pp, "each attribute is a two-element [key, value] array")
        push!(reqs, (pr[1], _sub(pp, "key")))
        push!(reqs, (pr[2], _sub(pp, "value")))
    end
    push!(reqs, (body, _sub(path, "object")))
    return _jframe("OMATTR", path, id, cdbase, reqs, length(pairs))
end

function _json_assemble(f::_JFrame2)
    kids = f.children
    paths = f.requests

    if f.kind == "OMA"
        return OMApplication(_as_object(kids[1], paths[1][2]),
            OMNode[_as_object(kids[i], paths[i][2]) for i in 2:length(kids)];
            cdbase = f.cdbase, id = f.id)

    elseif f.kind == "OME"
        kids[1] isa OMSymbol ||
            _jperr(paths[1][2], "the head of OME must be an OMS")
        return OMError(kids[1]::OMSymbol,
            OMOrForeign[_as_orforeign(kids[i], paths[i][2]) for i in 2:length(kids)];
            cdbase = f.cdbase, id = f.id)

    elseif f.kind == "OMBIND"
        bound = OMBoundVariable[]
        for i in 2:(1 + f.groups)
            node = kids[i]
            if node isa OMVariable
                push!(bound, OMBoundVariable(node.name))
            elseif node isa OMAttribution && node.object isa OMVariable
                push!(bound, OMBoundVariable(node.object.name, node.attributes))
            else
                _jperr(paths[i][2], "a bound variable must be an OMV or an attributed OMV")
            end
        end
        return OMBinding(_as_object(kids[1], paths[1][2]), bound,
            _as_object(kids[end], paths[end][2]);
            cdbase = f.cdbase, id = f.id)
    end

    out = OMAttributePair[]
    for i in 1:f.groups
        key = kids[2i - 1]
        key isa OMSymbol ||
            _jperr(paths[2i - 1][2], "an attribute key must be an OMS")
        push!(out, OMAttributePair(key::OMSymbol, _as_orforeign(kids[2i], paths[2i][2])))
    end
    return OMAttribution(out, _as_object(kids[end], paths[end][2]);
        cdbase = f.cdbase, id = f.id)
end

function _as_orforeign(x, path::_JPath)
    (x isa OMNode || x isa OMForeign) && return x
    return _jperr(path, "expected an object or foreign content here")
end
