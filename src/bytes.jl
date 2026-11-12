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
@inline _slice(s::String, from::Int, to::Int) = to < from ? "" :
                                                String(@view codeunits(s)[from:to])

@inline _byteview(s::String, from::Int, to::Int) = @view codeunits(s)[from:max(to, from - 1)]
