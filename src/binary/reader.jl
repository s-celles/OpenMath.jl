# SPDX-License-Identifier: MIT
#
# The binary encoding (omstd20 §3.2), reading side.
#
# Three properties this reader is built around:
#
#  * **It consumes one object and stops.** Given an `IO` it reads up to the end
#    object tag and leaves the rest of the stream alone, which is what makes it
#    usable on a socket carrying a sequence of objects — how SCSCP uses this
#    encoding. Given a byte vector, the whole vector must be the document, since
#    there is no second reader to hand the remainder to.
#
#  * **A declared length is checked before it is believed.** Every length field
#    in this encoding is attacker-controlled, and the difference between reading
#    a four-byte length and allocating four gigabytes is one `check_limit`
#    (REQ-BIN-006).
#
#  * **No leniency.** The XML reader has `:lenient` and `:recover` modes because
#    a malformed element can be skipped and the rest of the document still means
#    something. A byte format has no such structure: one wrong length and every
#    subsequent byte is misread, so `mode` is accepted for interface uniformity
#    and every deviation is an error.
#
# The traversal is an explicit stack, never recursion, for the same reason as the
# other readers: `StackOverflowError` cannot be caught reliably (REQ-SEC-002).

# --- the source ---------------------------------------------------------------

abstract type _BinSource end

mutable struct _VecSource <: _BinSource
    data::Vector{UInt8}
    pos::Int                      # 1-based index of the next byte
end

mutable struct _IOSource{T <: IO} <: _BinSource
    io::T
    pos::Int
end

_offset(s::_BinSource) = s.pos

function _truncated(s::_BinSource)
    throw(OpenMathParseError("the stream ends in the middle of a token";
        offset = _offset(s)))
end

function _takebyte!(s::_VecSource)
    s.pos > length(s.data) && _truncated(s)
    b = s.data[s.pos]
    s.pos += 1
    return b
end

function _takebyte!(s::_IOSource)
    eof(s.io) && _truncated(s)
    b = read(s.io, UInt8)
    s.pos += 1
    return b
end

function _take!(s::_VecSource, n::Int)
    check_limit(:max_bytes, n, limits().max_bytes)
    s.pos + n - 1 > length(s.data) && _truncated(s)
    out = s.data[s.pos:(s.pos + n - 1)]
    s.pos += n
    return out
end

# Read in bounded chunks. `n` has passed the byte budget, but the budget is a
# ceiling on a *document*, not a promise that this stream holds that much, so a
# single `read(io, n)` would still let a seven-byte stream ask for a gigabyte.
function _take!(s::_IOSource, n::Int)
    check_limit(:max_bytes, n, limits().max_bytes)
    out = UInt8[]
    sizehint!(out, min(n, 1 << 16))
    remaining = n
    while remaining > 0
        chunk = read(s.io, min(remaining, 1 << 16))
        isempty(chunk) && _truncated(s)
        append!(out, chunk)
        remaining -= length(chunk)
    end
    s.pos += n
    return out
end

function _read_u32!(s::_BinSource)
    b = _take!(s, 4)
    return (UInt32(b[1]) << 24) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 8) | UInt32(b[4])
end

_read_len!(s::_BinSource, long::Bool) = long ? Int(_read_u32!(s)) : Int(_takebyte!(s))

function _utf8!(s::_BinSource, bytes::Vector{UInt8}, what::AbstractString)
    str = String(bytes)
    isvalid(str) || throw(OpenMathParseError("$(what) is not valid UTF-8";
        offset = _offset(s)))
    return str
end

function _checked_name!(s::_BinSource, value::AbstractString, what::AbstractString)
    try
        checkname(value, what)
    catch err
        err isa OpenMathNameError || rethrow()
        throw(OpenMathParseError("invalid $(what) $(repr(String(value)))";
            offset = _offset(s)))
    end
    return String(value)
end

# --- reader state -------------------------------------------------------------

mutable struct _BinState
    om1::Bool                     # the document began [24] rather than [24+64]
    shared::Vector{String}        # ids we minted, in the order objects completed
    symbols::Vector{OMSymbol}     # the four OpenMath 1 tables (§3.2.4.1, §3.2.5)
    variables::Vector{OMVariable}
    strings8::Vector{OMString}
    strings16::Vector{OMString}
    nodes::Int
    root_cdbase::Union{Nothing, String}
end

function _BinState(om1::Bool)
    _BinState(om1, String[], OMSymbol[], OMVariable[],
        OMString[], OMString[], 0, nothing)
end

mutable struct _BinFrame
    kind::Symbol                  # :apply :error :bind :bvars :attr :atp :cdbase
    items::Vector{Any}
    shared::Bool
    uri::String
end

_BinFrame(kind::Symbol, shared::Bool) = _BinFrame(kind, Any[], shared, "")

# The bound-variable list and the attribute-pair list are grammar productions,
# not objects; these carry them up the stack without pretending otherwise.
struct _BVarList
    variables::Vector{OMBoundVariable}
end

struct _PairList
    pairs::Vector{OMAttributePair}
end

# --- entry points -------------------------------------------------------------

"""
    read_binary(src; mode = :strict) -> OMObject

Decode the binary encoding (standard §3.2) from a byte vector, a string of bytes
or an `IO`.

Given an `IO`, exactly one object is consumed and the stream is left positioned
after its end tag, so a stream carrying several objects can be read one at a
time. Given a byte vector, the whole vector must be one document.

`mode` is accepted for uniformity with the other readers and is not used: a
misread byte desynchronises everything after it, so this encoding has no lenient
dialect to recover into.

# Examples
```jldoctest
julia> using OpenMath

julia> read_binary(hex2bytes("580200011019")).object
OMI(16)
```
"""
function read_binary(data::AbstractVector{UInt8}; mode::Symbol = :strict)
    s = _VecSource(Vector{UInt8}(data), 1)
    object = _read_document!(s, mode)
    s.pos <= length(s.data) && throw(OpenMathParseError(
        "trailing bytes after the end object tag"; offset = s.pos))
    return object
end

read_binary(io::IO; mode::Symbol = :strict) = _read_document!(_IOSource(io, 1), mode)

function read_binary(src::AbstractString; mode::Symbol = :strict)
    read_binary(Vector{UInt8}(codeunits(String(src))); mode = mode)
end

function _read_document!(s::_BinSource, mode::Symbol)
    tag = _takebyte!(s)
    identifier(tag) == TOK_OBJ || throw(OpenMathParseError(
        "expected the begin object tag [24] or [24+64], got $(repr(tag))";
        offset = 1))
    isstreamed(tag) && throw(OpenMathParseError(
        "the begin object tag has no streamed form"; offset = 1))

    version = "2.0"
    st = _BinState(!isshared(tag))
    if !st.om1
        # "Objects with start token [88] have two additional bytes m and n that
        # characterize the version (m.n) of the encoding" (§3.2.2).
        major = _takebyte!(s)
        minor = _takebyte!(s)
        version = string(Int(major), '.', Int(minor))
    end

    object = _read_object!(s, st, mode)
    tag = _takebyte!(s)
    identifier(tag) == TOK_OBJ_END || throw(OpenMathParseError(
        "expected the end object tag [25]"; offset = _offset(s)))
    object isa OMNode || throw(OpenMathParseError(
        "foreign content is not an OpenMath object and cannot be the document " *
        "root (§2.1.1)"; offset = _offset(s)))
    return OMObject(object, version, st.root_cdbase, nothing)
end

# --- the traversal ------------------------------------------------------------

function _read_object!(s::_BinSource, st::_BinState, mode::Symbol)
    stack = _BinFrame[]
    while true
        tag = _takebyte!(s)
        t = identifier(tag)
        value = nothing

        if t == TOK_APP || t == TOK_ERROR || t == TOK_BIND || t == TOK_ATTR
            _open!(s, st, stack, t, tag)
            t == TOK_ATTR && _open!(s, st, stack, TOK_ATP, _expect_atp!(s))
            continue
        elseif t == TOK_BVAR
            _open!(s, st, stack, t, tag)
            continue
        elseif t == TOK_CDBASE
            uri = _utf8!(s, _take!(s, _read_len!(s, islong(tag))), "a cdbase")
            _checked_cdbase!(s, uri)
            _depth!(s, stack)
            push!(stack, _BinFrame(:cdbase, Any[], false, uri))
            continue
        elseif t == TOK_APP_END || t == TOK_ERROR_END || t == TOK_BIND_END ||
               t == TOK_BVAR_END || t == TOK_ATTR_END || t == TOK_ATP_END
            value = _close!(s, st, stack, t)
        elseif t == TOK_OBJ_END
            throw(OpenMathParseError(
                "the end object tag [25] closes an object " *
                "that is not open";
                offset = _offset(s)))
        else
            value = _read_leaf!(s, st, tag)
        end

        st.nodes += 1
        check_limit(:max_nodes, st.nodes, limits().max_nodes)

        while true
            if isempty(stack)
                return value
            end
            top = stack[end]
            if top.kind === :cdbase
                pop!(stack)
                value = _attach_cdbase(s, st, value, top.uri, isempty(stack))
                continue
            end
            push!(top.items, value)
            break
        end
    end
end

function _depth!(s::_BinSource, stack::Vector{_BinFrame})
    check_limit(:max_depth, length(stack) + 1, limits().max_depth)
    return nothing
end

function _open!(s::_BinSource, st::_BinState, stack::Vector{_BinFrame}, t::UInt8,
        tag::UInt8)
    isstreamed(tag) && throw(OpenMathParseError(
        "only integers, strings, byte arrays and foreign objects may be streamed " *
        "(§3.2.2)"; offset = _offset(s)))
    shared = isshared(tag)
    if shared && st.om1
        throw(OpenMathParseError(
            "the OpenMath 1 encoding shares only symbols, " *
            "variables and short strings (§3.2.4.1)";
            offset = _offset(s)))
    end
    kind = t == TOK_APP ? :apply :
           t == TOK_ERROR ? :error :
           t == TOK_BIND ? :bind :
           t == TOK_ATTR ? :attr :
           t == TOK_BVAR ? :bvars : :atp
    _depth!(s, stack)
    push!(stack, _BinFrame(kind, shared))
    return nothing
end

# An attributed object is [18] followed immediately by [20]; the pairs are not
# optional, so this is read rather than dispatched on.
function _expect_atp!(s::_BinSource)
    tag = _takebyte!(s)
    identifier(tag) == TOK_ATP || throw(OpenMathParseError(
        "an attributed object opens with the attribute pairs tag [20] (§3.2.2)";
        offset = _offset(s)))
    return tag
end

function _close!(s::_BinSource, st::_BinState, stack::Vector{_BinFrame}, t::UInt8)
    isempty(stack) && throw(OpenMathParseError("an end tag closes nothing";
        offset = _offset(s)))
    frame = pop!(stack)
    expected = frame.kind === :apply ? TOK_APP_END :
               frame.kind === :error ? TOK_ERROR_END :
               frame.kind === :bind ? TOK_BIND_END :
               frame.kind === :bvars ? TOK_BVAR_END :
               frame.kind === :attr ? TOK_ATTR_END :
               frame.kind === :atp ? TOK_ATP_END : 0x00
    t == expected || throw(OpenMathParseError(
        "end tag $(repr(t)) does not close a $(frame.kind)"; offset = _offset(s)))
    return _finish!(st, _build(s, frame), frame.shared)
end

function _build(s::_BinSource, frame::_BinFrame)
    items = frame.items
    if frame.kind === :apply
        isempty(items) && throw(OpenMathParseError(
            "an application needs at least the applicant (§2.1.1)";
            offset = _offset(s)))
        return OMApplication(_node(s, items[1]),
            OMNode[_node(s, x) for x in @view items[2:end]], nothing, nothing)

    elseif frame.kind === :error
        isempty(items) && throw(OpenMathParseError(
            "an error needs a head symbol (§2.1.1)"; offset = _offset(s)))
        head = items[1]
        head isa OMSymbol || throw(OpenMathParseError(
            "the head of an error must be a symbol (§2.1.1)"; offset = _offset(s)))
        return OMError(head, OMOrForeign[_orforeign(s, x) for x in @view items[2:end]],
            nothing, nothing)

    elseif frame.kind === :bvars
        return _BVarList(OMBoundVariable[_bound(s, x) for x in items])

    elseif frame.kind === :bind
        (length(items) == 3 && items[2] isa _BVarList) || throw(OpenMathParseError(
            "a binding is a binder, a [28] variable list and a body (§3.2.2)";
            offset = _offset(s)))
        return OMBinding(_node(s, items[1]), (items[2]::_BVarList).variables,
            _node(s, items[3]), nothing, nothing)

    elseif frame.kind === :atp
        (!isempty(items) && iseven(length(items))) || throw(OpenMathParseError(
            "attribute pairs come in twos (§3.2.2)"; offset = _offset(s)))
        pairs = OMAttributePair[]
        for i in 1:2:length(items)
            key = items[i]
            key isa OMSymbol || throw(OpenMathParseError(
                "an attribute key must be a symbol (§2.1.1)"; offset = _offset(s)))
            push!(pairs, OMAttributePair(key, _orforeign(s, items[i + 1])))
        end
        return _PairList(pairs)
    end

    (length(items) == 2 && items[1] isa _PairList) || throw(OpenMathParseError(
        "an attributed object is a [20] pair list and one object (§3.2.2)";
        offset = _offset(s)))
    return OMAttribution((items[1]::_PairList).pairs, _node(s, items[2]),
        nothing, nothing)
end

function _node(s::_BinSource, x)
    x isa OMNode && return x
    throw(OpenMathParseError(
        x isa OMForeign ?
        "foreign content is not an OpenMath object and is " *
        "admitted only as an attribute value or an error " *
        "argument (§2.1.1)" :
        "expected an object here";
        offset = _offset(s)))
end

function _orforeign(s::_BinSource, x)
    (x isa OMNode || x isa OMForeign) && return x
    throw(OpenMathParseError("expected an object or foreign content here";
        offset = _offset(s)))
end

# `attrvar → variable | [18] attrpairs attrvar [19]`: a bound variable may be
# wrapped in any number of attributions, which the object model folds into the
# variable itself.
function _bound(s::_BinSource, x)
    attributes = OMAttributePair[]
    while x isa OMAttribution
        append!(attributes, x.attributes)
        x = x.object
    end
    x isa OMVariable || throw(OpenMathParseError(
        "a [28] list holds variables, optionally attributed (§3.2.2)";
        offset = _offset(s)))
    return OMBoundVariable((x::OMVariable).name, attributes)
end

# §3.2.4.2 references shared objects by ordinal and carries no identifier, so the
# reader mints one per shared object. That is what lets an `OMR` come back as an
# `OMR` rather than as an inlined copy, and what makes writing idempotent.
function _finish!(st::_BinState, value, shared::Bool)
    (shared && !st.om1) || return value
    id = string('t', length(st.shared))
    push!(st.shared, id)
    return _with_id(value, id)
end

_with_id(x::OMInteger, id::String) = OMInteger(x.value, id)
_with_id(x::OMFloat, id::String) = OMFloat(x.value, id)
_with_id(x::OMString, id::String) = OMString(x.value, id)
_with_id(x::OMBytes, id::String) = OMBytes(x.value, id)
_with_id(x::OMVariable, id::String) = OMVariable(x.name, id)
_with_id(x::OMSymbol, id::String) = OMSymbol(x.cdbase, x.cd, x.name, id)
_with_id(x::OMReference, id::String) = OMReference(x.href, id)
_with_id(x::OMForeign, id::String) = OMForeign(x.encoding, x.value, id)
function _with_id(x::OMApplication, id::String)
    OMApplication(x.applicant, x.arguments, x.cdbase, id)
end
_with_id(x::OMError, id::String) = OMError(x.head, x.arguments, x.cdbase, id)
function _with_id(x::OMBinding, id::String)
    OMBinding(x.binder, x.variables, x.body, x.cdbase, id)
end
function _with_id(x::OMAttribution, id::String)
    OMAttribution(x.attributes, x.object, x.cdbase, id)
end
_with_id(x, ::String) = x

function _checked_cdbase!(s::_BinSource, uri::AbstractString)
    try
        checkcdbase(uri)
    catch err
        err isa OpenMathNameError || rethrow()
        throw(OpenMathParseError("invalid cdbase $(repr(String(uri)))";
            offset = _offset(s)))
    end
    return nothing
end

# Token 9 scopes over exactly one object, and there are three cases.
#
# The object can carry a base, and has none: attach it, which is the ordinary
# case and the only one our own writer produces.
#
# The object already carries one, from a scope nested inside this one. Then the
# inner base wins everywhere within it, and the outer scope affects nothing —
# it is vacuous, and dropping it is what keeps `resolve_cdbase` agreeing with
# the encoding.
#
# The object has nowhere to put a base at all: an integer, a string, a variable.
# At the document root that is exactly the `cdbase` attribute of the `OMOBJ`, so
# it goes there; deeper down it is again vacuous, since `cdbase` only ever
# affects how a symbol resolves and there is no symbol inside.
function _attach_cdbase(s::_BinSource, st::_BinState, value, uri::String,
        atroot::Bool)
    (value isa OMNode || value isa OMForeign) || throw(OpenMathParseError(
        "a cdbase scope contains one object (§3.2.2)"; offset = _offset(s)))
    if _cdbase_of(value) === nothing
        value isa OMSymbol && return OMSymbol(uri, value.cd, value.name, value.id)
        value isa OMApplication &&
            return OMApplication(value.applicant, value.arguments, uri, value.id)
        value isa OMError && return OMError(value.head, value.arguments, uri, value.id)
        value isa OMBinding &&
            return OMBinding(value.binder, value.variables, value.body, uri, value.id)
        value isa OMAttribution &&
            return OMAttribution(value.attributes, value.object, uri, value.id)
        atroot && (st.root_cdbase = uri)
    end
    return value
end

# --- leaves -------------------------------------------------------------------

function _read_leaf!(s::_BinSource, st::_BinState, tag::UInt8)
    t = identifier(tag)
    if st.om1 && isshared(tag)
        return _om1_reference!(s, st, tag)
    end
    isshared(tag) && (t == TOK_REF || t == TOK_REF_EXT) &&
        throw(OpenMathParseError(
            "chains of references are not allowed in the binary encoding (§3.2.4.2)";
            offset = _offset(s)))

    value = if t == TOK_INT
        _read_small_integer!(s, tag)
    elseif t == TOK_BIGINT
        _read_big_integer!(s, tag)
    elseif t == TOK_FLOAT
        _read_float!(s, tag)
    elseif t == TOK_BYTES
        OMBytes(_read_chunks!(s, tag), nothing)
    elseif t == TOK_VAR
        OMVariable(
            _checked_name!(
                s, _utf8!(s, _take!(s, _read_len!(s, islong(tag))),
                    "a variable name"),
                "variable name"),
            nothing)
    elseif t == TOK_STR8 || t == TOK_STR16
        _read_string!(s, tag)
    elseif t == TOK_SYMBOL
        _read_symbol!(s, tag)
    elseif t == TOK_FOREIGN
        _read_foreign!(s, tag)
    elseif t == TOK_REF
        _read_internal_reference!(s, st, tag)
    elseif t == TOK_REF_EXT
        OMReference(
            _utf8!(s, _take!(s, _read_len!(s, islong(tag))),
                "a reference URI"), nothing)
    else
        throw(OpenMathParseError(
            "token identifier $(Int(t)) is not assigned by " *
            "§3.2.1";
            offset = _offset(s)))
    end
    _om1_record!(st, value, t)
    return _finish!(st, value, isshared(tag))
end

# §3.2.4.1, the deprecated OpenMath 1 form: the sharing flag makes the tag a
# back-reference into one of four tables, indexed by a single byte.
function _om1_reference!(s::_BinSource, st::_BinState, tag::UInt8)
    t = identifier(tag)
    islong(tag) && throw(OpenMathParseError(
        "an OpenMath 1 back-reference is encoded with the long flag not set " *
        "(§3.2.4.1)"; offset = _offset(s)))
    table = t == TOK_SYMBOL ? st.symbols :
            t == TOK_VAR ? st.variables :
            t == TOK_STR8 ? st.strings8 :
            t == TOK_STR16 ? st.strings16 : nothing
    table === nothing && throw(OpenMathParseError(
        "the OpenMath 1 encoding shares only symbols, variables and strings " *
        "(§3.2.4.1)"; offset = _offset(s)))
    i = Int(_takebyte!(s)) + 1
    i <= length(table) && return table[i]
    throw(OpenMathParseError(
        "back-reference to slot $(i - 1), which nothing has " *
        "filled; forward references are not allowed (§3.2.5)";
        offset = _offset(s)))
end

# "Each time a sharable sub-object is read, it is entered in the corresponding
# table if it is not full" (§3.2.5). Only strings shorter than 256 characters
# qualify, and the two string widths are separate kinds of object for this
# sharing, hence four tables rather than three.
function _om1_record!(st::_BinState, value, t::UInt8)
    st.om1 || return nothing
    if t == TOK_SYMBOL && value isa OMSymbol
        length(st.symbols) < 256 && push!(st.symbols, value)
    elseif t == TOK_VAR && value isa OMVariable
        length(st.variables) < 256 && push!(st.variables, value)
    elseif (t == TOK_STR8 || t == TOK_STR16) && value isa OMString
        length(value.value) < 256 || return nothing
        table = t == TOK_STR16 ? st.strings16 : st.strings8
        length(table) < 256 && push!(table, value)
    end
    return nothing
end

function _read_internal_reference!(s::_BinSource, st::_BinState, tag::UInt8)
    st.om1 && throw(OpenMathParseError(
        "reference tokens [30] and [31] belong to the encoding that begins " *
        "[24+64] (§3.2.4.2)"; offset = _offset(s)))
    k = _read_len!(s, islong(tag))
    k + 1 <= length(st.shared) || throw(OpenMathParseError(
        "reference to shared object $(k), which has not been read; forward " *
        "references are not allowed (§3.2.5)"; offset = _offset(s)))
    return OMReference(string('#', st.shared[k + 1]), nothing)
end

function _read_float!(s::_BinSource, tag::UInt8)
    b = _take!(s, 8)
    bits = UInt64(0)
    for x in b
        bits = (bits << 8) | UInt64(x)
    end
    return OMFloat(reinterpret(Float64, bits), nothing)
end

# --- integers -----------------------------------------------------------------

# Token 1, the small integer. Unstreamed this is one signed byte, or four in
# network order with the long flag. Streamed, §3.2.2 makes the packets digits of
# base 2^7 (or 2^31 for the long form), most significant first, with only the
# first packet signed. The standard gives no worked example of that case.
function _read_small_integer!(s::_BinSource, tag::UInt8)
    long = islong(tag)
    radix = long ? big(2)^31 : big(2)^7
    acc = big(0)
    negative = false
    first = true
    cur = tag
    while true
        v = if islong(cur)
            Int64(reinterpret(Int32, _read_u32!(s)))
        else
            Int64(reinterpret(Int8, _takebyte!(s)))
        end
        if first
            negative = v < 0
            acc = big(v < 0 ? -v : v)
            first = false
        else
            (0 <= v < radix) || throw(OpenMathParseError(
                "a continuation packet of a small integer is a digit of base " *
                "$(radix)"; offset = _offset(s)))
            acc = acc * radix + v
        end
        isstreamed(cur) || break
        cur = _next_packet!(s, TOK_INT)
        islong(cur) == long || throw(OpenMathParseError(
            "packets of one integer must agree on the long flag";
            offset = _offset(s)))
    end
    return OMInteger(_narrow(negative ? -acc : acc), nothing)
end

# Token 2, the general form: a length, a byte holding the sign or-ed with the
# base, then the digits — characters for bases 10 and 16, raw bytes for base 256.
function _read_big_integer!(s::_BinSource, tag::UInt8)
    digits = UInt8[]
    sign = 0x00
    base = 0x00
    first = true
    cur = tag
    while true
        n = _read_len!(s, islong(cur))
        sb = _takebyte!(s)
        this_sign = sb & ~BASE_MASK
        this_base = sb & BASE_MASK
        (this_sign == SIGN_PLUS || this_sign == SIGN_MINUS) || throw(
            OpenMathParseError(
            "the sign byte of an integer is '+' or '-' or-ed " *
            "with the base mask (§3.2.2)";
            offset = _offset(s)))
        this_base == 0xc0 && throw(OpenMathParseError(
            "0xC0 is not one of the three base masks of §3.2.2";
            offset = _offset(s)))
        if first
            # "only the sequence-initial packet may contain a signed integer"
            sign, base, first = this_sign, this_base, false
        else
            this_base == base || throw(OpenMathParseError(
                "packets of one integer must agree on the base"; offset = _offset(s)))
        end
        append!(digits, _take!(s, n))
        check_limit(:max_bytes, length(digits), limits().max_bytes)
        isstreamed(cur) || break
        cur = _next_packet!(s, TOK_BIGINT)
    end

    magnitude = _digits_to_integer(s, digits, base)
    return OMInteger(_narrow(sign == SIGN_MINUS ? -magnitude : magnitude), nothing)
end

function _digits_to_integer(s::_BinSource, digits::Vector{UInt8}, base::UInt8)
    isempty(digits) && return big(0)
    if base == BASE_256
        acc = big(0)
        for b in digits
            acc = (acc << 8) | Int(b)
        end
        return acc
    end
    text = _utf8!(s, digits, "the digits of an integer")
    radix = base == BASE_16 ? 16 : 10
    value = tryparse(BigInt, text; base = radix)
    (value === nothing || !all(c -> _isdigit(c, radix), text)) && throw(
        OpenMathParseError(
        "$(repr(text)) is not a sequence of base-$(radix) " *
        "digits";
        offset = _offset(s)))
    return value
end

function _isdigit(c::Char, radix::Int)
    ('0' <= c <= '9') && return true
    radix == 16 && (('a' <= c <= 'f') || ('A' <= c <= 'F'))
end

# --- sized and streamed payloads ----------------------------------------------

function _next_packet!(s::_BinSource, expected::UInt8)
    cur = _takebyte!(s)
    identifier(cur) == expected || throw(OpenMathParseError(
        "all packets making up a basic object must have the same token " *
        "identifier (§3.2.2)"; offset = _offset(s)))
    return cur
end

# Byte arrays and LATIN-1 strings are both "a length, then that many bytes",
# concatenated across packets.
function _read_chunks!(s::_BinSource, tag::UInt8)
    out = _take!(s, _read_len!(s, islong(tag)))
    cur = tag
    while isstreamed(cur)
        cur = _next_packet!(s, identifier(tag))
        append!(out, _take!(s, _read_len!(s, islong(cur))))
        check_limit(:max_bytes, length(out), limits().max_bytes)
    end
    return out
end

function _read_string!(s::_BinSource, tag::UInt8)
    if identifier(tag) == TOK_STR8
        bytes = _read_chunks!(s, tag)
        io = IOBuffer()
        for b in bytes
            print(io, Char(b))          # ISO-8859-1: the byte *is* the code point
        end
        return OMString(String(take!(io)), nothing)
    end
    units = UInt16[]
    cur = tag
    while true
        n = _read_len!(s, islong(cur))
        bytes = _take!(s, 2n)           # "the number of UTF-16 units", not of bytes
        for i in 1:2:length(bytes)
            push!(units, (UInt16(bytes[i]) << 8) | UInt16(bytes[i + 1]))
        end
        check_limit(:max_bytes, 2 * length(units), limits().max_bytes)
        isstreamed(cur) || break
        cur = _next_packet!(s, TOK_STR16)
    end
    _check_utf16!(s, units)
    return OMString(transcode(String, units), nothing)
end

# `transcode` replaces a broken surrogate pair rather than refusing it, which
# would turn a malformed document into a different, well-formed one.
function _check_utf16!(s::_BinSource, units::Vector{UInt16})
    i = 1
    while i <= length(units)
        u = units[i]
        if 0xd800 <= u <= 0xdbff
            (i < length(units) && 0xdc00 <= units[i + 1] <= 0xdfff) || throw(
                OpenMathParseError("a high surrogate is not followed by a low one";
                offset = _offset(s)))
            i += 2
        elseif 0xdc00 <= u <= 0xdfff
            throw(OpenMathParseError("a low surrogate stands alone";
                offset = _offset(s)))
        else
            i += 1
        end
    end
    return nothing
end

function _read_symbol!(s::_BinSource, tag::UInt8)
    long = islong(tag)
    ncd = _read_len!(s, long)
    nname = _read_len!(s, long)
    cd = _checked_name!(s, _utf8!(s, _take!(s, ncd), "a content dictionary name"),
        "content dictionary name")
    name = _checked_name!(s, _utf8!(s, _take!(s, nname), "a symbol name"),
        "symbol name")
    return OMSymbol(nothing, cd, name, nothing)
end

function _read_foreign!(s::_BinSource, tag::UInt8)
    long = islong(tag)
    nenc = _read_len!(s, long)
    npayload = _read_len!(s, long)
    encoding = nenc == 0 ? nothing :
               _utf8!(s, _take!(s, nenc), "a foreign encoding")
    payload = _take!(s, npayload)
    cur = tag
    while isstreamed(cur)
        cur = _next_packet!(s, TOK_FOREIGN)
        n2 = _read_len!(s, islong(cur))
        m2 = _read_len!(s, islong(cur))
        enc2 = n2 == 0 ? nothing : _utf8!(s, _take!(s, n2), "a foreign encoding")
        enc2 == encoding || throw(OpenMathParseError(
            "packets of one foreign object must agree on the encoding";
            offset = _offset(s)))
        append!(payload, _take!(s, m2))
        check_limit(:max_bytes, length(payload), limits().max_bytes)
    end
    return OMForeign(encoding, _utf8!(s, payload, "foreign content"), nothing)
end
