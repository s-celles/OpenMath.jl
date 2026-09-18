# SPDX-License-Identifier: MIT
#
# The Symbolics.jl phrasebook (REQ-PHR-002), as a package extension.
#
# An extension rather than a companion package: the survey in
# docs/src/design/phrasebook.md found that the pinning problem which motivated
# the companion-package option is MathML.jl's, not Symbolics', and a weak
# dependency inherits no pin. That is half of decision D5.
#
# The two directions are not the same problem.
#
#   Symbolics → OpenMath is structural. Walk the expression tree, relabel each
#   operator with the Content Dictionary symbol it corresponds to. Nothing is
#   interpreted, so nothing can be interpreted wrongly.
#
#   OpenMath → Symbolics goes through a `Phrasebook`, because a variable has to
#   become a Symbolics variable rather than a `Symbol`, and that belongs to the
#   phrasebook rather than to a method on `interpret` — otherwise two callers in
#   one session could not disagree (REQ-PHR-001).

module OpenMathSymbolicsExt

using OpenMath
using OpenMath: OpenMathConversionError
import Symbolics                 # the module name itself; used qualified below
# `unwrap` and `issym` are owned by SymbolicUtils, and `iscall`, `operation` and
# `arguments` by TermInterface; Symbolics re-exports all five as part of its
# public surface. We take them from Symbolics on purpose. Depending on those two
# packages directly would mean tracking version bounds for the substrate of the
# Symbolics stack in order to reach an API Symbolics already offers, which is
# more coupling, not less. The `ExplicitImports` gate is told so by name in
# `test/quality/project.jl` rather than being switched off.
using Symbolics: Num, Equation, Differential, unwrap, iscall, operation, arguments,
                 issym

# --- Symbolics → OpenMath -----------------------------------------------------

# Julia function => the Content Dictionary symbol it is written as. Where several
# symbols denote the same function — `transc1#ln` and `transc1#log`, `arith1#plus`
# and `arith1#sum` — one is canonical, so that writing is deterministic.
const _OPERATORS = Dict{Any, Tuple{String, String}}(
    (+) => ("arith1", "plus"),
    (*) => ("arith1", "times"),
    (/) => ("arith1", "divide"),
    (^) => ("arith1", "power"),
    abs => ("arith1", "abs"),
    exp => ("transc1", "exp"),
    log => ("transc1", "ln"),
    max => ("minmax1", "max"),
    min => ("minmax1", "min"),
    inv => ("arith1", "divide"),
    identity => ("fns1", "identity"),
    (<) => ("relation1", "lt"),
    (>) => ("relation1", "gt"),
    (<=) => ("relation1", "leq"),
    (>=) => ("relation1", "geq"),
    (==) => ("relation1", "eq"),
    (!=) => ("relation1", "neq"),
    (&) => ("logic1", "and"),
    (|) => ("logic1", "or"),
    (!) => ("logic1", "not"),
    xor => ("logic1", "xor")
)

for (f, name) in ((sin, "sin"), (cos, "cos"), (tan, "tan"),
    (sec, "sec"), (csc, "csc"), (cot, "cot"),
    (sinh, "sinh"), (cosh, "cosh"), (tanh, "tanh"),
    (sech, "sech"), (csch, "csch"), (coth, "coth"),
    (asin, "arcsin"), (acos, "arccos"), (atan, "arctan"),
    (asec, "arcsec"), (acsc, "arccsc"), (acot, "arccot"),
    (asinh, "arcsinh"), (acosh, "arccosh"), (atanh, "arctanh"),
    (asech, "arcsech"), (acsch, "arccsch"), (acoth, "arccoth"))
    _OPERATORS[f] = ("transc1", name)
end

_sym(cd, name) = OMSymbol(cd, name)

OpenMath.to_openmath(x::Num) = OpenMath.to_openmath(unwrap(x))

function OpenMath.to_openmath(eq::Equation)
    _sym("relation1", "eq")(OpenMath.to_openmath(eq.lhs), OpenMath.to_openmath(eq.rhs))
end

function OpenMath.to_openmath(x::Symbolics.BasicSymbolic)
    issym(x) && return OMVariable(String(nameof(x)))

    # A literal inside an expression is still a symbolic node — `x + 1` holds a
    # constant node, not an `Int`. `Symbolics.value` is the public way down to
    # the Julia number, and the type check keeps a value that does not reduce
    # from recursing forever.
    if !iscall(x)
        v = Symbolics.value(x)
        v isa Symbolics.BasicSymbolic && throw(OpenMathConversionError(typeof(x),
            "this symbolic value is neither a variable, an application nor a " *
            "literal"))
        return OpenMath.to_openmath(v)
    end

    op = operation(x)
    args = arguments(x)

    # A derivative is not an operator in OpenMath: `calculus1#diff` applies to a
    # *function*, so the bound variable has to be carried by an `fns1#lambda`.
    if op isa Differential
        v = unwrap(op.x)
        issym(v) || throw(OpenMathConversionError(Differential,
            "a derivative is taken with respect to a variable"))
        body = OpenMath.to_openmath(only(args))
        lambda = OMBinding(_sym("fns1", "lambda"),
            [OMBoundVariable(String(nameof(v)))], body)
        return _sym("calculus1", "diff")(lambda)
    end

    # `ifelse(c, a, b)` is the two-branch case of `piece1`: a piecewise value is
    # a sequence of (value, condition) pieces closed by an `otherwise`.
    if op === ifelse
        cond, yes, no = args
        return _sym("piece1", "piecewise")(
            _sym("piece1", "piece")(OpenMath.to_openmath(yes),
                OpenMath.to_openmath(cond)),
            _sym("piece1", "otherwise")(OpenMath.to_openmath(no)))
    end

    # `sqrt(x)` is `x^(1/2)` in some normal forms and a call in others; write it
    # as `arith1#root`, which is what the CD has.
    op === sqrt && return _sym("arith1", "root")(
        OpenMath.to_openmath(only(args)), OMInteger(2))

    # `transc1#log` carries the base; `transc1#ln` is the natural logarithm and
    # carries none. Julia spells the first two ways — `log10(x)` and `log(b, x)`
    # — and the second as one-argument `log`, which is why `_OPERATORS` cannot
    # hold either of the first two: they need an argument moved or invented.
    op === log10 && return _sym("transc1", "log")(
        OMInteger(10), OpenMath.to_openmath(only(args)))
    op === log2 && return _sym("transc1", "log")(
        OMInteger(2), OpenMath.to_openmath(only(args)))
    if op === log && length(args) == 2
        return _sym("transc1", "log")(map(OpenMath.to_openmath, args)...)
    end

    # Julia's `-` is unary or binary; OpenMath gives them different symbols.
    if op === (-)
        length(args) == 1 && return _sym("arith1", "unary_minus")(
            OpenMath.to_openmath(only(args)))
        return _sym("arith1", "minus")(map(OpenMath.to_openmath, args)...)
    end

    # Symbolics keeps sums and products as `Add`/`Mul` nodes with a coefficient,
    # and a unit coefficient leaves a one-argument node behind: `x^4` can arrive
    # as `*(x^4)`. A product of one factor is that factor, so writing
    # `arith1#times(x)` would put a host-language representation artefact into
    # the OpenMath — something no other producer would emit, and enough to make
    # the round trip through Symbolics stop being the identity. Found by the
    # generated property, not by any of the hand-written cases.
    if (op === (+) || op === (*)) && length(args) == 1
        return OpenMath.to_openmath(only(args))
    end

    entry = get(_OPERATORS, op, nothing)
    entry === nothing && throw(OpenMathConversionError(typeof(x),
        "no Content Dictionary symbol is mapped to $(op); add one with " *
        "`define!` or extend `to_openmath`"))
    return _sym(entry...)(map(OpenMath.to_openmath, args)...)
end

# --- OpenMath → Symbolics -----------------------------------------------------

"""
    OpenMath.symbolics_phrasebook() -> Phrasebook

A [`Phrasebook`](@ref) whose variables are `Symbolics` variables and which knows
`calculus1#diff`, `fns1#lambda` and `relation1#eq`.

# Examples
```julia
julia> using OpenMath, Symbolics

julia> p = OpenMath.symbolics_phrasebook();

julia> interpret(p, OMS"transc1#sin"(OMVariable("x")))
sin(x)
```
"""
function OpenMath.symbolics_phrasebook()
    p = Phrasebook(; name = "symbolics")
    define_variable!(p, name -> Symbolics.variable(Symbol(name)))
    # Literals become `Num`s, so that an application of a mapped symbol to them
    # builds a symbolic expression instead of being computed. Without this,
    # `transc1#sin` applied to `OMI(-8)` comes back as -0.9893…, and the round
    # trip through `sin(-8)` is not the identity.
    define_leaf!(p, v -> v isa Number ? Num(v) : v)

    # An `fns1#lambda` binding becomes the pair (bound variables, body), which is
    # the only thing `calculus1#diff` needs and the only thing Symbolics can hold
    # — it has no lambda of its own.
    define!(p, OMSymbol("fns1", "lambda"), _lambda_marker)
    define!(p, OMSymbol("calculus1", "diff"), _diff)
    define!(p, OMSymbol("relation1", "eq"), (a, b) -> a ~ b)
    # `arith1#root(a, 2)` is `sqrt(a)`, which is what Symbolics keeps as a
    # distinct operation. Writing it as `a^(1//2)` is the same number and a
    # different expression, and the round trip would stop being exact.
    define!(p, OMSymbol("arith1", "root"), _root)
    # `log(10, x)` is `log(x)/log(10)` to Symbolics: the same number and a
    # different expression. `log10` is the one Symbolics keeps whole, so the
    # round trip is only exact if the common bases are spelled that way.
    define!(p, OMSymbol("transc1", "log"), _log)
    define!(p, OMSymbol("piece1", "piece"), (value, condition) -> _Piece(value, condition))
    define!(p, OMSymbol("piece1", "otherwise"), value -> _Otherwise(value))
    define!(p, OMSymbol("piece1", "piecewise"), _piecewise)
    return p
end

struct _Piece
    value::Any
    condition::Any
end

struct _Otherwise
    value::Any
end

# `piece1` writes the branches flat; `ifelse` can only nest, so they are folded
# from the last piece outwards.
function _piecewise(parts...)
    isempty(parts) && throw(OpenMathConversionError(OMApplication,
        "piece1#piecewise with no branches"))
    last(parts) isa _Otherwise || throw(OpenMathConversionError(OMApplication,
        "this phrasebook maps piece1#piecewise onto `ifelse`, which is total, so " *
        "the last branch must be a piece1#otherwise; inventing a default would " *
        "be a silent change of meaning"))
    result = last(parts).value
    for part in Iterators.reverse(parts[1:(end - 1)])
        part isa _Piece || throw(OpenMathConversionError(OMApplication,
            "every branch of a piece1#piecewise before the last is a piece1#piece"))
        # `relation1#eq` becomes a Symbolics `Equation`, which is the right
        # reading of an equation and the wrong one for a *condition*: `ifelse`
        # takes a truth value. Symbolics has no symbolic equality predicate —
        # `==` on symbolic values is eager and returns a `Bool` — so this is a
        # genuine gap between the two languages rather than something to paper
        # over. See docs/src/design/phrasebook.md.
        part.condition isa Equation && throw(OpenMathConversionError(OMApplication,
            "a piece1#piece condition became a Symbolics `Equation`, which " *
            "`ifelse` cannot take. Symbolics has no symbolic equality predicate, " *
            "so relation1#eq has no counterpart in a condition; use an " *
            "inequality, or interpret this object with a different phrasebook"))
        result = ifelse(part.condition, part.value, result)
    end
    # `ifelse` on symbolic values returns the unwrapped representation; wrap it,
    # so that every entry in this phrasebook hands back the same type.
    return result isa Symbolics.BasicSymbolic ? Num(result) : result
end

_root(a, b) = (b isa Number && b == 2) ? sqrt(a) : a^(1 // b)

function _log(base, x)
    base isa Number || return log(base, x)
    base == 10 && return log10(x)
    base == 2 && return log2(x)
    return log(base, x)
end

struct _Lambda
    variables::Vector{Num}
    body::Any
end

function _lambda_marker(args...)
    throw(OpenMathConversionError(OMApplication,
        "fns1#lambda is a binder, not a function; it appears as an OMBIND"))
end

function _diff(f)
    f isa _Lambda || throw(OpenMathConversionError(OMApplication,
        "calculus1#diff applies to a function, so its argument is an " *
        "fns1#lambda binding (§4.2)"))
    d = foldl((e, v) -> Differential(v)(e), f.variables; init = f.body)
    return d
end

# A binding is the one composite `interpret` cannot handle generically: the bound
# variables have to become values before the body is interpreted.
function OpenMath.interpret(p::Phrasebook, x::OMBinding)
    binder = x.binder
    (binder isa OMSymbol && binder.cd == "fns1" && binder.name == "lambda") ||
        throw(OpenMathConversionError(OMBinding,
            "this phrasebook binds only fns1#lambda"))
    vars = [p.variable[](v.name) for v in x.variables]
    return _Lambda(vars, OpenMath.interpret(p, x.body))
end

end # module
