# SPDX-License-Identifier: MIT
#
# The XML.jl-backed tokenizer (decision D1, re-opened 2026-09-21).
#
# This is an *evaluation* backend, not a replacement yet. It presents exactly the
# event surface `src/xml/tokenizer.jl` presents — `XMLPullParser`, `next_event!`,
# `read_raw_until_end!` and the five event types — so the three readers built on
# that surface (XML, Strict Content MathML, and the Content Dictionary parser)
# run unchanged. The comparison is then about the tokenizer and nothing else.
#
# Why an adapter rather than rewriting the readers onto `FlatNode` directly: the
# question to answer first is whether `XML.jl` at `wellformed = :strict` gives
# the guarantees this package needs. Rewriting three readers before knowing that
# would be answering the expensive question first.
#
# The load-bearing difference, and it is not hidden by the adapter: `XML.jl`'s
# well-formedness levels apply to `Node` and `FlatNode`, which **materialise the
# whole tree** before anything is handed back. Our own tokenizer is a pull
# parser, so `max_depth` and `max_nodes` stop hostile input part-way. Here the
# tree exists before the first event is read, and the budgets can only be checked
# afterwards. `OPENMATH_MAX_BYTES` is therefore the only limit that still bites
# before the work is done, and it is checked here rather than by the readers.

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

# `raw` and `skip` are filled for start events only: `read_raw_until_end!` needs
# the verbatim inner source of an element and the index of the event after its
# matching end tag. Both are known while flattening and would cost a second
# traversal to recover later.
mutable struct XMLPullParser
    data::String
    events::Vector{XMLEvent}
    inner::Vector{UnitRange{Int}}   # verbatim span between an element's tags
    skip::Vector{Int}
    pos::Int
end

function XMLPullParser(data::AbstractString)
    text = String(data)
    _check_utf8(text)
    # The one budget that can still be enforced before the work happens.
    check_limit(:max_bytes, ncodeunits(text), limits().max_bytes)

    doc = try
        XML.parse(XML.FlatNode, text; wellformed = :strict)
    catch err
        err isa OpenMathError && rethrow()
        throw(OpenMathParseError(_xmljl_message(err); offset = 1))
    end

    events = XMLEvent[]
    inner = UnitRange{Int}[]
    skip = Int[]
    _flatten!(events, inner, skip, text, doc)
    push!(events, XMLDocumentEnd(ncodeunits(text) + 1))
    push!(inner, 1:0)
    push!(skip, 0)
    return XMLPullParser(text, events, inner, skip, 1)
end

# `XML.jl` raises its own error types. They carry the right information and the
# wrong supertype: REQ-SEC-001 promises that nothing outside `OpenMathError`
# escapes a parser, so the message is kept and the type is not.
function _xmljl_message(err)
    text = sprint(showerror, err)
    return "the document is not well-formed XML: " * first(text, 300)
end

# An **explicit stack**, like every other traversal in this package (REQ-SEC-002).
# The first version of this walked recursively and a 1.6 MiB document raised
# `StackOverflowError` — a Julia exception escaping a parser, and the one Julia
# cannot reliably catch. Writing the adapter is not an exemption from the rule
# the readers follow.
struct _XJFrame
    node::Any
    start::Int          # index of this element's start event, 0 for a child visit
    tag::String
    endoffset::Int
end

function _flatten!(events, inner, skip, source::String, root)
    todo = _XJFrame[_XJFrame(root, 0, "", 0)]
    while !isempty(todo)
        item = pop!(todo)
        if item.start != 0
            # The closing half of an element already opened.
            push!(events, XMLEndElement(item.tag, item.endoffset))
            push!(inner, 1:0)
            push!(skip, 0)
            skip[item.start] = length(events) + 1
            continue
        end

        node = item.node
        t = XML.nodetype(node)
        if t === XML.Document
            for c in Iterators.reverse(XML.children(node))
                push!(todo, _XJFrame(c, 0, "", 0))
            end
            continue
        elseif t === XML.Text || t === XML.CData
            # Entity references are already expanded by `XML.jl`, and at
            # `:strict` an undeclared one has been refused rather than passed
            # through as text — which is the whole reason this backend exists.
            value = XML.value(node)
            value === nothing && continue
            push!(events, XMLCharacters(String(value), _offset(node)))
            push!(inner, 1:0)
            push!(skip, 0)
            continue
        elseif t === XML.DTD
            # `SECURITY.md` promises DTDs are refused outright, and the
            # hand-written tokenizer refuses them. `XML.jl` accepts a DTD and,
            # since #139, expands the entities its internal subset declares —
            # correct XML, and a weaker guarantee than this package makes. Two
            # corpus items in `invalid/` assert the refusal; they caught this.
            throw(OpenMathParseError(
                "a document type declaration is not accepted; OpenMath documents " *
                "need no DTD and accepting one widens the attack surface";
                offset = _offset(node)))
        elseif t !== XML.Element
            # Comments, processing instructions and the XML declaration carry no
            # OpenMath content. The readers never saw them from the hand-written
            # tokenizer either, which skipped them while scanning.
            continue
        end

        tag = String(XML.tag(node))
        attrs = XMLAttribute[]
        a = XML.attributes(node)
        if a !== nothing
            for (k, v) in a
                push!(attrs, XMLAttribute(String(k), String(v)))
            end
        end
        kids = XML.children(node)
        span = XML.sourcespan(node)
        selfclosed = isempty(kids) && _is_selfclosed(source, span)

        start = length(events) + 1
        push!(events, XMLStartElement(tag, attrs, selfclosed, first(span)))
        # A *span*, not the substring. Materialising every element's inner text
        # here is quadratic on a deeply nested document — each element's inner
        # text is nearly the whole document — and cost 6.6 GB on a 322 KiB input
        # before it was noticed. Only `read_raw_until_end!` needs the characters,
        # and only for `OMFOREIGN`.
        push!(inner, isempty(kids) ? (1:0) : _inner_span(kids))
        push!(skip, 0)

        if selfclosed
            skip[start] = length(events) + 1
        else
            push!(todo, _XJFrame(nothing, start, tag, last(span)))
        end
        for c in Iterators.reverse(kids)
            push!(todo, _XJFrame(c, 0, "", 0))
        end
    end
    return nothing
end

# `<a/>` and `<a></a>` are the same node to `XML.jl`, and not to a reader that
# decides whether to push a frame. The source says which, and it is decided from
# the last two bytes of the span rather than by slicing it: the slice is the
# whole element, which on a nested document is most of the file.
function _is_selfclosed(source::String, span::UnitRange{Int})
    stop = last(span)
    stop >= first(span) + 1 || return false
    return codeunit(source, stop) == UInt8('>') &&
           codeunit(source, stop - 1) == UInt8('/')
end

_offset(node) = first(XML.sourcespan(node))

# The span of the verbatim source between an element's tags: from the start of
# its first child to the end of its last. Concatenating each child's
# `sourcetext` would drop whatever sits between them.
_inner_span(kids) = first(XML.sourcespan(first(kids))):last(XML.sourcespan(last(kids)))

function next_event!(p::XMLPullParser)
    p.pos > length(p.events) && return XMLDocumentEnd(ncodeunits(p.data) + 1)
    ev = p.events[p.pos]
    p.pos += 1
    return ev
end

# Called just after the start event of `name` has been returned, so the element
# is the one at `pos - 1`.
function read_raw_until_end!(p::XMLPullParser, name::AbstractString)
    i = p.pos - 1
    (1 <= i <= length(p.events) && p.events[i] isa XMLStartElement) || throw(
        OpenMathParseError("unterminated <$(name)>"; offset = 1))
    p.pos = p.skip[i]
    return p.data[p.inner[i]]
end

# The full source of the element whose start tag was just returned, its own tags
# included. `XML.jl` has it exactly: `sourcespan` covers the element with its
# tags, which is what the Content Dictionary parser needs to lift an `<OMOBJ>`
# out of an `.ocd` file and hand it to `read_xml` unchanged.
function element_source!(p::XMLPullParser, ev::XMLStartElement)
    i = p.pos - 1
    (1 <= i <= length(p.events) && p.events[i] isa XMLStartElement) || throw(
        OpenMathParseError("unterminated <$(ev.name)>"; offset = ev.offset))
    stop = p.skip[i]
    # The end event of this element sits just before where `skip` lands, and its
    # offset is the last byte of the closing tag.
    last_byte = if ev.selfclosed
        _selfclosed_end(p.data, ev.offset)
    else
        p.events[stop - 1].offset
    end
    p.pos = stop
    return p.data[ev.offset:last_byte]
end

# `XML.jl` reports one span for a self-closing element, and its end is the `>`.
function _selfclosed_end(data::String, from::Int)
    something(findnext('>', data, from), lastindex(data))
end
