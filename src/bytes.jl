# SPDX-License-Identifier: MIT
#
# Byte-level helpers shared by the scanners.
#
# These lived in `src/xml/tokenizer.jl` and were used from `src/json/scanner.jl`,
# which meant the JSON scanner depended on a definition inside the XML
# tokenizer — invisible until the tokenizer became replaceable (decision D1) and
# taking it away broke JSON. They are about bytes, not about XML.

@inline _is_space(b::UInt8) = b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d

# Slice an inclusive *byte* range. `SubString` cannot be used here: it indexes by
# character boundary, so `SubString(s, from, i - 1)` throws a StringIndexError
# whenever the byte before `i` is a continuation byte — that is, on any
# multi-byte character. Going through the code units is correct for every input,
# including malformed UTF-8, which must pass through as opaque bytes rather than
# throw (REQ-SEC-001).
#
# The bytes are copied straight out of `s`, not through a view: on Julia 1.10,
# 1.11 and 1.12, `String(@view codeunits(s)[from:to])` takes time proportional
# to all of `s` (`Base.dataids` hashes the string), so a scanner slicing every
# string out of a large document went quadratic — the 23 MB OSR rules took about
# two hours to read instead of one second. `String(codeunits(s)[from:to])` is
# linear but allocates an intermediate vector, which the allocation budget
# catches. `unsafe_string` makes the one allocation the result needs, on every
# Julia; the range is checked first, which is all that is unsafe about it, and
# `GC.@preserve` keeps `s` alive while its pointer is read.
@inline function _slice(s::String, from::Int, to::Int)
    to < from && return ""
    (1 <= from && to <= ncodeunits(s)) || throw(BoundsError(s, from:to))
    return GC.@preserve s unsafe_string(pointer(s, from), to - from + 1)
end

@inline _byteview(s::String, from::Int, to::Int) = @view codeunits(s)[from:max(to, from - 1)]
