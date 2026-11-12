# SPDX-License-Identifier: MIT
#
# The XML event stream the three readers consume — the OpenMath XML reader, the
# Strict Content MathML reader and the Content Dictionary parser — built on
# `XML.jl` (decision D1, docs/src/design/xml-backend.md). This package does not
# parse XML itself any more.
#
# `XML.jl` reads the document into a `FlatNode` store at `wellformed = :strict`,
# which is where every XML 1.0 well-formedness rule is decided, including the
# one D1 turned on: an undeclared entity reference is a fatal error (§4.1). The
# stream below is then *lazy*: it walks the store with `eachchildnode`, whose
# state is an integer, and holds an explicit stack of open elements rather than
# recursing (REQ-SEC-002). An earlier adapter flattened the whole store into a
# vector of events first, and that — not `XML.jl` — is what made it 3× slower.
#
# What this layer adds to `XML.jl`, because this package promises more than
# well-formedness:
#
# - a document type declaration is refused outright (REQ-XML-009, SECURITY.md).
#   `XML.jl` accepts one and applies its internal subset, which is correct XML
#   and a weaker guarantee than this package makes;
# - nothing but an `OpenMathError` escapes (REQ-SEC-001). `XML.jl` raises
#   `ErrorException`; its message is kept and its type is not. It carries no
#   position, so such an error reports offset 1 — see upstream-bugs.md.

using XML: XML

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

const _FlatNode = XML.FlatNode
const _ChildIter = typeof(XML.eachchildnode(Base.parse(XML.FlatNode, "<a/>")))

# One open element: where its children are being read from, and what its end
# event will say. `fresh` stands for "no child read yet", because the iterator's
# initial state is internal to `XML.jl`.
struct _Open
    node::_FlatNode
    children::_ChildIter
    state::Int32
    fresh::Bool
    name::String
    endoffset::Int
end

mutable struct XMLPullParser
    data::String                 # the source `XML.jl` read, which spans index
    open::Vector{_Open}
    last::Union{Nothing, _FlatNode}   # the element whose start was just returned
    finished::Bool
end

function XMLPullParser(data::AbstractString)
    text = String(data)
    _check_utf8(text)
    doc = try
        Base.parse(XML.FlatNode, text; wellformed = :strict)
    catch err
        (err isa ErrorException || err isa ArgumentError) || rethrow()
        message = _xmljl_message(err)
        throw(OpenMathParseError("the document is not well-formed XML: " * message;
            offset = _xmljl_offset(message)))
    end
    source = XML.sourcetext(doc)
    root = _Open(doc, XML.eachchildnode(doc), Int32(0), true, "",
        ncodeunits(source) + 1)
    return XMLPullParser(String(source), _Open[root], nothing, false)
end

_xmljl_message(err) = first(sprint(showerror, err), 300)

# `XML.jl`'s tokenizer errors say "at position N"; its well-formedness errors say
# nothing about where. Use the position when there is one.
function _xmljl_offset(message::AbstractString)
    m = match(r"at position (\d+)", message)
    m === nothing && return 1
    digits = m.captures[1]
    digits === nothing && return 1
    n = tryparse(Int, digits)
    return n === nothing ? 1 : max(n, 1)
end

_offset(n::_FlatNode) = first(XML.sourcespan(n))

# An element's source ends with the `>` of its end tag. `XML.jl` v0.4.8 accepts
# an end tag cut off at the very end of the document — `<a>1</a` — at `:strict`
# (upstream-bugs.md), and its span then ends on the name instead.
function _check_closed(p::XMLPullParser, name::AbstractString, stop::Int)
    (1 <= stop <= ncodeunits(p.data) && codeunit(p.data, stop) == UInt8('>')) ||
        throw(OpenMathParseError("unterminated end tag </$(name)>"; offset = stop))
    return nothing
end

function next_event!(p::XMLPullParser)
    while true
        p.finished && return XMLDocumentEnd(ncodeunits(p.data) + 1)
        top = p.open[end]
        step = top.fresh ? iterate(top.children) : iterate(top.children, top.state)
        if step === nothing
            pop!(p.open)
            if isempty(p.open)
                p.finished = true
                return XMLDocumentEnd(ncodeunits(p.data) + 1)
            end
            _check_closed(p, top.name, top.endoffset)
            return XMLEndElement(top.name, top.endoffset)
        end
        node, state = step
        p.open[end] = _Open(top.node, top.children, state, false, top.name, top.endoffset)

        kind = XML.nodetype(node)
        if kind === XML.Element
            return _start!(p, node)
        elseif kind === XML.Text || kind === XML.CData
            return _characters!(p, node)
        elseif kind === XML.ProcessingInstruction
            # XML 1.0 §2.6 reserves the target `xml` in any case. `XML.jl`
            # v0.4.8 accepts `<?XML …?>` at `:strict` (upstream-bugs.md).
            target = XML.tag(node)
            (target !== nothing && lowercase(target) == "xml") && throw(
                OpenMathParseError(
                "the processing-instruction target $(repr(String(target))) is " *
                "reserved (XML 1.0 §2.6)"; offset = _offset(node)))
        elseif kind === XML.DTD
            throw(OpenMathParseError(
                "DOCTYPE declarations are not accepted (standard §3.1; see SECURITY.md)";
                offset = _offset(node)))
        end
        # Comments, processing instructions and the XML declaration carry no
        # OpenMath content.
    end
end

# Adjacent text and CDATA siblings are one run of character data to a reader,
# and `XML.jl` keeps them as separate nodes. Peeking is free: the child iterator
# is a pure function of its state, so a sibling that is not text is simply read
# again by the next call.
function _characters!(p::XMLPullParser, node::_FlatNode)
    offset = _offset(node)
    first_value = XML.value(node)
    top = p.open[end]
    step = iterate(top.children, top.state)
    _is_text(step) || return XMLCharacters(String(something(first_value, "")), offset)
    buf = IOBuffer()
    first_value === nothing || write(buf, first_value)
    state = top.state
    while _is_text(step)
        sibling, state = step
        v = XML.value(sibling)
        v === nothing || write(buf, v)
        step = iterate(top.children, state)
    end
    p.open[end] = _Open(top.node, top.children, state, false, top.name, top.endoffset)
    return XMLCharacters(String(take!(buf)), offset)
end

function _is_text(step)
    step === nothing && return false
    kind = XML.nodetype(step[1])
    return kind === XML.Text || kind === XML.CData
end

function _start!(p::XMLPullParser, node::_FlatNode)
    tag = XML.tag(node)
    # An element always has a tag; `XML.tag` is typed for every node kind.
    tag === nothing && throw(OpenMathParseError("an element without a name";
        offset = _offset(node)))
    name = _intern(tag)
    attributes = XMLAttribute[]
    pairs = XML.attributes(node)
    if pairs !== nothing
        sizehint!(attributes, length(pairs))
        for (k, v) in pairs
            push!(attributes, XMLAttribute(_intern(k), String(v)))
        end
    end
    span = XML.sourcespan(node)
    # `<a/>` and `<a></a>` are one node to `XML.jl` and two shapes to a reader
    # deciding whether to push a frame. The last two bytes of the span say which.
    selfclosed = _is_selfclosed(p.data, span)
    p.last = node
    if !selfclosed
        push!(p.open, _Open(node, XML.eachchildnode(node), Int32(0), true, name,
            last(span)))
    end
    return XMLStartElement(name, attributes, selfclosed, first(span))
end

function _is_selfclosed(data::String, span::UnitRange{Int})
    stop = last(span)
    stop >= first(span) + 1 || return false
    return codeunit(data, stop) == UInt8('>') && codeunit(data, stop - 1) == UInt8('/')
end

"""
    read_raw_until_end!(p, name) -> String

The verbatim source between the tags of the element whose start was just
returned, leaving the stream positioned after its end tag. Used for
`OMFOREIGN`, whose content is by definition not OpenMath and must survive
untouched.
"""
function read_raw_until_end!(p::XMLPullParser, name::AbstractString)
    node = _consume_last!(p, name)
    kids = XML.children(node)
    isempty(kids) && return ""
    from = first(XML.sourcespan(first(kids)))
    to = last(XML.sourcespan(last(kids)))
    return _slice(p.data, from, to)
end

# The full source of the element whose start tag was just returned, its own tags
# included, leaving the stream positioned after it.
function element_source!(p::XMLPullParser, ev::XMLStartElement)
    node = _consume_last!(p, ev.name)
    span = XML.sourcespan(node)
    return _slice(p.data, first(span), last(span))
end

# The element whose start was just returned, with its subtree skipped: its frame,
# if it has one, is dropped, so its end event is never produced.
function _consume_last!(p::XMLPullParser, name::AbstractString)
    node = p.last
    node === nothing && throw(OpenMathParseError("unterminated <$(name)>"; offset = 1))
    p.last = nothing
    if !isempty(p.open) && p.open[end].node == node && length(p.open) > 1
        top = pop!(p.open)
        _check_closed(p, top.name, top.endoffset)
    end
    return node
end

# Element and attribute names the readers compare against, shared rather than
# copied once per occurrence.
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

# A flat, concretely-typed vector scanned with a length pre-filter: with forty
# entries, anything cleverer costs more than it saves.
const _INTERNED_LIST = collect(String, _INTERNED_NAMES)

function _intern(s::AbstractString)
    len = ncodeunits(s)
    @inbounds for c in _INTERNED_LIST
        ncodeunits(c) == len && c == s && return c
    end
    return String(s)
end
