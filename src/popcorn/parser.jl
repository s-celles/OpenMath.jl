# SPDX-License-Identifier: MIT
#
# The Popcorn parser (REQ-POP-002): the reverse of `src/popcorn/printer.jl`, on
# the grammar of `PopcornAST.g` and the objects `PopcornWalker.g` builds from it
# (docs/src/design/popcorn.md).
#
# Like every other reader here it uses no recursion (REQ-SEC-002): operators and
# operands sit on explicit stacks, and each bracketed group — `( )`, a call, a
# list, a binding, an attribution — opens a frame of its own. Every error is an
# `OpenMathParseError` carrying the byte offset of the token at fault
# (REQ-API-007).

# ------------------------------------------------------------------ lexer ---

struct _PopToken
    kind::Symbol      # :id :int :float :hexfloat :string :gref :omb :foreign :punct :kw :eof
    text::String
    offset::Int
end

mutable struct _PopLexer
    src::String
    pos::Int
    peeked::Union{Nothing, _PopToken}
end

_pop_lexerr(msg::AbstractString, at::Int) = throw(OpenMathParseError(msg; offset = at))

# Longest first: `<=>` before `<=`, `==>` before `=`.
const _POP_PUNCT = ("==>", "<=>", ":=", "::", "<=", ">=", "!=", "<>", "->", "//", "..",
    "(", ")", "[", "]", "{", "}", ",", ";", ":", "=", "<", ">", "~", "+", "-", "*",
    "/", "^", "|", "!", ".", "\$", "#")

function _pop_isidstart(b::UInt8)
    UInt8('a') <= b <= UInt8('z') || UInt8('A') <= b <= UInt8('Z') ||
        b == UInt8('_')
end
_pop_isidchar(b::UInt8) = _pop_isidstart(b) || UInt8('0') <= b <= UInt8('9')
_pop_isdigit(b::UInt8) = UInt8('0') <= b <= UInt8('9')
function _pop_ishex(b::UInt8)
    _pop_isdigit(b) || UInt8('a') <= b <= UInt8('f') ||
        UInt8('A') <= b <= UInt8('F')
end

function _pop_peek(lx::_PopLexer)
    lx.peeked === nothing && (lx.peeked = _pop_lex(lx))
    return lx.peeked::_PopToken
end

function _pop_next(lx::_PopLexer)
    t = _pop_peek(lx)
    lx.peeked = nothing
    return t
end

# The text from `from` up to, not including, the next `close`; the position after it.
function _pop_until(lx::_PopLexer, from::Int, close::String, what::String, start::Int)
    r = findnext(close, lx.src, from)
    r === nothing && _pop_lexerr("unterminated $(what)", start)
    return _slice(lx.src, from, first(r) - 1), last(r) + 1
end

function _pop_lex(lx::_PopLexer)
    s = lx.src
    n = ncodeunits(s)
    i = lx.pos
    # White space and `/* … */` comments.
    while i <= n
        b = codeunit(s, i)
        if b == UInt8(' ') || b == UInt8('\t') || b == UInt8('\n') || b == UInt8('\r')
            i += 1
        elseif b == UInt8('/') && i < n && codeunit(s, i + 1) == UInt8('*')
            r = findnext("*/", s, i + 2)
            r === nothing && _pop_lexerr("unterminated comment", i)
            i = last(r) + 1
        else
            break
        end
    end
    if i > n
        lx.pos = i
        return _PopToken(:eof, "", i)
    end
    start = i
    b = codeunit(s, i)
    if _pop_isidstart(b)
        while i <= n && _pop_isidchar(codeunit(s, i))
            i += 1
        end
        text = _slice(s, start, i - 1)
        lx.pos = i
        return _PopToken(text in _POP_KEYWORDS ? :kw : :id, text, start)
    elseif b == UInt8('\'')
        text, lx.pos = _pop_until(lx, i + 1, "'", "quoted name", start)
        isempty(text) && _pop_lexerr("an empty quoted name", start)
        return _PopToken(:id, text, start)
    elseif _pop_isdigit(b)
        if b == UInt8('0') && i < n && codeunit(s, i + 1) in (UInt8('x'), UInt8('f'))
            kind = codeunit(s, i + 1) == UInt8('x') ? :int : :hexfloat
            j = i + 2
            while j <= n && _pop_ishex(codeunit(s, j))
                j += 1
            end
            j == i + 2 && _pop_lexerr("a hexadecimal number needs digits", start)
            lx.pos = j
            return _PopToken(kind, _slice(s, start, j - 1), start)
        end
        while i <= n && _pop_isdigit(codeunit(s, i))
            i += 1
        end
        # A float has digits after its point; `1..5` is an interval.
        if i < n && codeunit(s, i) == UInt8('.') && _pop_isdigit(codeunit(s, i + 1))
            i += 1
            while i <= n && _pop_isdigit(codeunit(s, i))
                i += 1
            end
            if i <= n && codeunit(s, i) == UInt8('e')
                j = i + 1
                j <= n && codeunit(s, j) == UInt8('-') && (j += 1)
                k = j
                while k <= n && _pop_isdigit(codeunit(s, k))
                    k += 1
                end
                k == j && _pop_lexerr("an exponent needs digits", i)
                i = k
            end
            lx.pos = i
            return _PopToken(:float, _slice(s, start, i - 1), start)
        end
        lx.pos = i
        return _PopToken(:int, _slice(s, start, i - 1), start)
    elseif b == UInt8('"')
        buf = IOBuffer()
        i += 1
        while true
            i > n && _pop_lexerr("unterminated string", start)
            c = codeunit(s, i)
            if c == UInt8('"')
                break
            elseif c == UInt8('\\')
                nx = i < n ? codeunit(s, i + 1) : 0x00
                (nx == UInt8('"') || nx == UInt8('\\')) ||
                    _pop_lexerr("in a string, a backslash escapes only \\\" and \\\\", i)
                write(buf, nx)
                i += 2
            else
                write(buf, c)
                i += 1
            end
        end
        lx.pos = i + 1
        return _PopToken(:string, String(take!(buf)), start)
    elseif b == UInt8('#') && i < n && codeunit(s, i + 1) == UInt8('#')
        text, lx.pos = _pop_until(lx, i + 2, "##", "reference", start)
        isempty(text) && _pop_lexerr("an empty reference", start)
        return _PopToken(:gref, text, start)
    elseif b == UInt8('%')
        text, lx.pos = _pop_until(lx, i + 1, "%", "byte array", start)
        return _PopToken(:omb, text, start)
    elseif b == UInt8('`')
        text, lx.pos = _pop_until(lx, i + 1, "`", "foreign object", start)
        return _PopToken(:foreign, text, start)
    end
    for p in _POP_PUNCT
        if _pop_at(s, i, p)
            lx.pos = i + ncodeunits(p)
            return _PopToken(:punct, p, start)
        end
    end
    _pop_lexerr("unexpected character $(repr(s[i]))", start)
end

function _pop_at(s::String, i::Int, p::String)
    m = ncodeunits(p)
    i + m - 1 <= ncodeunits(s) || return false
    for k in 1:m
        codeunit(s, i + k - 1) == codeunit(p, k) || return false
    end
    return true
end

# ----------------------------------------------------------------- parser ---

# The binary operators, keyed by their token, with the symbol they build.
const _POP_BINARY = Dict{String, Tuple{Tuple{String, String}, _PopInfix}}()
for (key, op) in _POP_INFIX
    _POP_BINARY[strip(op.text)] = (key, op)
end
_POP_BINARY["<>"] = (("relation1", "neq"), _POP_INFIX[("relation1", "neq")])

const _POP_BARE_NAMES = Dict{String, Tuple{String, String}}(v => k for (k, v) in _POP_BARE)

# An operand: the node, where it starts, and what may follow it.
struct _PopVal
    node::Any
    offset::Int
    anchor::Bool            # may take an id, or head a call, binding or attribution
    flat::Union{Nothing, Tuple{String, String}}   # an unbracketed `+`, `*` or `;` chain
    depth::Int
end

struct _PopOp
    key::Tuple{String, String}
    level::Int
    grouping::Symbol        # :flat :left :nonassoc, or :prefix for a sign
    offset::Int
end

mutable struct _PopFrame
    kind::Symbol            # :top :paren :call :ecall :list :set :bind :attr :if :while
    offset::Int
    head::Any
    items::Vector{Any}
    depths::Vector{Int}
    stage::Int
    opsbase::Int
    valsbase::Int
end

_pop_err(msg::AbstractString, at::Int) = throw(OpenMathParseError(msg; offset = at))

"""
    read_popcorn(src) -> OMObject

Read an object written in Popcorn, the compact notation of Horn and Roozemond
(2009) that [`write_popcorn`](@ref) writes. What the printer writes reads back as
the same object, but for what Popcorn has no syntax for: `cdbase`, and the
encoding of an `OMFOREIGN`.

The grammar is the reference one (`PopcornAST.g`). A chain `a + b + c` reads as
one `arith1#plus` of three operands, while `(a + b) + c` keeps its brackets; a
negative literal `-3` is the integer -3; a bare name is one of the few the
printer writes bare, such as `sin` or `pi`. `x::T` is not read, since it needs a
type symbol nothing defines.

Errors are `OpenMathParseError`s carrying the byte offset of the token at fault,
and the configured limits apply (`max_bytes`, `max_depth`).

# Examples
```jldoctest
julia> using OpenMath

julia> read_popcorn("(\\\$x + 1)*2")
OMOBJ(OMA(OMS(arith1#times), OMA(OMS(arith1#plus), OMV(x), OMI(1)), OMI(2)))
```
"""
function read_popcorn(src::AbstractString)
    text = String(src)::String
    check_limit(:max_bytes, ncodeunits(text), limits().max_bytes)
    _check_utf8(text, "Popcorn is read as UTF-8")
    lx = _PopLexer(text, 1, nothing)
    node = try
        _pop_parse(lx)
    catch err
        # A name or value a constructor refuses is the document's fault: say so
        # where it happened, in the one error type a reader raises.
        (err isa OpenMathError && !(err isa OpenMathParseError) &&
         !(err isa OpenMathLimitError)) || rethrow()
        throw(OpenMathParseError(sprint(showerror, err); offset = lx.pos))
    end
    node isa OMForeign &&
        _pop_err(
            "foreign content cannot be a whole object; it can only be an error's " *
            "argument or an attribute's value",
            1)
    return OMObject(node)
end

function _pop_parse(lx::_PopLexer)
    vals = _PopVal[]
    ops = _PopOp[]
    frames = _PopFrame[_PopFrame(:top, 1, nothing, Any[], Int[], 1, 0, 0)]
    maxdepth = limits().max_depth
    expect_operand = true
    while true
        t = _pop_next(lx)
        frame = frames[end]
        if expect_operand
            if _pop_atom!(vals, lx, t)
                expect_operand = false
            elseif t.kind === :punct && t.text in ("(", "[", "{")
                kind = t.text == "(" ? :paren : t.text == "[" ? :list : :set
                _pop_open!(frames, ops, vals, kind, t.offset, nothing, maxdepth)
            elseif t.kind === :punct && t.text == "-"
                ctx = length(ops) > frame.opsbase ? ops[end].level : 0
                ctx < _POP_NEG || _pop_err(
                    "a prefix '-' must start a term of a sum; put it in brackets",
                    t.offset)
                push!(ops, _PopOp(("arith1", "unary_minus"), _POP_NEG, :prefix, t.offset))
            elseif t.kind === :kw && t.text in ("if", "while")
                _pop_open!(frames, ops, vals, Symbol(t.text), t.offset, nothing, maxdepth)
            elseif t.kind === :punct && t.text in (")", "]", "}") &&
                   _pop_empty(frame, ops, vals) && isempty(frame.items) &&
                   frame.kind in (:call, :ecall, :list, :set)
                _pop_close!(frames, ops, vals, t, maxdepth)
                expect_operand = false
            elseif t.kind === :punct && t.text == "->" && frame.kind === :bind &&
                   frame.stage == 1 && _pop_empty(frame, ops, vals)
                frame.stage = 2
            else
                _pop_err(
                    t.kind === :eof ? "unexpected end of input" :
                    "expected an operand, found $(repr(t.text))",
                    t.offset)
            end
            continue
        end

        # After an operand: an operator, a postfix form, or the end of a group.
        if (t.kind === :punct || t.kind === :kw) && haskey(_POP_BINARY, t.text)
            key, op = _POP_BINARY[t.text]
            while length(ops) > frame.opsbase
                top = ops[end]
                if top.level == op.level && op.grouping === :nonassoc
                    _pop_err("$(repr(t.text)) does not chain; put one side in brackets",
                        t.offset)
                end
                (top.level > op.level || (top.level == op.level)) || break
                _pop_reduce!(vals, ops, maxdepth)
            end
            push!(ops, _PopOp(key, op.level, op.grouping, t.offset))
            expect_operand = true
        elseif t.kind === :punct && t.text in ("(", "[", "{", "!")
            head = _pop_anchor!(vals, frame, t)
            if t.text == "!"
                nx = _pop_next(lx)
                (nx.kind === :punct && nx.text == "(") ||
                    _pop_err("expected '(' after '!'", nx.offset)
                head.node isa OMSymbol ||
                    _pop_err("an error's head must be a symbol", head.offset)
            end
            kind = t.text == "(" ? :call :
                   t.text == "!" ? :ecall :
                   t.text == "[" ? :bind : :attr
            _pop_open!(frames, ops, vals, kind, head.offset, head.node, maxdepth)
            expect_operand = true
        elseif t.kind === :punct && t.text == ":"
            nx = _pop_next(lx)
            nx.kind === :id || _pop_err("expected an id after ':'", nx.offset)
            v = _pop_anchor!(vals, frame, t)
            _pop_node_id(v.node) === nothing ||
                _pop_err("this object already has an id", t.offset)
            push!(vals, _PopVal(_pop_with_id(v.node, nx.text), v.offset, true, nothing,
                v.depth))
        elseif t.kind === :punct && t.text == "::"
            _pop_err("'::' needs a type symbol; write the attribution {cd.type -> T}",
                t.offset)
        elseif t.kind === :punct && t.text in (",", "->")
            _pop_separator!(frames, ops, vals, t)
            expect_operand = true
        elseif t.kind === :kw && t.text in ("then", "else", "do")
            _pop_separator!(frames, ops, vals, t)
            expect_operand = true
        elseif (t.kind === :punct && t.text in (")", "]", "}")) ||
               (t.kind === :kw && t.text in ("endif", "endwhile")) || t.kind === :eof
            done = _pop_close!(frames, ops, vals, t, maxdepth)
            done && return only(vals).node
        else
            _pop_err("expected an operator, found $(repr(t.text))", t.offset)
        end
    end
end

function _pop_empty(frame::_PopFrame, ops, vals)
    length(ops) == frame.opsbase && length(vals) == frame.valsbase
end

function _pop_val(node, offset::Int, depth::Int, maxdepth::Int;
        anchor::Bool = false, flat = nothing)
    check_limit(:max_depth, depth, maxdepth)
    return _PopVal(node, offset, anchor, flat, depth)
end

# An atom, pushed as an operand; `false` when `t` does not start one.
function _pop_atom!(vals::Vector{_PopVal}, lx::_PopLexer, t::_PopToken)
    node = if t.kind === :int
        OMInteger(startswith(t.text, "0x") ? Base.parse(BigInt, t.text[3:end]; base = 16) :
                  Base.parse(BigInt, t.text))
    elseif t.kind === :float
        # As the XML reader does for `<OMF dec>`: a value past Float64's range is
        # refused, not rounded (`Base.parse` raises an `ArgumentError` on it).
        v = tryparse(Float64, t.text)
        v === nothing && _pop_err("$(t.text) is not a representable float", t.offset)
        OMFloat(v)
    elseif t.kind === :hexfloat
        digits = t.text[3:end]
        ncodeunits(digits) <= 16 ||
            _pop_err("a hexadecimal float has at most 16 digits", t.offset)
        OMFloat(reinterpret(Float64, Base.parse(UInt64, digits; base = 16)))
    elseif t.kind === :string
        OMString(t.text)
    elseif t.kind === :gref
        OMReference(t.text)
    elseif t.kind === :omb
        OMBytes(base64_decode(t.text; offset = t.offset))
    elseif t.kind === :foreign
        OMForeign(nothing, t.text)
    elseif t.kind === :id
        nx = _pop_peek(lx)
        if nx.kind === :punct && nx.text == "."
            _pop_next(lx)
            name = _pop_next(lx)
            name.kind === :id || _pop_err("expected a symbol name after '.'", name.offset)
            OMSymbol(t.text, name.text)
        else
            key = get(_POP_BARE_NAMES, t.text, nothing)
            key === nothing &&
                _pop_err("unknown name $(repr(t.text)); write a symbol as cd.name", t.offset)
            OMSymbol(key...)
        end
    elseif t.kind === :punct && t.text in ("\$", "#")
        name = _pop_next(lx)
        name.kind === :id || _pop_err("expected a name after '$(t.text)'", name.offset)
        t.text == "\$" ? OMVariable(name.text) : OMReference("#" * name.text)
    else
        return false
    end
    push!(vals, _PopVal(node, t.offset, true, nothing, 1))
    return true
end

# The operand just read, taken off the stack to head a postfix form or carry an
# id. Only an anchor may: an atom, a bracketed expression, or either with an id.
function _pop_anchor!(vals::Vector{_PopVal}, frame::_PopFrame, t::_PopToken)
    length(vals) > frame.valsbase || _pop_err("nothing before $(repr(t.text))", t.offset)
    v = vals[end]
    v.anchor ||
        _pop_err("$(repr(t.text)) needs an atom or a bracketed expression before it",
            t.offset)
    v.node isa OMForeign && t.text != ":" &&
        _pop_err("foreign content cannot head $(repr(t.text))", t.offset)
    return pop!(vals)
end

function _pop_open!(frames, ops, vals, kind::Symbol, offset::Int, head, maxdepth::Int)
    check_limit(:max_depth, length(frames), maxdepth)
    push!(frames, _PopFrame(kind, offset, head, Any[], Int[], 1, length(ops), length(vals)))
    return nothing
end

function _pop_reduce!(vals::Vector{_PopVal}, ops::Vector{_PopOp}, maxdepth::Int)
    op = pop!(ops)
    if op.grouping === :prefix
        v = pop!(vals)
        n = v.node
        n isa OMForeign && _pop_err("foreign content cannot be an operand", op.offset)
        # The reference parser folds a sign into a literal: `-3` is the integer -3.
        node = if n isa OMInteger && n.id === nothing
            OMInteger(-n.value)
        elseif n isa OMFloat && n.id === nothing
            OMFloat(-n.value)
        else
            OMApplication(OMSymbol(op.key...), [n])
        end
        depth = node isa OMApplication ? v.depth + 1 : v.depth
        push!(vals, _pop_val(node, op.offset, depth, maxdepth))
        return nothing
    end
    r = pop!(vals)
    l = pop!(vals)
    (l.node isa OMForeign || r.node isa OMForeign) &&
        _pop_err("foreign content cannot be an operand", op.offset)
    if op.grouping === :flat && l.flat == op.key
        node = l.node::OMApplication
        args = OMNode[node.arguments; r.node]
        push!(vals,
            _pop_val(OMApplication(node.applicant, args), l.offset,
                max(l.depth, r.depth + 1), maxdepth; flat = op.key))
    else
        node = OMApplication(OMSymbol(op.key...), OMNode[l.node, r.node])
        push!(vals,
            _pop_val(node, l.offset, max(l.depth, r.depth) + 1, maxdepth;
                flat = op.grouping === :flat ? op.key : nothing))
    end
    return nothing
end

# Reduce everything in the current frame to one operand, and take it.
function _pop_finish!(frame::_PopFrame, ops, vals, at::Int, maxdepth::Int)
    while length(ops) > frame.opsbase
        _pop_reduce!(vals, ops, maxdepth)
    end
    length(vals) == frame.valsbase + 1 || _pop_err("expected an operand", at)
    return pop!(vals)
end

function _pop_separator!(frames, ops, vals, t::_PopToken)
    frame = frames[end]
    sep = t.text
    allowed = if sep == ","
        frame.kind in (:call, :ecall, :list, :set) ||
            (frame.kind === :bind && frame.stage == 1) ||
            (frame.kind === :attr && frame.stage == 2)
    elseif sep == "->"
        frame.kind in (:bind, :attr) && frame.stage == 1
    elseif sep == "then"
        frame.kind === :if && frame.stage == 1
    elseif sep == "else"
        frame.kind === :if && frame.stage == 2
    else  # "do"
        frame.kind === :while && frame.stage == 1
    end
    allowed || _pop_err("unexpected $(repr(sep))", t.offset)
    v = _pop_finish!(frame, ops, vals, t.offset, typemax(Int))
    push!(frame.items, v.node)
    push!(frame.depths, v.depth)
    if frame.kind === :attr
        frame.stage = sep == "->" ? 2 : 1
    elseif frame.kind === :bind
        sep == "->" && (frame.stage = 2)
    elseif frame.kind in (:if, :while)
        frame.stage += 1
    end
    return nothing
end

const _POP_CLOSERS = Dict(:paren => ")", :call => ")", :ecall => ")", :list => "]",
    :set => "}", :bind => "]", :attr => "}", :if => "endif", :while => "endwhile",
    :top => "")

# Close the current frame on `t`; `true` when that ends the input.
function _pop_close!(frames, ops, vals, t::_PopToken, maxdepth::Int)
    frame = frames[end]
    closer = t.kind === :eof ? "" : t.text
    if closer != _POP_CLOSERS[frame.kind]
        _pop_err(
            t.kind === :eof ?
            "unexpected end of input: $(repr(_POP_CLOSERS[frame.kind])) is missing" :
            "unexpected $(repr(t.text))",
            t.offset)
    end
    if frame.kind === :top
        v = _pop_finish!(frame, ops, vals, t.offset, maxdepth)
        push!(vals, v)
        return true
    end
    if !_pop_empty(frame, ops, vals)
        v = _pop_finish!(frame, ops, vals, t.offset, maxdepth)
        push!(frame.items, v.node)
        push!(frame.depths, v.depth)
    end
    pop!(frames)
    items = frame.items
    kind = frame.kind
    sub = isempty(frame.depths) ? 0 : maximum(frame.depths)
    # Foreign content may be an error's argument or an attribute's value, and
    # nothing else; elsewhere the object model has no place for it.
    foreign_ok = kind === :ecall ? (1:length(items)) :
                 kind === :attr ? (2:2:length(items)) : (1:0)
    for (k, item) in enumerate(items)
        item isa OMForeign && !(k in foreign_ok) &&
            _pop_err(
                "foreign content can only be an error's argument or an attribute's value",
                frame.offset)
    end
    node, anchor = if kind === :paren
        length(items) == 1 || _pop_err("expected an expression in brackets", t.offset)
        only(items), true
    elseif kind === :call
        OMApplication(frame.head, items), false
    elseif kind === :ecall
        OMError(frame.head::OMSymbol, items), false
    elseif kind === :list
        OMApplication(OMSymbol("list1", "list"), items), false
    elseif kind === :set
        OMApplication(OMSymbol("set1", "set"), items), false
    elseif kind === :bind
        frame.stage == 2 && !isempty(items) ||
            _pop_err("a binding needs '->' and a body", t.offset)
        body = pop!(items)
        OMBinding(frame.head, [_pop_bound(v, frame.offset) for v in items], body), false
    elseif kind === :attr
        (frame.stage == 2 && iseven(length(items))) ||
            _pop_err("an attribution needs key -> value pairs", t.offset)
        pairs = OMAttributePair[]
        for k in 1:2:length(items)
            key = items[k]
            key isa OMSymbol ||
                _pop_err("an attribution key must be a symbol", frame.offset)
            push!(pairs, OMAttributePair(key, items[k + 1]))
        end
        OMAttribution(pairs, frame.head), false
    elseif kind === :if
        length(items) == 3 || _pop_err("if needs then and else", t.offset)
        OMApplication(OMSymbol("prog1", "if"), items), false
    else  # :while
        length(items) == 2 || _pop_err("while needs do", t.offset)
        OMApplication(OMSymbol("prog1", "while"), items), false
    end
    d = kind === :paren ? sub : sub + 1
    push!(vals, _pop_val(node, frame.offset, max(d, 1), maxdepth; anchor = anchor))
    return false
end

function _pop_bound(v, at::Int)
    if v isa OMVariable && v.id === nothing
        return OMBoundVariable(v.name)
    elseif v isa OMAttribution && v.id === nothing && v.object isa OMVariable &&
           v.object.id === nothing
        return OMBoundVariable(v.object.name, v.attributes)
    end
    _pop_err("a bound variable must be \$name, possibly with attributes", at)
end

# `node` with an id: rebuilt, since the object model is immutable.
_pop_with_id(n::OMInteger, id) = OMInteger(n.value; id = id)
_pop_with_id(n::OMFloat, id) = OMFloat(n.value; id = id)
_pop_with_id(n::OMString, id) = OMString(n.value; id = id)
_pop_with_id(n::OMBytes, id) = OMBytes(n.value; id = id)
_pop_with_id(n::OMVariable, id) = OMVariable(n.name; id = id)
_pop_with_id(n::OMSymbol, id) = OMSymbol(n.cd, n.name; cdbase = n.cdbase, id = id)
_pop_with_id(n::OMReference, id) = OMReference(n.href; id = id)
_pop_with_id(n::OMForeign, id) = OMForeign(n.encoding, n.value; id = id)
function _pop_with_id(n::OMApplication, id)
    OMApplication(n.applicant, n.arguments; cdbase = n.cdbase, id = id)
end
function _pop_with_id(n::OMBinding, id)
    OMBinding(n.binder, n.variables, n.body; cdbase = n.cdbase, id = id)
end
_pop_with_id(n::OMError, id) = OMError(n.head, n.arguments; cdbase = n.cdbase, id = id)
function _pop_with_id(n::OMAttribution, id)
    OMAttribution(n.attributes, n.object; cdbase = n.cdbase, id = id)
end
