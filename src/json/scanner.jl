# SPDX-License-Identifier: MIT
#
# A JSON scanner for the OpenMath JSON encoding (standard §3.3). See decision D3
# in docs/src/design/json-backend.md for why this is purpose-built.
#
# Two properties a general-purpose JSON parser does not give us for free:
#
#  * Numbers keep their source text. `{"kind":"OMI","integer":2^200}` is a legal
#    JSON number, and a parser that hands back a Float64 has already destroyed it
#    (REQ-JSN-003). Nothing here interprets a number until the reader knows which
#    OpenMath field it belongs to.
#
#  * Every failure carries a byte offset and nothing escapes the OpenMathError
#    family (REQ-API-007, REQ-SEC-001).
#
# Scanning is byte-oriented, which is safe on UTF-8 — continuation bytes are all
# ≥ 0x80 and can never be mistaken for an ASCII delimiter — and lets malformed
# UTF-8 pass through as opaque bytes rather than throw.

"""
    JSONNumber(text, isintegral)

A JSON number, kept as its source text until the reader knows what it means.
"""
struct JSONNumber
    text::String
    isintegral::Bool
end

"""
    JSONValue

The JSON data model, as the OpenMath encoding uses it. Objects keep their members
in document order because the reader reports the position of a bad one.
"""
const JSONValue = Union{Nothing, Bool, String, JSONNumber,
    Vector{Any}, Vector{Pair{String, Any}}}

mutable struct JSONScanner
    data::String
    pos::Int
end

JSONScanner(data::AbstractString) = JSONScanner(String(data), 1)

@inline _jeof(s::JSONScanner, i::Int = s.pos) = i > ncodeunits(s.data)
@inline _jbyte(s::JSONScanner, i::Int = s.pos) = codeunit(s.data, i)

function _jfail(s::JSONScanner, msg::AbstractString, at::Int = s.pos)
    throw(OpenMathParseError(msg; offset = at))
end

function _jskip!(s::JSONScanner)
    while !_jeof(s)
        b = _jbyte(s)
        (b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d) || break
        s.pos += 1
    end
    return nothing
end

"""
    scan_json(src) -> JSONValue

Parse `src` into the JSON data model. Depth is bounded by the configured
`max_depth`; the parser uses an explicit stack, so a deeply nested document
raises [`OpenMathLimitError`](@ref) rather than overflowing (REQ-SEC-002).
"""
function scan_json(src::AbstractString)
    s = JSONScanner(src)
    _jskip!(s)
    _jeof(s) && _jfail(s, "the input is empty", 1)
    value = _scan_value!(s)
    _jskip!(s)
    _jeof(s) || _jfail(s, "trailing content after the JSON value")
    return value
end

# A frame is a container being filled: either an array, or an object together
# with the key awaiting its value.
mutable struct _JFrame
    isobject::Bool
    array::Vector{Any}
    members::Vector{Pair{String, Any}}
    key::String
end

_array_frame() = _JFrame(false, Any[], Pair{String, Any}[], "")
_object_frame() = _JFrame(true, Any[], Pair{String, Any}[], "")

function _scan_value!(s::JSONScanner)
    maxdepth = limits().max_depth
    stack = _JFrame[]
    result = nothing
    have_result = false

    while true
        _jskip!(s)
        _jeof(s) && _jfail(s, "unexpected end of input")
        b = _jbyte(s)

        # --- open a container, or read a scalar ---
        if b == UInt8('[')
            s.pos += 1
            check_limit(:max_depth, length(stack) + 1, maxdepth)
            push!(stack, _array_frame())
            _jskip!(s)
            if !_jeof(s) && _jbyte(s) == UInt8(']')
                s.pos += 1
                value, have_result = _close!(stack), true
            else
                continue
            end
        elseif b == UInt8('{')
            s.pos += 1
            check_limit(:max_depth, length(stack) + 1, maxdepth)
            push!(stack, _object_frame())
            _jskip!(s)
            if !_jeof(s) && _jbyte(s) == UInt8('}')
                s.pos += 1
                value, have_result = _close!(stack), true
            else
                stack[end].key = _scan_member_key!(s)
                continue
            end
        else
            value, have_result = _scan_scalar!(s), true
        end

        have_result || continue

        # --- attach the finished value to its parent, or return it ---
        while true
            if isempty(stack)
                return value
            end
            frame = stack[end]
            if frame.isobject
                push!(frame.members, frame.key => value)
            else
                push!(frame.array, value)
            end

            _jskip!(s)
            _jeof(s) && _jfail(s, "unexpected end of input inside a " *
                      (frame.isobject ? "JSON object" : "JSON array"))
            c = _jbyte(s)
            if c == UInt8(',')
                s.pos += 1
                frame.isobject && (frame.key = _scan_member_key!(s))
                break                       # go read the next value
            elseif (frame.isobject && c == UInt8('}')) ||
                   (!frame.isobject && c == UInt8(']'))
                s.pos += 1
                value = _close!(stack)
                continue                    # this container is now a value
            else
                _jfail(s,
                    "expected ',' or '" * (frame.isobject ? "}" : "]") *
                    "' in a JSON " * (frame.isobject ? "object" : "array"))
            end
        end
    end
end

function _close!(stack::Vector{_JFrame})
    frame = pop!(stack)
    return frame.isobject ? frame.members : frame.array
end

function _scan_member_key!(s::JSONScanner)
    _jskip!(s)
    (!_jeof(s) && _jbyte(s) == UInt8('"')) ||
        _jfail(s, "expected a member name in a JSON object")
    key = _scan_string!(s)
    _jskip!(s)
    (!_jeof(s) && _jbyte(s) == UInt8(':')) ||
        _jfail(s, "expected ':' after the member name $(repr(key))")
    s.pos += 1
    return key
end

function _scan_scalar!(s::JSONScanner)
    b = _jbyte(s)
    b == UInt8('"') && return _scan_string!(s)
    (b == UInt8('-') || (UInt8('0') <= b <= UInt8('9'))) && return _scan_number!(s)
    _lit!(s, "true") && return true
    _lit!(s, "false") && return false
    _lit!(s, "null") && return nothing
    return _jfail(s, "unexpected character $(repr(Char(b))) where a JSON value was expected")
end

function _lit!(s::JSONScanner, word::String)
    n = ncodeunits(word)
    s.pos + n - 1 > ncodeunits(s.data) && return false
    for k in 1:n
        codeunit(s.data, s.pos + k - 1) == codeunit(word, k) || return false
    end
    s.pos += n
    return true
end

function _scan_number!(s::JSONScanner)
    start = s.pos
    isintegral = true
    _jbyte(s) == UInt8('-') && (s.pos += 1)

    # JSON forbids a leading zero followed by more digits, and that matters here:
    # accepting "01" would make two different documents mean the same thing.
    _jeof(s) && _jfail(s, "a JSON number needs at least one digit", start)
    if _jbyte(s) == UInt8('0')
        s.pos += 1
        !_jeof(s) && UInt8('0') <= _jbyte(s) <= UInt8('9') &&
            _jfail(s, "a JSON number may not have a leading zero", start)
    else
        d = 0
        while !_jeof(s) && UInt8('0') <= _jbyte(s) <= UInt8('9')
            s.pos += 1
            d += 1
        end
        d == 0 && _jfail(s, "a JSON number needs at least one digit", start)
    end

    if !_jeof(s) && _jbyte(s) == UInt8('.')
        isintegral = false
        s.pos += 1
        d = 0
        while !_jeof(s) && UInt8('0') <= _jbyte(s) <= UInt8('9')
            s.pos += 1
            d += 1
        end
        d == 0 && _jfail(s, "a JSON number needs a digit after '.'", start)
    end

    if !_jeof(s) && (_jbyte(s) == UInt8('e') || _jbyte(s) == UInt8('E'))
        isintegral = false
        s.pos += 1
        !_jeof(s) && (_jbyte(s) == UInt8('+') || _jbyte(s) == UInt8('-')) && (s.pos += 1)
        d = 0
        while !_jeof(s) && UInt8('0') <= _jbyte(s) <= UInt8('9')
            s.pos += 1
            d += 1
        end
        d == 0 && _jfail(s, "a JSON number needs a digit in its exponent", start)
    end

    return JSONNumber(_slice(s.data, start, s.pos - 1), isintegral)
end

function _scan_string!(s::JSONScanner)
    start = s.pos
    s.pos += 1                                  # opening quote

    # Fast path. The overwhelming majority of JSON strings contain no escape at
    # all, and for those the whole span can be copied in one go: no IOBuffer, no
    # growth, no byte-at-a-time `write`. Measured at 38 allocations per node
    # before this, against 20 for the XML reader on the same document, which is
    # what sent us looking here (docs/src/performance.md).
    n = ncodeunits(s.data)
    i = s.pos
    while i <= n
        b = codeunit(s.data, i)
        if b == UInt8('"')
            value = _slice(s.data, s.pos, i - 1)
            s.pos = i + 1
            return value
        elseif b == UInt8('\\')
            break                               # there is an escape; fall through
        elseif b < 0x20
            s.pos = i
            _jfail(s, "a raw control character is not allowed in a JSON string")
        end
        i += 1
    end
    i > n && _jfail(s, "unterminated JSON string", start)

    # Slow path, seeded with the bytes the scan above already proved plain.
    out = IOBuffer()
    write(out, _byteview(s.data, s.pos, i - 1))
    s.pos = i
    while true
        _jeof(s) && _jfail(s, "unterminated JSON string", start)
        b = _jbyte(s)
        if b == UInt8('"')
            s.pos += 1
            return String(take!(out))
        elseif b == UInt8('\\')
            s.pos += 1
            _jeof(s) && _jfail(s, "unterminated escape in a JSON string", start)
            e = _jbyte(s)
            s.pos += 1
            if e == UInt8('"')
                write(out, '"')
            elseif e == UInt8('\\')
                write(out, '\\')
            elseif e == UInt8('/')
                write(out, '/')
            elseif e == UInt8('b')
                write(out, '\b')
            elseif e == UInt8('f')
                write(out, '\f')
            elseif e == UInt8('n')
                write(out, '\n')
            elseif e == UInt8('r')
                write(out, '\r')
            elseif e == UInt8('t')
                write(out, '\t')
            elseif e == UInt8('u')
                write(out, _scan_escape_codepoint!(s))
            else
                _jfail(s, "unknown escape \\$(Char(e)) in a JSON string", s.pos - 1)
            end
        elseif b < 0x20
            _jfail(s, "a raw control character is not allowed in a JSON string")
        else
            write(out, b)
            s.pos += 1
        end
    end
end

function _scan_hex4!(s::JSONScanner)
    s.pos + 3 > ncodeunits(s.data) && _jfail(s, "a \\u escape needs four hex digits")
    v = UInt32(0)
    for _ in 1:4
        b = _jbyte(s)
        d = if UInt8('0') <= b <= UInt8('9')
            b - UInt8('0')
        elseif UInt8('a') <= b <= UInt8('f')
            b - UInt8('a') + 0x0a
        elseif UInt8('A') <= b <= UInt8('F')
            b - UInt8('A') + 0x0a
        else
            _jfail(s, "a \\u escape needs four hex digits")
        end
        v = (v << 4) | UInt32(d)
        s.pos += 1
    end
    return v
end

function _scan_escape_codepoint!(s::JSONScanner)
    at = s.pos
    hi = _scan_hex4!(s)
    if 0xd800 <= hi <= 0xdbff
        # A high surrogate must be followed by its low half; anything else would
        # produce an invalid Char and an exception outside the OpenMathError family.
        (s.pos + 1 <= ncodeunits(s.data) && _jbyte(s) == UInt8('\\') &&
         _jbyte(s, s.pos + 1) == UInt8('u')) ||
            _jfail(s, "a high surrogate escape must be followed by a low surrogate", at)
        s.pos += 2
        lo = _scan_hex4!(s)
        (0xdc00 <= lo <= 0xdfff) ||
            _jfail(s, "expected a low surrogate escape after a high surrogate", at)
        return Char(0x10000 + ((hi - 0xd800) << 10) + (lo - 0xdc00))
    end
    (0xdc00 <= hi <= 0xdfff) &&
        _jfail(s, "an unpaired low surrogate escape is not a character", at)
    return Char(hi)
end
