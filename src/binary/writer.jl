# SPDX-License-Identifier: MIT
#
# The binary encoding (omstd20 §3.2), writing side.
#
# Two decisions shape this file, both recorded in docs/src/design/binary-backend.md.
#
#  * **D7** — a tag with the sharing flag carries no identifier string. Figure 3.3
#    says it does; Figures 3.5 and 3.6, §3.2.4.2 and §3.2.5 say it does not, and
#    the grammar contradicts itself on the point (`[6+64] [n] bytes:n` has no id
#    field, `[6+64+128] {n} {m} bytes:n id:m` has one). References are by ordinal.
#  * **D8** — the document tag is [24] unless the object needs [24+64]. §3.2.6
#    keeps [24] valid in OpenMath 2 — "the binary encoding tags without the shared
#    flag can still be used as more compact representations of the objects (which
#    are not shared, and do not have an identifier)" — and it is what the only
#    other shipping implementation emits. We use [24+64] exactly when it buys
#    something: structure sharing, or a version other than 2.0, which is the only
#    thing the two version bytes can carry. The deprecated OpenMath 1 per-kind
#    sharing tables are read (§3.2.4.1) and never produced either way.
#
# As in the other writers the traversal is an explicit stack, never recursion: a
# document deep enough to overflow the Julia stack must raise OpenMathLimitError
# instead, and `StackOverflowError` cannot be caught reliably (REQ-SEC-002).

# --- the work stack -----------------------------------------------------------

struct _BinPending
    node::Any                        # a node to emit, or nothing for a closing item
    base::String
    closing::UInt8                   # 0x00 when there is nothing to write
    register::Union{Nothing, String}  # the id to number once this item is reached
end

_bin_node(node, base::AbstractString) = _BinPending(node, String(base), 0x00, nothing)
function _bin_close(tok::UInt8 = 0x00, register::Union{Nothing, String} = nothing)
    _BinPending(nothing, "", tok, register)
end

mutable struct _BinWriteState
    targets::Set{String}             # ids some internal reference points at
    present::Set{String}             # every id in the document
    assigned::Dict{String, Int}      # id => ordinal, filled as objects complete
    assigned_order::Vector{String}
end

function _BinWriteState(targets::Set{String}, present::Set{String})
    _BinWriteState(targets, present, Dict{String, Int}(), String[])
end

# Every id an internal OMR names, and every id that exists. The first set says
# which objects get the sharing flag — an id nothing refers to is dropped, since
# §3.2.4.2 has no way to carry it. The second distinguishes a reference that
# points forward from one that points nowhere, which are different faults.
function _shared_targets(root)
    targets = Set{String}()
    present = Set{String}()
    walk(root) do node
        if node isa OMReference && isinternal(node)
            push!(targets, reference_target(node)::String)
        elseif (node isa OMNode || node isa OMForeign) && node.id !== nothing
            push!(present, node.id::String)
        end
        return nothing
    end
    return (targets, present)
end

"""
    OpenMath.binary(obj) -> Vector{UInt8}

Encode `obj` in the binary encoding (standard §3.2).

# Examples
```jldoctest
julia> using OpenMath

julia> bytes2hex(OpenMath.binary(OMObject(OMInteger(16))))
"18011019"
```

The bytes are the object tag [24], the small integer tag [1] with its value byte,
and the end object tag [25]. An object that needs structure sharing, or that
carries a version other than 2.0, is written with [24+64] instead; see decision
D8 in the design notes.
"""
function binary(obj::Union{OMObject, OMNode})
    io = IOBuffer()
    write_binary(io, obj)
    return take!(io)
end

"""
    write_binary(io, obj) -> Int

Write the binary encoding of `obj` to `io`, returning the number of bytes written.

# Examples
```jldoctest
julia> using OpenMath

julia> io = IOBuffer();

julia> write_binary(io, OMObject(OMInteger(1)))
4
```
"""
function write_binary(io::IO, obj::Union{OMObject, OMNode})
    document = obj isa OMObject ? obj : OMObject(obj)
    check_limit(:max_depth, depth(document.object), limits().max_depth)

    state = _BinWriteState(_shared_targets(document.object)...)

    # [24+64] is needed for exactly two things: the sharing mechanism of §3.2.4.2,
    # and the version bytes. An object using neither is written [24], which every
    # OpenMath 2 reader must accept and which an OpenMath 1 reader accepts too.
    om2 = !isempty(state.targets) || document.version != "2.0"
    n = if om2
        major, minor = _version_bytes(document.version)
        write(io, TOK_OBJ | FLAG_SHARE, major, minor)
    else
        write(io, TOK_OBJ)
    end
    # The binary encoding has no cdbase attribute on the object tag, so a
    # document-level base becomes a scope (token 9) around the root object —
    # unless the root object carries a base of its own, in which case the scope
    # would be overridden by the very object it scopes over and affects nothing.
    # Writing it anyway is what would make `binary(read(binary(x)))` differ from
    # `binary(x)`: the reader has nowhere to put a base that means nothing.
    base = CD_BASE
    if document.cdbase !== nothing && _cdbase_of(document.object) === nothing
        n += _write_cdbase(io, document.cdbase)
        base = document.cdbase
    end
    stack = _BinPending[_bin_close(TOK_OBJ_END), _bin_node(document.object, base)]

    while !isempty(stack)
        item = pop!(stack)
        if item.node === nothing
            item.closing == 0x00 || (n += write(io, item.closing))
            if item.register !== nothing
                _register!(state, item.register)
            end
        else
            n += _bin_emit!(io, stack, state, item.node, item.base)
        end
    end
    return n
end

# Shared objects are numbered in the order they *complete*, which is the only
# order under which Figure 3.6 decodes at all, and what §3.2.5 describes: "it is
# read and a pointer to the generated data structure is stored at the next
# position of the array".
function _register!(state::_BinWriteState, id::String)
    push!(state.assigned_order, id)
    state.assigned[id] = length(state.assigned_order) - 1
    return nothing
end

Base.istextmime(::MIME"application/openmath+binary") = false

function Base.show(io::IO, ::MIME"application/openmath+binary", obj::OMObject)
    write_binary(io, obj)
    return nothing
end
function Base.show(io::IO, m::MIME"application/openmath+binary", obj::OMNode)
    show(io, m, OMObject(obj))
end

# Push `items` so that they are emitted left to right.
function _bin_push!(stack::Vector{_BinPending}, items::Vector{_BinPending})
    for i in length(items):-1:1
        push!(stack, items[i])
    end
    return nothing
end

# --- primitives ---------------------------------------------------------------

function _version_bytes(v::AbstractString)
    parts = split(v, '.')
    length(parts) == 2 || throw(OpenMathConversionError(OMObject,
        "the binary encoding carries the version as two bytes; " *
        "$(repr(String(v))) is not major.minor"))
    nums = map(parts) do p
        n = tryparse(Int, p)
        (n === nothing || n < 0 || n > 255) && throw(OpenMathConversionError(OMObject,
            "version component $(repr(String(p))) does not fit in one byte"))
        return UInt8(n)
    end
    return (nums[1], nums[2])
end

function _put_u32(io::IO, n::Integer)
    write(io, UInt8.(reverse(digits(UInt32(n), base = 256,
        pad = 4)))...)
end

# One length field: a byte, or four bytes in network order when the long flag is
# set. The caller has already put the flag in the tag.
_put_len(io::IO, n::Integer, long::Bool) = long ? _put_u32(io, n) : write(io, UInt8(n))

function _write_cdbase(io::IO, uri::AbstractString)
    bytes = Vector{UInt8}(String(uri))
    long = needs_long(length(bytes))
    n = write(io, TOK_CDBASE | (long ? FLAG_LONG : 0x00))
    n += _put_len(io, length(bytes), long)
    return n + write(io, bytes)
end

# `cdbase` scopes lexically here exactly as it does in the XML encoding, and the
# default is the OpenMath base, so an ordinary symbol needs no scope at all.
function _bin_base(own::Union{Nothing, String}, inherited::String)
    own === nothing && return (false, inherited)
    own == inherited && return (false, inherited)
    return (true, own)
end

# --- emitting one node --------------------------------------------------------

function _bin_emit!(io::IO, stack::Vector{_BinPending}, state::_BinWriteState,
        node, base::String)
    n = 0
    inner = base
    if node isa OMSymbol || node isa OMApplication || node isa OMBinding ||
       node isa OMError || node isa OMAttribution
        scoped, inner = _bin_base(node.cdbase, base)
        scoped && (n += _write_cdbase(io, inner))
    end

    share = _bin_shared(node, state)
    flag = share ? FLAG_SHARE : 0x00

    if node isa OMInteger
        n += _write_integer(io, node.value, flag)

    elseif node isa OMFloat
        n += write(io, TOK_FLOAT | flag)
        n += write(io, reverse(reinterpret(UInt8, [reinterpret(UInt64, node.value)])))

    elseif node isa OMString
        n += _write_string(io, node.value, flag)

    elseif node isa OMBytes
        n += _write_sized(io, TOK_BYTES, node.value, flag)

    elseif node isa OMVariable
        n += _write_sized(io, TOK_VAR, Vector{UInt8}(node.name), flag)

    elseif node isa OMSymbol
        cd = Vector{UInt8}(node.cd)
        name = Vector{UInt8}(node.name)
        long = needs_long(max(length(cd), length(name)))
        n += write(io, TOK_SYMBOL | flag | (long ? FLAG_LONG : 0x00))
        n += _put_len(io, length(cd), long)
        n += _put_len(io, length(name), long)
        n += write(io, cd) + write(io, name)

    elseif node isa OMForeign
        enc = node.encoding === nothing ? UInt8[] : Vector{UInt8}(node.encoding)
        payload = Vector{UInt8}(node.value)
        long = needs_long(max(length(enc), length(payload)))
        n += write(io, TOK_FOREIGN | flag | (long ? FLAG_LONG : 0x00))
        n += _put_len(io, length(enc), long)
        n += _put_len(io, length(payload), long)
        n += write(io, enc) + write(io, payload)

    elseif node isa OMReference
        n += _write_reference(io, node, state)

    elseif node isa OMApplication
        n += write(io, TOK_APP | flag)
        items = _BinPending[_bin_node(node.applicant, inner)]
        for a in node.arguments
            push!(items, _bin_node(a, inner))
        end
        push!(items, _bin_close(TOK_APP_END, share ? node.id : nothing))
        _bin_push!(stack, items)

    elseif node isa OMError
        n += write(io, TOK_ERROR | flag)
        items = _BinPending[_bin_node(node.head, inner)]
        for a in node.arguments
            push!(items, _bin_node(a, inner))
        end
        push!(items, _bin_close(TOK_ERROR_END, share ? node.id : nothing))
        _bin_push!(stack, items)

    elseif node isa OMBinding
        n += write(io, TOK_BIND | flag)
        items = _BinPending[_bin_node(node.binder, inner), _bin_close(TOK_BVAR)]
        for v in node.variables
            push!(items, _bin_node(_bound_variable_node(v), inner))
        end
        push!(items, _bin_close(TOK_BVAR_END))
        push!(items, _bin_node(node.body, inner))
        push!(items, _bin_close(TOK_BIND_END, share ? node.id : nothing))
        _bin_push!(stack, items)

    elseif node isa OMAttribution
        n += write(io, TOK_ATTR | flag)
        n += write(io, TOK_ATP)
        items = _BinPending[]
        for p in node.attributes
            push!(items, _bin_node(p.key, inner))
            push!(items, _bin_node(p.value, inner))
        end
        push!(items, _bin_close(TOK_ATP_END))
        push!(items, _bin_node(node.object, inner))
        push!(items, _bin_close(TOK_ATTR_END, share ? node.id : nothing))
        _bin_push!(stack, items)

    else
        throw(OpenMathConversionError(typeof(node), "no binary encoding for this value"))
    end

    # A leaf completes the moment it is written, so it takes its ordinal here.
    if share && !(node isa OMApplication || node isa OMError ||
         node isa OMBinding || node isa OMAttribution)
        _register!(state, node.id::String)
    end
    return n
end

function _bin_shared(node, state::_BinWriteState)
    node isa OMReference && return false          # chains of references are not allowed
    id = node isa OMForeign || node isa OMNode ? node.id : nothing
    return id !== nothing && id in state.targets
end

function _write_reference(io::IO, node::OMReference, state::_BinWriteState)
    if isinternal(node)
        target = reference_target(node)::String
        k = get(state.assigned, target, nothing)
        if k === nothing
            target in state.present ||
                throw(OpenMathReferenceError(node.href, :dangling))
            throw(OpenMathConversionError(OMReference,
                "the binary encoding numbers shared objects in the order they " *
                "complete, so a reference can only point backwards (§3.2.5); " *
                "$(repr(node.href)) points at an object that has not been " *
                "written yet — call `expand_references` first"))
        end
        long = needs_long(k)
        n = write(io, TOK_REF | (long ? FLAG_LONG : 0x00))
        return n + _put_len(io, k, long)
    end
    return _write_sized(io, TOK_REF_EXT, Vector{UInt8}(node.href), 0x00)
end

function _write_sized(io::IO, tok::UInt8, bytes::Vector{UInt8}, flag::UInt8)
    long = needs_long(length(bytes))
    n = write(io, tok | flag | (long ? FLAG_LONG : 0x00))
    n += _put_len(io, length(bytes), long)
    return n + write(io, bytes)
end

# --- integers -----------------------------------------------------------------

# §3.2.2 gives four formats and permits "a 'small' integer in any 'bigger'
# format". We take the smallest that fits, and **base 10** for the general form.
#
# That is not the densest choice, and the reasoning took two corrections.
#
# Base 256 is densest and was the obvious pick. It is also the one GAP reads
# wrongly — it renders each digit byte as hexadecimal without padding to two
# characters, so any byte below 0x10 drops a zero (see `upstream-bugs.md`). So
# base 16, which GAP reads correctly and the standard gives a worked example of.
#
# Then: why not simply write what the only other implementation writes? GAP emits
# base 10. Decision **D8** already adopted GAP's document tag on exactly that
# reasoning, and applying it to one field and not the other was an inconsistency
# rather than a judgement.
#
# The cost is smaller than it looks. Base 16 saves about 17 % of the *digits of a
# big integer*, which on a 1601-node document with one such integer is ten bytes
# in eleven thousand — 0.09 %. Against that: base 10 is the only base any shipping
# implementation *writes*, so it is the only one whose reader is exercised by
# someone else's round trips. Base 256 was broken in GAP precisely because nothing
# wrote it, and this session has learned three times over that the unexercised
# path is where the defect lives.
function _write_integer(io::IO, v::Union{Int64, BigInt}, flag::UInt8)
    if -128 <= v <= 127
        return write(io, TOK_INT | flag) + write(io, reinterpret(UInt8, Int8(v)))
    elseif -2147483648 <= v <= 2147483647
        n = write(io, TOK_INT | flag | FLAG_LONG)
        return n + _put_u32(io, reinterpret(UInt32, Int32(v)))
    end
    magnitude = BigInt(v) < 0 ? -BigInt(v) : BigInt(v)
    digits = Vector{UInt8}(string(magnitude))
    long = needs_long(length(digits))
    n = write(io, TOK_BIGINT | flag | (long ? FLAG_LONG : 0x00))
    n += _put_len(io, length(digits), long)
    n += write(io, (v < 0 ? SIGN_MINUS : SIGN_PLUS) | BASE_10)
    return n + write(io, digits)
end

# --- strings ------------------------------------------------------------------

# §3.2.2 offers exactly two string tokens, ISO-8859-1 and UTF-16. There is no
# UTF-8 token, so the writer has to choose, and the choice is per string: the
# narrow form when every character fits in a byte, UTF-16 otherwise.
function _write_string(io::IO, s::String, flag::UInt8)
    if all(c -> c <= 'ÿ', s)
        bytes = Vector{UInt8}(undef, length(s))
        for (i, c) in enumerate(s)
            bytes[i] = UInt8(codepoint(c))
        end
        return _write_sized(io, TOK_STR8, bytes, flag)
    end
    units = transcode(UInt16, s)
    long = needs_long(length(units))
    n = write(io, TOK_STR16 | flag | (long ? FLAG_LONG : 0x00))
    n += _put_len(io, length(units), long)
    for u in units
        n += write(io, UInt8(u >> 8), UInt8(u & 0x00ff))
    end
    return n
end
