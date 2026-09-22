# SPDX-License-Identifier: MIT
#
# A pull tokenizer for the OpenMath XML subset (standard §3.1). See decision D1
# in docs/src/design/xml-backend.md for why this is purpose-built rather than a
# dependency.
#
# What it handles: elements, attributes, character data, CDATA sections,
# comments, processing instructions, the five predefined entities and numeric
# character references.
#
# What it refuses, by never implementing it: document type declarations, entity
# declarations and entity references other than the predefined five. The
# billion-laughs class of attack is therefore absent rather than mitigated
# (REQ-XML-009).
#
# Scanning is byte-oriented so that every error can carry a byte offset
# (REQ-API-007). That is safe on UTF-8: continuation bytes are all ≥ 0x80 and can
# never be mistaken for an ASCII delimiter. It also means malformed UTF-8 passes
# through as opaque bytes instead of throwing (REQ-SEC-001).

struct XMLAttribute
    name::String
    value::String
end

abstract type XMLEvent end

struct XMLStartElement <: XMLEvent
    name::String
    attributes::Vector{XMLAttribute}
    selfclosed::Bool
    offset::Int
end

struct XMLEndElement <: XMLEvent
    name::String
    offset::Int
end

struct XMLCharacters <: XMLEvent
    text::String
    offset::Int
end

struct XMLDocumentEnd <: XMLEvent
    offset::Int
end

mutable struct XMLPullParser
    data::String
    pos::Int
    open::Vector{String}
    finished::Bool
end

function XMLPullParser(data::AbstractString)
    text = String(data)
    _check_utf8(text)
    return XMLPullParser(text, 1, String[], false)
end

@inline _at(p::XMLPullParser) = ncodeunits(p.data)
@inline _byte(p::XMLPullParser, i::Int) = codeunit(p.data, i)
@inline _eof(p::XMLPullParser, i::Int = p.pos) = i > ncodeunits(p.data)

function _fail(p::XMLPullParser, msg::AbstractString, at::Int = p.pos)
    throw(OpenMathParseError(msg; offset = at))
end

@inline function _lookahead(p::XMLPullParser, s::String, i::Int = p.pos)
    n = ncodeunits(s)
    i + n - 1 > ncodeunits(p.data) && return false
    for k in 1:n
        codeunit(p.data, i + k - 1) == codeunit(s, k) || return false
    end
    return true
end

# XML NameStartChar/NameChar, restricted to what a byte scan can decide. Any byte
# ≥ 0x80 is accepted here and rejected later by `checkname` if it reaches a name
# that the OpenMath grammar constrains.
@inline _is_name_byte(b::UInt8) = (UInt8('a') <= b <= UInt8('z')) ||
                                  (UInt8('A') <= b <= UInt8('Z')) ||
                                  (UInt8('0') <= b <= UInt8('9')) || b == UInt8('_') ||
                                  b == UInt8(':') ||
                                  b == UInt8('-') || b == UInt8('.') || b >= 0x80

"""
    next_event!(p::XMLPullParser) -> XMLEvent

The next token. Comments, processing instructions and the XML declaration are
skipped. Adjacent character data, CDATA sections and entity references merge into
a single [`XMLCharacters`](@ref) event.
"""
function next_event!(p::XMLPullParser)
    while true
        if _eof(p)
            p.finished && return XMLDocumentEnd(p.pos)
            if !isempty(p.open)
                _fail(p, "unexpected end of document: <$(p.open[end])> is not closed")
            end
            p.finished = true
            return XMLDocumentEnd(p.pos)
        end

        if _byte(p, p.pos) != UInt8('<')
            return _read_characters!(p)
        end

        if _lookahead(p, "<![CDATA[")
            return _read_characters!(p)
        elseif _lookahead(p, "<!--")
            _skip_comment!(p)
        elseif _lookahead(p, "<?")
            _skip_pi!(p)
        elseif _lookahead(p, "<!DOCTYPE")
            _fail(p, "DOCTYPE declarations are not accepted (standard §3.1; " *
                     "see SECURITY.md)")
        elseif _lookahead(p, "<!ENTITY") || _lookahead(p, "<!ELEMENT") ||
               _lookahead(p, "<!ATTLIST") || _lookahead(p, "<!NOTATION")
            _fail(p, "entity and markup declarations are not accepted " *
                     "(standard §3.1; see SECURITY.md)")
        elseif _lookahead(p, "<!")
            _fail(p, "unsupported markup declaration")
        elseif _lookahead(p, "</")
            return _read_end_tag!(p)
        else
            return _read_start_tag!(p)
        end
    end
end

function _skip_comment!(p::XMLPullParser)
    start = p.pos
    i = p.pos + 4
    while true
        i + 2 > ncodeunits(p.data) && _fail(p, "unterminated comment", start)
        if codeunit(p.data, i) == UInt8('-') && codeunit(p.data, i + 1) == UInt8('-') &&
           codeunit(p.data, i + 2) == UInt8('>')
            p.pos = i + 3
            return nothing
        end
        i += 1
    end
end

function _skip_pi!(p::XMLPullParser)
    start = p.pos
    i = p.pos + 2
    while true
        i + 1 > ncodeunits(p.data) && _fail(p, "unterminated processing instruction", start)
        if codeunit(p.data, i) == UInt8('?') && codeunit(p.data, i + 1) == UInt8('>')
            p.pos = i + 2
            return nothing
        end
        i += 1
    end
end

# Every element and attribute name this package's readers compare against. A
# name scanned out of a document that matches one is returned *as this literal*,
# so the overwhelmingly common case allocates nothing: an allocation profile put
# the name slice at the top of the XML reader, 15 % of everything it allocates,
# and almost every one of those strings is compared against a constant and
# dropped.
#
# This is **not** the interning `SECURITY.md` forbids. That rule is about names a
# *document* chooses — variables and symbols — which are unbounded and
# attacker-controlled, so retaining them is a memory-exhaustion vector. These are
# markup names from a closed table that is already in the binary; nothing a
# document supplies is retained, and a name outside the table is allocated as
# before. `test/unit/xml_tokenizer.jl` asserts the table still covers both
# readers' element sets, so it cannot quietly stop applying.
const _INTERNED_NAMES = (
    # OpenMath XML elements (§3.1)
    "OMOBJ", "OMI", "OMF", "OMSTR", "OMB", "OMV", "OMS", "OMA",
    "OMBIND", "OMBVAR", "OME", "OMATTR", "OMATP", "OMFOREIGN", "OMR",
    # Strict Content MathML elements (MathML 4 §4.1.3)
    "math", "cn", "ci", "cs", "cbytes", "csymbol", "apply", "bind",
    "bvar", "cerror", "semantics", "annotation-xml", "share",
    # attributes
    "id", "name", "cd", "cdbase", "href", "encoding", "version",
    "xmlns", "type", "base", "dec", "hex", "order")

# Grouped by length so a scan compares bytes only against candidates that could
# match. With the table this small that is the whole of the optimisation; a
# hash would cost more than it saves.
# A flat, concretely-typed vector scanned with a length pre-filter. Two earlier
# shapes were type-unstable — a vector of `NTuple{2,Any}`, then a heterogeneous
# tuple of tuples indexed by a runtime length — and each boxed on every name
# scan, making reading *slower* than the allocation the table was meant to
# remove. With forty entries and a length comparison first, a linear scan is the
# whole of it; anything cleverer costs more than it saves.
const _INTERNED_LIST = collect(String, _INTERNED_NAMES)
const _INTERNED_LENGTHS = Int[ncodeunits(n) for n in _INTERNED_LIST]

function _interned(data::String, from::Int, to::Int)
    len = to - from + 1
    @inbounds for j in eachindex(_INTERNED_LIST)
        _INTERNED_LENGTHS[j] == len || continue
        c = _INTERNED_LIST[j]
        same = true
        for k in 1:len
            if codeunit(data, from + k - 1) != codeunit(c, k)
                same = false
                break
            end
        end
        same && return c
    end
    return nothing
end

function _read_name!(p::XMLPullParser)
    start = p.pos
    i = p.pos
    while !_eof(p, i) && _is_name_byte(_byte(p, i))
        i += 1
    end
    i == start && _fail(p, "expected an element or attribute name", start)
    p.pos = i
    shared = _interned(p.data, start, i - 1)
    shared === nothing || return shared
    return _slice(p.data, start, i - 1)
end

function _skip_space!(p::XMLPullParser)
    while !_eof(p) && _is_space(_byte(p, p.pos))
        p.pos += 1
    end
    return nothing
end

function _read_start_tag!(p::XMLPullParser)
    offset = p.pos
    p.pos += 1                      # '<'
    name = _read_name!(p)
    attrs = XMLAttribute[]
    while true
        _skip_space!(p)
        _eof(p) && _fail(p, "unterminated start tag <$name>", offset)
        b = _byte(p, p.pos)
        if b == UInt8('>')
            p.pos += 1
            push!(p.open, name)
            return XMLStartElement(name, attrs, false, offset)
        elseif b == UInt8('/')
            _lookahead(p, "/>") || _fail(p, "expected '/>' in <$name>")
            p.pos += 2
            return XMLStartElement(name, attrs, true, offset)
        end
        push!(attrs, _read_attribute!(p, name, offset))
    end
end

function _read_attribute!(p::XMLPullParser, element::String, tagoffset::Int)
    at = p.pos
    name = _read_name!(p)
    _skip_space!(p)
    (!_eof(p) && _byte(p, p.pos) == UInt8('=')) ||
        _fail(p, "attribute $(repr(name)) of <$element> has no value", at)
    p.pos += 1
    _skip_space!(p)
    _eof(p) && _fail(p, "attribute $(repr(name)) of <$element> has no value", at)
    q = _byte(p, p.pos)
    (q == UInt8('"') || q == UInt8('\'')) ||
        _fail(p, "attribute $(repr(name)) of <$element> must be quoted", p.pos)
    p.pos += 1
    start = p.pos
    i = p.pos
    while true
        _eof(p, i) && _fail(p, "unterminated attribute value in <$element>", tagoffset)
        _byte(p, i) == q && break
        i += 1
    end
    raw = _slice(p.data, start, i - 1)
    p.pos = i + 1
    return XMLAttribute(name, _unescape(p, raw, start))
end

function _read_end_tag!(p::XMLPullParser)
    offset = p.pos
    p.pos += 2                      # '</'
    name = _read_name!(p)
    _skip_space!(p)
    (!_eof(p) && _byte(p, p.pos) == UInt8('>')) ||
        _fail(p, "unterminated end tag </$name>", offset)
    p.pos += 1
    isempty(p.open) && _fail(p, "end tag </$name> without a matching start tag", offset)
    expected = pop!(p.open)
    expected == name ||
        _fail(p, "end tag </$name> does not match <$expected>", offset)
    return XMLEndElement(name, offset)
end

function _read_characters!(p::XMLPullParser)
    offset = p.pos
    out = IOBuffer()
    while true
        # Raw run up to the next '<' or '&'.
        start = p.pos
        i = p.pos
        while !_eof(p, i)
            b = _byte(p, i)
            (b == UInt8('<') || b == UInt8('&')) && break
            i += 1
        end
        i > start && write(out, _byteview(p.data, start, i - 1))
        p.pos = i
        _eof(p) && break
        if _byte(p, p.pos) == UInt8('&')
            write(out, _read_reference!(p))
        elseif _lookahead(p, "<![CDATA[")
            write(out, _read_cdata!(p))
        else
            break
        end
    end
    return XMLCharacters(String(take!(out)), offset)
end

function _read_cdata!(p::XMLPullParser)
    start = p.pos
    p.pos += 9                      # "<![CDATA["
    from = p.pos
    i = p.pos
    while true
        i + 2 > ncodeunits(p.data) && _fail(p, "unterminated CDATA section", start)
        if codeunit(p.data, i) == UInt8(']') && codeunit(p.data, i + 1) == UInt8(']') &&
           codeunit(p.data, i + 2) == UInt8('>')
            p.pos = i + 3
            return _byteview(p.data, from, i - 1)
        end
        i += 1
    end
end

const _PREDEFINED = Dict("lt" => "<", "gt" => ">", "amp" => "&",
    "quot" => "\"", "apos" => "'")

function _read_reference!(p::XMLPullParser)
    start = p.pos
    i = p.pos + 1
    while !_eof(p, i) && _byte(p, i) != UInt8(';') && _byte(p, i) != UInt8('<') &&
          !_is_space(_byte(p, i))
        i += 1
    end
    (!_eof(p, i) && _byte(p, i) == UInt8(';')) ||
        _fail(p, "unterminated entity reference", start)
    body = _slice(p.data, start + 1, i - 1)
    p.pos = i + 1

    if startswith(body, '#')
        digits = SubString(body, 2)
        hex = startswith(digits, 'x') || startswith(digits, 'X')
        hex && (digits = SubString(digits, 2))
        isempty(digits) && _fail(p, "empty character reference", start)
        code = tryparse(UInt32, digits; base = hex ? 16 : 10)
        code === nothing && _fail(p, "malformed character reference &$body;", start)
        # Reject anything outside the Unicode scalar range, including surrogates:
        # building a Char from those would throw outside the OpenMathError family.
        (code > 0x10ffff || (0xd800 <= code <= 0xdfff)) &&
            _fail(p, "character reference &$body; is not a Unicode scalar value", start)
        return string(Char(code))
    end

    v = get(_PREDEFINED, String(body), nothing)
    v === nothing && _fail(p,
        "undeclared entity reference &$body;; only the five predefined entities " *
        "are accepted (standard §3.1; see SECURITY.md)", start)
    return v
end

"""
    read_raw_until_end!(p::XMLPullParser, name) -> String

The verbatim source between the current position and the end tag matching `name`,
honouring nesting. Used for `OMFOREIGN`, whose content is by definition not
OpenMath and must survive untouched.
"""
# The full source of the element whose start tag was just returned, its own tags
# included, leaving the parser positioned after it. Backend-neutral: the Content
# Dictionary parser used to compute this from `p.data` and `p.pos` directly,
# which is a coupling to how a tokenizer happens to track position.
function element_source!(p::XMLPullParser, ev::XMLStartElement)
    ev.selfclosed && return _slice(p.data, ev.offset, p.pos - 1)
    read_raw_until_end!(p, ev.name)
    return _slice(p.data, ev.offset, p.pos - 1)
end

function read_raw_until_end!(p::XMLPullParser, name::AbstractString)
    start = p.pos
    depth = 1
    from = p.pos
    while true
        _eof(p) && _fail(p, "unterminated <$name>", start)
        if _lookahead(p, "<!--")
            _skip_comment!(p)
            continue
        elseif _lookahead(p, "<![CDATA[")
            _read_cdata!(p)
            continue
        elseif _lookahead(p, "</")
            mark = p.pos
            p.pos += 2
            closing = _read_name!(p)
            _skip_space!(p)
            (!_eof(p) && _byte(p, p.pos) == UInt8('>')) ||
                _fail(p, "unterminated end tag </$closing>", mark)
            p.pos += 1
            if closing == name
                depth -= 1
                if depth == 0
                    isempty(p.open) || pop!(p.open)
                    return _slice(p.data, from, mark - 1)
                end
            end
            continue
        elseif _byte(p, p.pos) == UInt8('<')
            mark = p.pos
            p.pos += 1
            opening = _read_name!(p)
            # Walk to the end of the tag without interpreting it.
            while true
                _eof(p) && _fail(p, "unterminated start tag <$opening>", mark)
                if _lookahead(p, "/>")
                    p.pos += 2
                    break
                elseif _byte(p, p.pos) == UInt8('>')
                    p.pos += 1
                    opening == name && (depth += 1)
                    break
                elseif _byte(p, p.pos) == UInt8('"') || _byte(p, p.pos) == UInt8('\'')
                    q = _byte(p, p.pos)
                    p.pos += 1
                    while !_eof(p) && _byte(p, p.pos) != q
                        p.pos += 1
                    end
                    _eof(p) && _fail(p, "unterminated attribute value", mark)
                    p.pos += 1
                else
                    p.pos += 1
                end
            end
            continue
        end
        p.pos += 1
    end
end

function _unescape(p::XMLPullParser, s::AbstractString, at::Int)
    occursin('&', s) || return String(s)
    sub = XMLPullParser(String(s))
    out = IOBuffer()
    while !_eof(sub)
        if _byte(sub, sub.pos) == UInt8('&')
            try
                write(out, _read_reference!(sub))
            catch err
                err isa OpenMathParseError || rethrow()
                throw(OpenMathParseError(err.message; offset = at + sub.pos - 1))
            end
        else
            start = sub.pos
            i = sub.pos
            while !_eof(sub, i) && _byte(sub, i) != UInt8('&')
                i += 1
            end
            write(out, _byteview(sub.data, start, i - 1))
            sub.pos = i
        end
    end
    return String(take!(out))
end
