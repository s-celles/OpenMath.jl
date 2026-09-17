# SPDX-License-Identifier: MIT
#
# The base64 codec used by OMB in the XML encoding (standard §3.1.1).
#
# Written here rather than taken from the Base64 stdlib because the rules that
# matter are the XML ones: whitespace inside the encoded form is insignificant and
# must be skipped, and every rejection has to carry the byte offset that
# REQ-API-007 requires.

const _B64_ALPHABET = UInt8.(collect("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))

const _B64_REVERSE = let t = fill(Int8(-1), 256)
    for (i, c) in enumerate(_B64_ALPHABET)
        t[c + 1] = Int8(i - 1)
    end
    t
end

"""
    base64_encode(bytes::AbstractVector{UInt8}) -> String

Encode `bytes` as base64 with `=` padding, as the XML encoding of `OMB` requires.
"""
function base64_encode(bytes::AbstractVector{UInt8})
    n = length(bytes)
    out = IOBuffer(; sizehint = 4 * cld(n, 3))
    i = firstindex(bytes)
    last = i + n - 1
    while i + 2 <= last
        w = (UInt32(bytes[i]) << 16) | (UInt32(bytes[i + 1]) << 8) | UInt32(bytes[i + 2])
        write(out, _B64_ALPHABET[((w >> 18) & 0x3f) + 1],
            _B64_ALPHABET[((w >> 12) & 0x3f) + 1],
            _B64_ALPHABET[((w >> 6) & 0x3f) + 1],
            _B64_ALPHABET[(w & 0x3f) + 1])
        i += 3
    end
    rem = last - i + 1
    if rem == 1
        w = UInt32(bytes[i]) << 16
        write(out, _B64_ALPHABET[((w >> 18) & 0x3f) + 1],
            _B64_ALPHABET[((w >> 12) & 0x3f) + 1], UInt8('='), UInt8('='))
    elseif rem == 2
        w = (UInt32(bytes[i]) << 16) | (UInt32(bytes[i + 1]) << 8)
        write(out, _B64_ALPHABET[((w >> 18) & 0x3f) + 1],
            _B64_ALPHABET[((w >> 12) & 0x3f) + 1],
            _B64_ALPHABET[((w >> 6) & 0x3f) + 1], UInt8('='))
    end
    return String(take!(out))
end

"""
    base64_decode(s::AbstractString; offset = 0) -> Vector{UInt8}

Decode base64, ignoring whitespace. `offset` is added to the reported position so
that an error can point into the enclosing document rather than into the
substring. Raises [`OpenMathParseError`](@ref) on an invalid alphabet, a
misplaced `=`, or a length that is not a multiple of four.
"""
function base64_decode(s::AbstractString; offset::Int = 0)
    # Significant characters, with the position each came from.
    chars = UInt8[]
    at = Int[]
    for i in 1:ncodeunits(s)
        b = codeunit(s, i)
        (b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d) && continue
        push!(chars, b)
        push!(at, i)
    end

    n = length(chars)
    n == 0 && return UInt8[]
    if n % 4 != 0
        throw(OpenMathParseError("base64 length $n is not a multiple of 4";
            offset = offset + at[end]))
    end

    pad = 0
    for i in 1:n
        if chars[i] == UInt8('=')
            # Padding is legal only in the final quantum, at position 3 or 4.
            (i > n - 2) || throw(OpenMathParseError(
                "base64 padding '=' before the final quantum";
                offset = offset + at[i]))
            pad += 1
        elseif pad > 0
            throw(OpenMathParseError("base64 character after padding";
                offset = offset + at[i]))
        elseif _B64_REVERSE[chars[i] + 1] < 0
            throw(OpenMathParseError(
                "invalid base64 character $(repr(Char(chars[i])))";
                offset = offset + at[i]))
        end
    end
    pad == 1 && chars[n] != UInt8('=') &&
        throw(OpenMathParseError(
            "base64 padding must be at the end"; offset = offset + at[n]))

    out = Vector{UInt8}(undef, 3 * (n ÷ 4) - pad)
    o = 1
    for g in 0:((n ÷ 4) - 1)
        i = 4g + 1
        c1 = UInt32(_B64_REVERSE[chars[i] + 1])
        c2 = UInt32(_B64_REVERSE[chars[i + 1] + 1])
        c3 = chars[i + 2] == UInt8('=') ? UInt32(0) : UInt32(_B64_REVERSE[chars[i + 2] + 1])
        c4 = chars[i + 3] == UInt8('=') ? UInt32(0) : UInt32(_B64_REVERSE[chars[i + 3] + 1])
        w = (c1 << 18) | (c2 << 12) | (c3 << 6) | c4
        o <= length(out) && (out[o] = UInt8((w >> 16) & 0xff); o += 1)
        o <= length(out) && (out[o] = UInt8((w >> 8) & 0xff); o += 1)
        o <= length(out) && (out[o] = UInt8(w & 0xff); o += 1)
    end
    return out
end
