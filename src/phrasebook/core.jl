# SPDX-License-Identifier: MIT
#
# Phrasebooks (REQ-PHR-001, REQ-PHR-003, REQ-PHR-005); see
# docs/src/design/phrasebook.md.
#
# A phrasebook is OpenMath's own word for the translation between objects and the
# values of one particular system. This package already had a fixed one —
# `to_openmath` and `from_openmath`, extended by dispatch — which is the right
# default and the wrong *only* mechanism: two callers in one session may
# legitimately disagree about what `nums1#rational` denotes, and a method table
# cannot hold both readings at once. A `Phrasebook` is that translation as a
# value.
#
# Two properties this file exists to guarantee:
#
#  * **Interpretation is structural.** A symbol name is a key in a dictionary and
#    the *function* found there is applied. The name is never turned into code,
#    so `nowhere#run` does not become anything and `OMV("exit")` is the Julia
#    symbol `:exit`, not `Base.exit` (REQ-PHR-003, §5.4).
#
#  * **Nothing is dropped quietly.** A symbol with no entry raises and names
#    itself. A phrasebook that ignored an attribution it did not understand would
#    turn a faithful document into a plausible lie (REQ-PHR-005).

"""
    Phrasebook()

The translation between OpenMath objects and Julia values, as a value.

A fresh phrasebook contains the built-in vocabulary — the same correspondence
[`from_openmath`](@ref) uses. Add to it with [`define!`](@ref), apply it with
[`interpret`](@ref) and [`express`](@ref), and make it the default for a dynamic
scope with [`with_phrasebook`](@ref).

Entries are keyed on `(cdbase, cd, name)`, because the same `cd` and `name` under
a different base is a different symbol (standard §2.1.4).

# Examples
```jldoctest
julia> using OpenMath

julia> p = Phrasebook();

julia> interpret(p, OMS"arith1#plus"(OMInteger(1), OMInteger(2)))
3

julia> define!(p, OMS"arith1#plus", (xs...) -> "intercepted");

julia> interpret(p, OMS"arith1#plus"(OMInteger(1), OMInteger(2)))
"intercepted"
```
"""
struct Phrasebook
    forward::Dict{Tuple{String, String, String}, Any}
    backward::Dict{Type, Any}
    # How a *variable* becomes a value. `Symbol` by default, which is right for
    # plain Julia; a computer algebra system wants its own variable type, and
    # that has to be part of the phrasebook rather than a method on `interpret`,
    # or two phrasebooks in one session could not disagree (REQ-PHR-001).
    variable::Base.RefValue{Any}
    # How a *literal* becomes a value. `identity` by default. A computer algebra
    # system needs its own wrapper here for the same reason it needs one for
    # variables: without it `transc1#sin` applied to `OMI(-8)` reaches Julia's
    # `sin` with a plain `Int` and is *evaluated*, which this package does not do
    # (REQ-PHR-006). Found by the generated round-trip property, on `sin(-8)`.
    leaf::Base.RefValue{Any}
    name::String
end

Phrasebook(; name::AbstractString = "phrasebook") = _base_phrasebook(String(name))

function Base.show(io::IO, p::Phrasebook)
    print(io, "Phrasebook(", repr(p.name), ", ", length(p.forward), " symbols, ",
        length(p.backward), " types)")
    return nothing
end

# The key a symbol resolves to. `resolve_cdbase`'s rule, applied here so that the
# phrasebook and the passes cannot disagree about what counts as the same symbol.
function _key(s::OMSymbol)
    (s.cdbase === nothing ? CD_BASE : s.cdbase, s.cd, s.name)
end

"""
    define!(p, symbol, forward)
    define!(p, symbol, forward, backward)

Teach `p` that `symbol` denotes `forward`, which is applied to the interpreted
arguments of an application, or called with no arguments for a bare symbol.

`backward` is the reverse: a function from a Julia value to an `OMNode`, keyed on
the type of its argument, used by [`express`](@ref).

# Examples
```jldoctest
julia> using OpenMath

julia> p = Phrasebook();

julia> define!(p, OMS"arith1#plus", +);

julia> interpret(p, OMS"arith1#plus"(OMInteger(1), OMInteger(2)))
3
```
"""
function define!(p::Phrasebook, s::OMSymbol, forward)
    p.forward[_key(s)] = forward
    return p
end

function define!(p::Phrasebook, s::OMSymbol, forward, backward)
    p.forward[_key(s)] = forward
    p.backward[_sole_argument_type(backward)] = backward
    return p
end

"""
    define!(p, T::Type, backward)

Teach `p` to express Julia values of type `T`, without claiming a symbol.
"""
function define!(p::Phrasebook, T::Type, backward)
    p.backward[T] = backward
    return p
end

# The argument type `backward` was written for, so that `express` can dispatch on
# it without the caller having to repeat it.
function _sole_argument_type(f)
    ms = collect(methods(f))
    length(ms) == 1 || throw(ArgumentError(
        "the backward direction of a phrasebook entry must have exactly one " *
        "method, so that its argument type is unambiguous; got $(length(ms)). " *
        "Pass the type explicitly with `define!(p, T, backward)`."))
    sig = Base.unwrap_unionall(only(ms).sig)
    length(sig.parameters) == 2 || throw(ArgumentError(
        "the backward direction of a phrasebook entry takes exactly one argument"))
    T = sig.parameters[2]
    return T isa Type ? T : Any
end

"""
    define_variable!(p, f)

Teach `p` to turn a variable name into a value with `f`, a function of one
`String`. The default is `Symbol`.

This is what a computer algebra system replaces: `Symbolics` wants its own
variable objects, and a phrasebook that could not say so would force every caller
in the session to agree.

# Examples
```jldoctest
julia> using OpenMath

julia> p = Phrasebook();

julia> define_variable!(p, name -> Symbol(name));

julia> interpret(p, OMVariable("x"))
:x
```
"""
function define_variable!(p::Phrasebook, f)
    p.variable[] = f
    return p
end

"""
    define_leaf!(p, f)

Teach `p` to turn a literal — an integer, float, string or byte array — into a
value with `f`. The default is `identity`.

The reason this exists is narrower than it looks. A phrasebook whose symbols map
onto ordinary Julia functions will *evaluate* an application of them to literals:
`transc1#sin` applied to `OMI(-8)` reaches `Base.sin` with an `Int` and returns a
`Float64`. For plain Julia that is exactly right. For a computer algebra system it
is not — it should stay symbolic — and this is where that is said.

# Examples
```jldoctest
julia> using OpenMath

julia> p = Phrasebook();

julia> interpret(p, OMInteger(2))
2

julia> define_leaf!(p, v -> v isa Number ? float(v) : v);

julia> interpret(p, OMInteger(2))
2.0
```
"""
function define_leaf!(p::Phrasebook, f)
    p.leaf[] = f
    return p
end

"""
    symbols(p) -> Vector{OMSymbol}

Every symbol `p` can interpret.

# Examples
```jldoctest
julia> using OpenMath

julia> length(symbols(Phrasebook())) > 60
true
```
"""
function symbols(p::Phrasebook)
    out = [OMSymbol(base, cd, name, nothing) for (base, cd, name) in keys(p.forward)]
    sort!(out; by = s -> (s.cdbase, s.cd, s.name))
    return out
end

# --- the scoped default -------------------------------------------------------

const _PHRASEBOOK = Ref{Union{Nothing, Phrasebook}}(nothing)

"""
    current_phrasebook() -> Phrasebook

The phrasebook in force for the current dynamic scope.

# Examples
```jldoctest
julia> using OpenMath

julia> current_phrasebook().name
"default"
```
"""
function current_phrasebook()
    p = _PHRASEBOOK[]
    p === nothing || return p
    q = Phrasebook(; name = "default")
    _PHRASEBOOK[] = q
    return q
end

"""
    with_phrasebook(f, p::Phrasebook)

Run `f()` with `p` as the default phrasebook, restoring the previous one
afterwards — including when `f` throws.

# Examples
```jldoctest
julia> using OpenMath

julia> p = Phrasebook();

julia> define!(p, OMS"arith1#plus", (xs...) -> :intercepted);

julia> with_phrasebook(p) do
           from_openmath(OMS"arith1#plus"(OMInteger(1), OMInteger(2)))
       end
:intercepted
```
"""
function with_phrasebook(f, p::Phrasebook)
    old = _PHRASEBOOK[]
    _PHRASEBOOK[] = p
    try
        return f()
    finally
        _PHRASEBOOK[] = old
    end
end

# --- interpretation -----------------------------------------------------------

"""
    interpret(p::Phrasebook, x) -> Any

The Julia value `p` gives to the OpenMath object `x`.

Raises [`OpenMathConversionError`](@ref) for anything `p` has no entry for,
naming the symbol. Nothing is dropped silently (REQ-PHR-005).

# Examples
```jldoctest
julia> using OpenMath

julia> interpret(Phrasebook(), OMS"arith1#plus"(OMInteger(1), OMInteger(2)))
3
```
"""
interpret(p::Phrasebook, x::OMObject) = interpret(p, x.object)
interpret(p::Phrasebook, x::OMInteger) = p.leaf[](x.value)
interpret(p::Phrasebook, x::OMFloat) = p.leaf[](x.value)
interpret(p::Phrasebook, x::OMString) = p.leaf[](x.value)
interpret(p::Phrasebook, x::OMBytes) = p.leaf[](x.value)
interpret(p::Phrasebook, x::OMVariable) = p.variable[](x.name)

function interpret(p::Phrasebook, x::OMSymbol)
    f = get(p.forward, _key(x), nothing)
    f === nothing && _unknown(x)
    return f isa Function ? f() : f
end

function interpret(p::Phrasebook, x::OMApplication)
    head = x.applicant
    head isa OMSymbol || throw(OpenMathConversionError(OMApplication,
        "cannot interpret an application whose applicant is not a symbol"))
    f = get(p.forward, _key(head), nothing)
    f === nothing && _unknown(head, length(x.arguments))
    return f((interpret(p, a) for a in x.arguments)...)
end

function interpret(p::Phrasebook, x::Union{OMOrForeign, OMObject})
    throw(OpenMathConversionError(typeof(x),
        "no phrasebook entry interprets $(kind(x))"))
end

function _unknown(s::OMSymbol, arity::Union{Nothing, Int} = nothing)
    where_ = s.cdbase === nothing ? "" : " (cdbase $(s.cdbase))"
    what = arity === nothing ? "$(s.cd)#$(s.name)" : "$(s.cd)#$(s.name)/$(arity)"
    throw(OpenMathConversionError(OMSymbol,
        "this phrasebook has no entry for $(what)$(where_)"))
end

"""
    express(p::Phrasebook, v) -> OMNode

The OpenMath object `p` gives to the Julia value `v`, falling back to
[`to_openmath`](@ref) for types `p` says nothing about.

# Examples
```jldoctest
julia> using OpenMath

julia> express(Phrasebook(), 3)
OMI(3)
```
"""
function express(p::Phrasebook, v)
    best = nothing
    for (T, f) in p.backward
        v isa T || continue
        # Most specific wins, so a rule for `Metres` beats one for `Any`, and the
        # result does not depend on dictionary order.
        (best === nothing || T <: best[1]) && (best = (T, f))
    end
    best === nothing && return to_openmath(v)
    return best[2](v)
end

"""
    OpenMath.symbolics_phrasebook() -> Phrasebook

A [`Phrasebook`](@ref) for `Symbolics.jl` expressions. Defined by the package
extension, so it needs `Symbolics` to be loaded.
"""
function symbolics_phrasebook end
