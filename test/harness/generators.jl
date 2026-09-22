# SPDX-License-Identifier: MIT
#
# Generators for arbitrary OpenMath objects (harness spec §6.4).
#
# Every generator produces objects the constructors accept, so a property failure
# always means the property is false — never that the generator built nonsense.
# The interesting values are deliberately over-represented: the Int64 boundaries,
# the floats with no decimal spelling, the signed zeros, empty strings and byte
# arrays, non-ASCII names.

module Generators

using Supposition
using Supposition.Data
using OpenMath

# --- names --------------------------------------------------------------------

# A spread across the Name production of standard §2.3 rather than just ASCII:
# the ranges either side of the U+00D7 gap, a combining mark, CJK, and the
# characters that are NameChar but not NameStartChar.
const NAME_START = collect("abzABZ_:αλΩℝ変é")
const NAME_REST = collect("abzABZ_:αλΩℝ変é0.9-̀")

const gen_name = @composed (
    first = Data.SampledFrom(NAME_START),
    rest = Data.Text(Data.SampledFrom(NAME_REST); max_len = 5)
) -> string(first, rest)

# --- leaves -------------------------------------------------------------------

const _SMALL = Data.Integers(-8, 8)

# Boundaries first: an encoder that only ever sees small positive integers looks
# correct right up until it meets typemin(Int64) or a bignum.
const _BOUNDARY_INTS = Data.SampledFrom(
    Any[0, 1, -1, typemax(Int64), typemin(Int64), typemax(Int64) - 1,
    BigInt(2) ^ 63, -BigInt(2) ^ 63 - 1, BigInt(2) ^ 200, -BigInt(2) ^ 200 + 1,
    BigInt(10) ^ 100])

const gen_integer = map(OMInteger,
    Data.OneOf(map(Int, _SMALL), _BOUNDARY_INTS,
        Data.Integers(typemin(Int64), typemax(Int64))))

# The values with no decimal spelling, plus the ones a naive encoder collapses.
const _SPECIAL_FLOATS = Data.SampledFrom(
    Float64[NaN, Inf, -Inf, 0.0, -0.0, 5.0e-324, 1.0e308, -1.0e308,
    eps(Float64), 1 / 3])

const gen_float = map(OMFloat, Data.OneOf(_SPECIAL_FLOATS, Data.Floats{Float64}()))

const gen_string = map(OMString,
    Data.OneOf(Data.Just(""),
        Data.SampledFrom(["  spaced  ", "a<b&c>d", "]]>",
            "λ ℝ 変数", "\n\t", "'\""]),
        Data.Text(Data.AsciiCharacters(); max_len = 8)))

const gen_bytes = map(OMBytes,
    Data.Vectors(Data.Integers(0, 255); min_size = 0, max_size = 8) |>
    g -> map(v -> UInt8.(v), g))

const gen_variable = map(OMVariable, gen_name)

const gen_symbol = @composed (
    cd = gen_name,
    name = gen_name,
    base = Data.SampledFrom(Union{Nothing, String}[nothing, OpenMath.CD_BASE,
        "http://example.org/cd",
        "urn:example:cd"])
) -> OMSymbol(cd, name; cdbase = base)

# Foreign content is verbatim source, so only well-formed fragments appear here:
# anything else is a value the writer is required to refuse, which is its own test.
const _FOREIGNS = Union{Nothing, OMForeign}[
    nothing,
    OMForeign("text/plain", "text"),
    OMForeign("application/mathml+xml", "<mi>x</mi>"),
    OMForeign(nothing, "a &amp; b"),
    OMForeign("text/html", "<b class=\"x\">bold</b>")
]

const gen_leaf = Data.OneOf(gen_integer, gen_float, gen_string, gen_bytes,
    gen_variable, gen_symbol)

# --- composites ---------------------------------------------------------------

# `@composed` defines a global method, so it cannot appear inside a function —
# and `Data.Recursive` hands the child generator to a function. The composites are
# therefore assembled by `map` over nested `Data.Pairs`, which composes anywhere.
#
# `_SHAPE` carries the three discrete choices — which composite, which cdbase,
# which foreign argument — so that they shrink as ordinary sampled values.
const _SHAPE = Data.SampledFrom(
    [(which, base, foreign)
     for which in 1:4
     for base in Union{Nothing, String}[nothing, nothing, "http://example.org/cd",
    "http://other.example/cd"]
     for foreign in eachindex(_FOREIGNS)])

function _assemble(shape, kids, sym, names)
    which, base, foreign = shape
    if which == 1
        return OMApplication(kids[1], Vector{OMNode}(kids[2:end]); cdbase = base)
    elseif which == 2
        return OMBinding(kids[1], [OMBoundVariable(n) for n in names], kids[end];
            cdbase = base)
    elseif which == 3
        args = OMOrForeign[k for k in kids]
        f = _FOREIGNS[foreign]
        f === nothing || push!(args, f)
        return OMError(sym, args; cdbase = base)
    else
        return OMAttribution([OMAttributePair(sym, kids[1])], kids[end]; cdbase = base)
    end
end

function _composite(child)
    kids = Data.Vectors(child; min_size = 1, max_size = 4)
    extra = Data.Pairs(gen_symbol, Data.Vectors(gen_name; min_size = 1, max_size = 2))
    return map(Data.Pairs(Data.Pairs(kids, _SHAPE), extra)) do p
        (ks, shape) = p.first
        (sym, names) = p.second
        _assemble(shape, ks, sym, names)
    end
end

"""
    gen_node(; max_layers = 3)

Arbitrary OpenMath objects, depth-bounded.
"""
function gen_node(; max_layers::Int = 3)
    Data.Recursive(gen_leaf, _composite; max_layers = max_layers)
end

"""
    gen_object(; max_layers = 3)

Arbitrary `OMObject` document roots.
"""
function gen_object(; max_layers::Int = 3)
    bases = Data.SampledFrom(Union{Nothing, String}[nothing, nothing,
        "http://example.org/cd"])
    return map(Data.Pairs(gen_node(; max_layers = max_layers), bases)) do p
        OMObject(p.first; cdbase = p.second)
    end
end

"""
    gen_shared(; max_layers = 2)

Objects built to *contain repetition*, for exercising [`share_structure`](@ref).

`gen_node` produces a repeated subtree about once in thirteen draws, and never
more than one — so a property checked on it spends nine tenths of its budget
asserting that sharing an object with nothing to share returns it unchanged.
This plants a composite subtree at several positions instead, so the pass has
work to do on every example.
"""
function gen_shared(; max_layers::Int = 2)
    body = _composite(gen_node(; max_layers = max_layers))
    return map(Data.Pairs(Data.Pairs(body, gen_node(; max_layers = max_layers)),
        gen_symbol)) do p
        (repeated, other) = p.first
        head = p.second
        # `repeated` appears three times, twice at the same depth and once
        # nested, so both the flat case and the case where a shared subtree
        # contains another are reached.
        inner = OMApplication(head, OMNode[repeated, other])
        return OMApplication(head, OMNode[repeated, other, repeated, inner])
    end
end

# --- vacuity ------------------------------------------------------------------

"""
    diversity(gen, n) -> Dict{Symbol,Int}

How many of each object kind `n` draws from `gen` actually produced. A property
that holds because the generator only ever built `OMI(0)` holds vacuously, so the
property layer asserts a floor on this (harness spec §4.5).
"""
function diversity(gen, n::Int)
    counts = Dict{Symbol, Int}()
    for obj in example(gen, n)
        node = obj isa OMObject ? obj.object : obj
        OpenMath.walk(node) do x
            k = OpenMath.kind(x)
            counts[k] = get(counts, k, 0) + 1
        end
    end
    return counts
end

"""
    xml_representable(obj) -> Bool

Whether every character in `obj` is one XML 1.0 §2.2 admits.

A C0 control other than tab, newline and carriage return is not a legal XML
character and XML has no escape for one, so a string holding one has no XML
representation at all. JSON and the binary encoding carry it exactly.

This exists because the properties about XML used to assume every generated
object round-trips through it. They passed for a year while the writer emitted a
raw NUL and the reader read it back — the two agreed with each other, and the
document was one no conforming XML parser would accept. `docs/src/round-trip.md`
lists the loss; `test/unit/xml_writer.jl` checks the refusal is exact.
"""
function xml_representable(x)
    for n in OpenMath.collect_nodes(x)
        text = if n isa OpenMath.OMString
            n.value
        elseif n isa OpenMath.OMVariable
            n.name
        elseif n isa OpenMath.OMForeign
            n.value
        else
            continue
        end
        for c in text
            u = UInt32(c)
            ok = u == 0x09 || u == 0x0a || u == 0x0d ||
                 (0x20 <= u <= 0xd7ff) || (0xe000 <= u <= 0xfffd) ||
                 (0x10000 <= u <= 0x10ffff)
            ok || return false
        end
    end
    return true
end

end # module
