# SPDX-License-Identifier: MIT
#
# The built-in vocabulary: the Content Dictionary symbols a fresh `Phrasebook`
# knows, and the Julia values they denote.
#
# The target is MathML.jl's table, symbol by symbol, because that is the
# vocabulary a Julia caller coming from SBML or SciML already has (see
# docs/src/design/phrasebook.md). The names line up because MathML's Content
# elements were named after these Content Dictionaries in the first place.
#
# Everything here is data. No entry is a string that becomes code (REQ-PHR-003).

# `arith1#minus` is binary and `arith1#unary_minus` is unary, so the n-ary Julia
# operators need narrowing rather than splatting.
_om_minus(a, b) = a - b
_om_divide(a, b) = a / b
_om_power(a, b) = a^b
_om_root(a, b) = a^(1 // b)

# nums1#rational must stay exact: `//` on integers, `/` otherwise.
_om_rational(a, b) = (a isa Integer && b isa Integer) ? a // b : a / b

function _om_matrix(rows...)
    isempty(rows) && return Matrix{Any}(undef, 0, 0)
    n = length(first(rows))
    all(r -> length(r) == n, rows) || throw(OpenMathConversionError(
        OMApplication, "matrix rows have differing lengths"))
    return permutedims(reduce(hcat, collect.(rows)))
end

_om_mean(xs...) = sum(xs) / length(xs)

function _om_median(xs...)
    isempty(xs) && throw(OpenMathConversionError(OMApplication,
        "s_data1#median of no data"))
    v = sort!(collect(xs))
    n = length(v)
    return isodd(n) ? v[(n + 1) ÷ 2] : (v[n ÷ 2] + v[n ÷ 2 + 1]) / 2
end

function _om_mode(xs...)
    isempty(xs) && throw(OpenMathConversionError(OMApplication,
        "s_data1#mode of no data"))
    counts = Dict{Any, Int}()
    for x in xs
        counts[x] = get(counts, x, 0) + 1
    end
    best = maximum(values(counts))
    # `s_data1#mode` is the most frequent value; ties are resolved by order of
    # appearance, which at least makes the answer deterministic.
    for x in xs
        counts[x] == best && return x
    end
end

# The `s_data1` CD defines the *sample* variance, dividing by n - 1.
function _om_variance(xs...)
    length(xs) < 2 && throw(OpenMathConversionError(OMApplication,
        "s_data1#variance needs at least two values"))
    m = _om_mean(xs...)
    return sum(abs2(x - m) for x in xs) / (length(xs) - 1)
end

_om_sdev(xs...) = sqrt(_om_variance(xs...))

# (cd, name) => the Julia value or function it denotes, all under the official
# cdbase. A nullary entry is a constant; anything else is applied to the
# interpreted arguments.
const _BASE_VOCABULARY = Dict{Tuple{String, String}, Any}(
    # --- constants and truth values -----------------------------------------
    ("logic1", "true") => () -> true,
    ("logic1", "false") => () -> false,
    ("nums1", "pi") => () -> π,
    ("nums1", "e") => () -> ℯ,
    ("nums1", "infinity") => () -> Inf,
    ("nums1", "NaN") => () -> NaN,
    ("nums1", "i") => () -> im,

    # --- arithmetic -----------------------------------------------------------
    ("arith1", "plus") => +,
    ("arith1", "times") => *,
    ("arith1", "minus") => _om_minus,
    ("arith1", "unary_minus") => -,
    ("arith1", "divide") => _om_divide,
    ("arith1", "power") => _om_power,
    ("arith1", "abs") => abs,
    ("arith1", "root") => _om_root,
    ("arith1", "gcd") => gcd,
    ("arith1", "lcm") => lcm,
    ("arith1", "sum") => +,
    ("arith1", "product") => *,

    # --- numbers --------------------------------------------------------------
    ("nums1", "rational") => _om_rational,
    ("nums1", "complex_cartesian") => complex,
    ("integer1", "factorial") => factorial,
    ("integer1", "quotient") => div,
    ("integer1", "remainder") => rem,
    ("rounding1", "ceiling") => ceil,
    ("rounding1", "floor") => floor,
    ("rounding1", "round") => round,
    ("rounding1", "trunc") => trunc,
    ("minmax1", "min") => min,
    ("minmax1", "max") => max,

    # --- complex --------------------------------------------------------------
    ("complex1", "real") => real,
    ("complex1", "imaginary") => imag,
    ("complex1", "conjugate") => conj,
    ("complex1", "argument") => angle,

    # --- transcendental -------------------------------------------------------
    ("transc1", "exp") => exp,
    ("transc1", "ln") => log,
    ("transc1", "log") => log,
    ("transc1", "sin") => sin, ("transc1", "cos") => cos, ("transc1", "tan") => tan,
    ("transc1", "sec") => sec, ("transc1", "csc") => csc, ("transc1", "cot") => cot,
    ("transc1", "sinh") => sinh, ("transc1", "cosh") => cosh,
    ("transc1", "tanh") => tanh, ("transc1", "sech") => sech,
    ("transc1", "csch") => csch, ("transc1", "coth") => coth,
    ("transc1", "arcsin") => asin, ("transc1", "arccos") => acos,
    ("transc1", "arctan") => atan, ("transc1", "arcsec") => asec,
    ("transc1", "arccsc") => acsc, ("transc1", "arccot") => acot,
    ("transc1", "arcsinh") => asinh, ("transc1", "arccosh") => acosh,
    ("transc1", "arctanh") => atanh, ("transc1", "arcsech") => asech,
    ("transc1", "arccsch") => acsch, ("transc1", "arccoth") => acoth,

    # --- relations ------------------------------------------------------------
    ("relation1", "eq") => ==,
    ("relation1", "neq") => !=,
    ("relation1", "lt") => <,
    ("relation1", "gt") => >,
    ("relation1", "leq") => <=,
    ("relation1", "geq") => >=,
    ("relation1", "approx") => isapprox,

    # --- logic ----------------------------------------------------------------
    ("logic1", "and") => &,
    ("logic1", "or") => |,
    ("logic1", "xor") => xor,
    ("logic1", "not") => !,
    ("logic1", "implies") => (a, b) -> !a | b,
    ("logic1", "equivalent") => ==,

    # --- linear algebra and collections ---------------------------------------
    ("linalg2", "vector") => (xs...) -> collect(xs),
    ("linalg2", "matrixrow") => (xs...) -> collect(xs),
    ("linalg2", "matrix") => _om_matrix,
    ("list1", "list") => (xs...) -> collect(xs),
    ("set1", "set") => (xs...) -> Set(xs),

    # --- functions on functions ----------------------------------------------
    ("fns1", "identity") => identity,
    ("fns1", "inverse") => inv,
    ("fns1", "left_compose") => (fs...) -> reduce(∘, fs),

    # --- statistics -----------------------------------------------------------
    #
    # Written out rather than taken from `Statistics`, which would be a
    # dependency for four symbols. They are also the definitions the `s_data1`
    # Content Dictionary gives, which is the point: the phrasebook should say
    # what the CD says, not what the nearest Julia function happens to do.
    ("s_data1", "mean") => _om_mean,
    ("s_data1", "median") => _om_median,
    ("s_data1", "mode") => _om_mode,
    ("s_data1", "variance") => _om_variance,
    ("s_data1", "sdev") => _om_sdev
)

# The Julia types a fresh phrasebook can express, beyond whatever `to_openmath`
# already handles by dispatch. Kept empty on purpose: the default backward
# direction *is* `to_openmath`, and duplicating it here would give two places to
# change.
function _base_phrasebook(name::String)
    forward = Dict{Tuple{String, String, String}, Any}()
    for ((cd, sym), f) in _BASE_VOCABULARY
        forward[(CD_BASE, cd, sym)] = f
    end
    return Phrasebook(forward, Dict{Type, Any}(),
        Base.RefValue{Any}(Symbol), Base.RefValue{Any}(identity), name)
end

"""
    base_vocabulary() -> Vector{OMSymbol}

Every symbol a fresh [`Phrasebook`](@ref) knows, sorted, with `cdbase` resolved.

Resolved, because the key is `(cdbase, cd, name)` and the base is part of a
symbol's identity (§2.1.4). So comparing against a literal needs
[`resolve_cdbase`](@ref), which is the same normalisation the passes and the
writers apply.

# Examples
```jldoctest
julia> using OpenMath

julia> length(base_vocabulary()) > 60
true

julia> resolve_cdbase(OMS"arith1#plus") in base_vocabulary()
true

julia> OMS"arith1#plus" in base_vocabulary()     # no cdbase, so not the same value
false
```
"""
base_vocabulary() = symbols(Phrasebook())
