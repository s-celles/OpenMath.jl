# SPDX-License-Identifier: MIT
#
# Helpers both XML tokenizer backends need: the UTF-8 gate and qualified-name
# splitting. Extracted when the `XML.jl` backend was added (decision D1), so the
# two backends share one definition rather than drifting apart in the one place
# where disagreeing would be invisible.

# XML 1.0 §2.2 requires every character in a document to be a legal Unicode
# character, so a malformed byte sequence is a lexical error and saying so is
# correct. Saying so *here* is what matters: the readers call `strip` on element
# text, `strip` calls `isspace`, and `isspace` on an invalid `Char` raises
# `Base.InvalidCharError` — a Julia exception escaping a parser that guarantees
# only `OpenMathError` does (REQ-SEC-001).
#
# The check is one pass over the bytes and only on construction, so it costs a
# scan of the input once rather than a branch at every character.
function _check_utf8(text::String)
    isvalid(text) && return nothing
    # Report where, because "the document is not UTF-8" is not actionable on a
    # megabyte of it. Iterating with `pairs` decodes the same way the rest of
    # Julia will, so the first character it reports as invalid is the first one
    # that would have raised.
    for (i, c) in pairs(text)
        isvalid(c) || throw(OpenMathParseError(
            "the input is not valid UTF-8; XML 1.0 §2.2 admits only legal " *
            "Unicode characters"; offset = i))
    end
    throw(OpenMathParseError("the input is not valid UTF-8"; offset = 1))
end

"""
    localname(qname) -> String

The part of a qualified XML name after the colon.
"""
function localname(q::AbstractString)
    (i = findfirst(==(':'), q);
        i === nothing ? String(q) : String(@view q[nextind(q, i):end]))
end

"""
    prefix(qname) -> String

The namespace prefix of a qualified XML name, or `""` when it has none.
"""
function prefix(q::AbstractString)
    (i = findfirst(==(':'), q); i === nothing ? "" : String(@view q[1:prevind(q, i)]))
end
