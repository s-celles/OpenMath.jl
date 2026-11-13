# SPDX-License-Identifier: MIT
#
# The Popcorn printer (REQ-POP-001). Popcorn is the compact linear notation of
# Horn and Roozemond, "OpenMath in SCIEnce: SCSCP and POPCORN" (Calculemus/MKM
# 2009): `arith1.plus(1, $x)`, or `1 + $x` for the symbols it gives an infix
# form. It is not an encoding of the standard, and not an interchange format
# (REQ-POP-004 is a Won't): it is what a person reads.
#
# What is printed follows the reference *grammar*, `PopcornAST.g` and
# `PopcornWalker.g` in `org.symcomp.openmath`, so that it reads back as the same
# object. Where the reference *renderer* disagrees with its own grammar, the
# grammar wins; docs/src/design/popcorn.md lists each case.
#
# The tree is walked with an explicit stack, like every other traversal here
# (REQ-SEC-002): a deep object must not overflow the call stack.

# Binding strength, from the grammar's rule nesting, loosest first. A child is
# bracketed when its own level is below the level its position requires.
const _POP_BLOCK = 1        # `;`            prog1#block
const _POP_ASSIGN = 2       # `:=`           prog1#assign
const _POP_IMPLIES = 3      # `==>` `<=>`    logic1#implies, logic1#equivalent
const _POP_OR = 4           # `or`
const _POP_AND = 5          # `and`
const _POP_REL = 6          # `=` `<` `<=` `>` `>=` `!=` `~`
const _POP_INTERVAL = 7     # `..`           interval1#interval
const _POP_ADD = 8          # `+` `-`
const _POP_NEG = 9          # prefix `-`, and a negative literal
const _POP_MUL = 10         # `*` `/`
const _POP_POWER = 11       # `^`
const _POP_COMPLEX = 12     # `|`            complex1#complex_cartesian
const _POP_RATIONAL = 13    # `//`           nums1#rational
const _POP_ATOM = 14        # calls, bindings, lists, sets, attributions, atoms

# How an infix operator groups:
#   :flat      n-ary, at least two operands. The reference parser flattens a
#              chain (`a + b + c` is one `plus` of three), so an operand that is
#              the same operator is bracketed.
#   :left      exactly two operands, left-associative: `a - b - c` is
#              `minus(minus(a, b), c)`.
#   :nonassoc  exactly two operands; `a < b < c` does not parse.
struct _PopInfix
    text::String
    level::Int
    grouping::Symbol
end

const _POP_INFIX = Dict{Tuple{String, String}, _PopInfix}(
    ("prog1", "block") => _PopInfix("; ", _POP_BLOCK, :flat),
    ("prog1", "assign") => _PopInfix(" := ", _POP_ASSIGN, :nonassoc),
    ("logic1", "implies") => _PopInfix(" ==> ", _POP_IMPLIES, :nonassoc),
    ("logic1", "equivalent") => _PopInfix(" <=> ", _POP_IMPLIES, :nonassoc),
    # The reference parser builds `and` and `or` two operands at a time, so
    # they are left-associative binary operators there, not flat ones.
    ("logic1", "or") => _PopInfix(" or ", _POP_OR, :left),
    ("logic1", "and") => _PopInfix(" and ", _POP_AND, :left),
    ("relation1", "eq") => _PopInfix(" = ", _POP_REL, :nonassoc),
    ("relation1", "lt") => _PopInfix(" < ", _POP_REL, :nonassoc),
    ("relation1", "leq") => _PopInfix(" <= ", _POP_REL, :nonassoc),
    ("relation1", "gt") => _PopInfix(" > ", _POP_REL, :nonassoc),
    ("relation1", "geq") => _PopInfix(" >= ", _POP_REL, :nonassoc),
    ("relation1", "neq") => _PopInfix(" != ", _POP_REL, :nonassoc),
    ("relation2", "approx") => _PopInfix(" ~ ", _POP_REL, :nonassoc),
    ("interval1", "interval") => _PopInfix(" .. ", _POP_INTERVAL, :nonassoc),
    ("arith1", "plus") => _PopInfix(" + ", _POP_ADD, :flat),
    ("arith1", "minus") => _PopInfix(" - ", _POP_ADD, :left),
    ("arith1", "times") => _PopInfix("*", _POP_MUL, :flat),
    ("arith1", "divide") => _PopInfix("/", _POP_MUL, :left),
    ("arith1", "power") => _PopInfix("^", _POP_POWER, :nonassoc),
    ("complex1", "complex_cartesian") => _PopInfix("|", _POP_COMPLEX, :nonassoc),
    ("nums1", "rational") => _PopInfix("//", _POP_RATIONAL, :nonassoc)
)

# Symbols written without their Content Dictionary. Every entry is one the
# reference parser maps back to the same symbol (`PopcornHelper.translate`,
# checked one by one): its renderer also prints `ln`, `log`, `arcsin`, `gcd` and
# others bare, which its own parser then cannot read.
const _POP_BARE = Dict{Tuple{String, String}, String}(
    ("transc1", "sin") => "sin", ("transc1", "cos") => "cos",
    ("transc1", "tan") => "tan", ("transc1", "exp") => "exp",
    ("transc1", "sinh") => "sinh", ("transc1", "cosh") => "cosh",
    ("transc1", "tanh") => "tanh",
    ("nums1", "pi") => "pi", ("nums1", "e") => "e", ("nums1", "i") => "i",
    ("nums1", "infinity") => "infinity",
    ("logic1", "true") => "true", ("logic1", "false") => "false",
    ("logic1", "not") => "not",
    ("minmax1", "min") => "min", ("minmax1", "max") => "max",
    ("arith1", "abs") => "abs", ("arith1", "sum") => "sum",
    ("arith1", "product") => "product", ("arith1", "root") => "root",
    ("fns1", "lambda") => "lambda",
    ("quant1", "forall") => "forall", ("quant1", "exists") => "exists"
)

const _POP_KEYWORDS = ("or", "and", "if", "then", "else", "endif", "while", "do",
    "endwhile")

# An identifier the grammar's `ID` token reads as it stands, or the same in
# single quotes. A keyword is quoted too: `$or` lexes as `$` then the keyword.
function _pop_id(s::AbstractString)
    plain = !isempty(s) &&
            all(c -> isascii(c) && (isletter(c) || isdigit(c) || c == '_'), s) &&
            !isdigit(first(s)) && !(s in _POP_KEYWORDS)
    return plain ? String(s) : string("'", s, "'")
end

# A node still to print, with the least level its position accepts and whether
# the position needs an anchor: the head of a call, a binding or an error, the
# object of an attribution, or anything carrying an id.
struct _PopItem
    node::Any
    minlevel::Int
    anchor::Bool
end

_pop_item(node, minlevel::Int = 0; anchor::Bool = false) = _PopItem(node, minlevel, anchor)

"""
    write_popcorn(io, obj)

Write `obj` to `io` in Popcorn, the compact linear notation of Horn and
Roozemond (2009): `1 + \$x` for `OMA(OMS(arith1#plus), OMI(1), OMV(x))`.

Popcorn is for reading, not interchange. It has no syntax for `cdbase`, so a
symbol is written by its Content Dictionary and name only, and an `OMFOREIGN`
loses its encoding. See [`OpenMath.popcorn`](@ref) for a `String`.

# Examples
```jldoctest
julia> using OpenMath

julia> write_popcorn(stdout, OMS"arith1#times"(OMS"arith1#plus"(OMVariable("x"), OMInteger(1)), OMInteger(2)))
(\$x + 1)*2
```
"""
function write_popcorn(io::IO, obj::Union{OMObject, OMOrForeign})
    stack = Any[_pop_item(obj isa OMObject ? obj.object : obj)]
    while !isempty(stack)
        top = pop!(stack)
        if top isa String
            print(io, top)
            continue
        end
        level, atom, pieces = _pop_pieces(top.node)
        id = _pop_node_id(top.node)
        if id !== nothing
            # `atom:id` binds an id to an atom; anything else is bracketed first.
            # Either way the result is an anchor, so it needs no more brackets.
            push!(stack, ":" * _pop_id(id))
            atom || push!(stack, ")")
            _pop_push_reversed!(stack, pieces)
            atom || push!(stack, "(")
        elseif level < top.minlevel || (top.anchor && !atom)
            push!(stack, ")")
            _pop_push_reversed!(stack, pieces)
            push!(stack, "(")
        else
            _pop_push_reversed!(stack, pieces)
        end
    end
    return nothing
end

"""
    OpenMath.popcorn(obj) -> String

`obj` in Popcorn, as [`write_popcorn`](@ref) writes it.

# Examples
```jldoctest
julia> using OpenMath

julia> OpenMath.popcorn(OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")], OMS"arith1#plus"(OMInteger(1), OMVariable("x"))))
"lambda[\\\$x -> 1 + \\\$x]"
```
"""
function popcorn(obj::Union{OMObject, OMOrForeign})
    io = IOBuffer()
    write_popcorn(io, obj)
    return String(take!(io))
end

function _pop_push_reversed!(stack::Vector{Any}, pieces::Vector{Any})
    for i in length(pieces):-1:1
        push!(stack, pieces[i])
    end
    return nothing
end

_pop_node_id(node::OMOrForeign) = node.id
_pop_node_id(::Any) = nothing

# A comma-separated run of nodes, each at the loosest level.
function _pop_list!(pieces::Vector{Any}, nodes)
    for (i, n) in enumerate(nodes)
        i > 1 && push!(pieces, ", ")
        push!(pieces, _pop_item(n))
    end
    return pieces
end

function _pop_attributes!(pieces::Vector{Any}, attributes)
    push!(pieces, "{")
    for (i, a) in enumerate(attributes)
        i > 1 && push!(pieces, ", ")
        push!(pieces, _pop_item(a.key), " -> ", _pop_item(a.value))
    end
    push!(pieces, "}")
    return pieces
end

# Each method returns (level, atom, pieces): how tightly the printed form binds,
# whether it is an atom of the grammar (so it can carry an id or head a call
# without brackets), and what to print, as strings and nodes still to print.

function _pop_pieces(x::OMInteger)
    return x.value < 0 ? (_POP_NEG, false, Any[string(x.value)]) :
           (_POP_ATOM, true, Any[string(x.value)])
end

function _pop_pieces(x::OMFloat)
    v = x.value
    if !isfinite(v)
        # The grammar's decimal form has no infinity or NaN; its `0f` form is the
        # IEEE bits, as in `<OMF hex="…"/>`.
        bits = uppercase(lpad(string(reinterpret(UInt64, v); base = 16), 16, '0'))
        return (_POP_ATOM, true, Any["0f" * bits])
    end
    return signbit(v) ? (_POP_NEG, false, Any[string(v)]) :
           (_POP_ATOM, true, Any[string(v)])
end

function _pop_pieces(x::OMString)
    s = replace(x.value, "\\" => "\\\\", "\"" => "\\\"")
    return (_POP_ATOM, true, Any[string("\"", s, "\"")])
end

_pop_pieces(x::OMVariable) = (_POP_ATOM, true, Any["\$" * _pop_id(x.name)])

function _pop_pieces(x::OMSymbol)
    bare = x.cdbase === nothing ? get(_POP_BARE, (x.cd, x.name), nothing) : nothing
    text = bare === nothing ? string(_pop_id(x.cd), ".", _pop_id(x.name)) : bare
    return (_POP_ATOM, true, Any[text])
end

function _pop_pieces(x::OMReference)
    text = startswith(x.href, "#") ? "#" * _pop_id(x.href[2:end]) :
           string("##", x.href, "##")
    return (_POP_ATOM, true, Any[text])
end

_pop_pieces(x::OMBytes) = (_POP_ATOM, true, Any[string("%", base64_encode(x.value), "%")])

_pop_pieces(x::OMForeign) = (_POP_ATOM, true, Any[string("`", x.value, "`")])

function _pop_pieces(x::OMBoundVariable)
    pieces = Any["\$" * _pop_id(x.name)]
    isempty(x.attributes) || _pop_attributes!(pieces, x.attributes)
    return (_POP_ATOM, isempty(x.attributes), pieces)
end

function _pop_pieces(x::OMBinding)
    pieces = Any[_pop_item(x.binder; anchor = true), "["]
    _pop_list!(pieces, x.variables)
    push!(pieces, " -> ", _pop_item(x.body), "]")
    return (_POP_ATOM, false, pieces)
end

function _pop_pieces(x::OMError)
    pieces = Any[_pop_item(x.head; anchor = true), "!("]
    _pop_list!(pieces, x.arguments)
    push!(pieces, ")")
    return (_POP_ATOM, false, pieces)
end

function _pop_pieces(x::OMAttribution)
    pieces = Any[_pop_item(x.object; anchor = true)]
    _pop_attributes!(pieces, x.attributes)
    return (_POP_ATOM, false, pieces)
end

function _pop_is_symbol(n, cd::String, name::String)
    n isa OMSymbol && n.cdbase === nothing && n.cd == cd && n.name == name
end

function _pop_is_app(n, cd::String, name::String)
    n isa OMApplication && _pop_is_symbol(n.applicant, cd, name)
end

function _pop_pieces(x::OMApplication)
    head, args = x.applicant, x.arguments
    if head isa OMSymbol && head.cdbase === nothing
        key = (head.cd, head.name)
        if key == ("list1", "list")
            return (_POP_ATOM, false, push!(_pop_list!(Any["["], args), "]"))
        elseif key == ("set1", "set")
            return (_POP_ATOM, false, push!(_pop_list!(Any["{"], args), "}"))
        elseif key == ("arith1", "unary_minus") && length(args) == 1 &&
               !(only(args) isa OMInteger || only(args) isa OMFloat)
            # Not for a literal: the reference parser folds `-3` into the
            # integer -3, so negating one is written as a call.
            return (_POP_NEG, false, Any["-", _pop_item(only(args), _POP_MUL)])
        end
        op = get(_POP_INFIX, key, nothing)
        if op !== nothing && _pop_arity_ok(op, length(args))
            return (op.level, false, _pop_infix_pieces(op, key, args))
        end
    end
    pieces = Any[_pop_item(head; anchor = true), "("]
    _pop_list!(pieces, args)
    push!(pieces, ")")
    return (_POP_ATOM, false, pieces)
end

_pop_arity_ok(op::_PopInfix, n::Int) = op.grouping === :flat ? n >= 2 : n == 2

function _pop_infix_pieces(op::_PopInfix, key::Tuple{String, String}, args)
    L = op.level
    pieces = Any[]
    for (i, a) in enumerate(args)
        i > 1 && push!(pieces, op.text)
        minlevel = if i == 1 && op.grouping !== :nonassoc
            # A left operand may sit at the same level — `a - b + c` — unless
            # it is this very operator, which the parser would flatten.
            _pop_is_app(a, key...) && op.grouping === :flat ? L + 1 : L
        else
            L + 1
        end
        push!(pieces, _pop_item(a, minlevel))
    end
    return pieces
end

# ------------------------------------------------------------- text/plain ---
#
# What the REPL shows (REQ-POP-003): Popcorn, which is what a person reads, but
# only when it shows the whole object. Popcorn has no syntax for `cdbase` or for
# an `OMFOREIGN` encoding, and a display that silently drops either would show a
# different object from the one held; those fall back to the functional form,
# which carries both. The two-argument `show` — used by `repr`, inside
# containers, in string interpolation — stays the functional form throughout.

function Base.show(io::IO, ::MIME"text/plain", x::OMNode)
    _popcorn_shows_all(x) ? write_popcorn(io, x) : show(io, x)
    return nothing
end

function _popcorn_shows_all(root::OMNode)
    stack = OMOrForeign[root]
    while !isempty(stack)
        n = pop!(stack)
        if n isa OMForeign
            n.encoding === nothing || return false
            continue
        end
        hasfield(typeof(n), :cdbase) && getfield(n, :cdbase) !== nothing && return false
        append!(stack, children(n))
    end
    return true
end
