# SPDX-License-Identifier: MIT
#
# The conformance corpus and its driver (harness spec §6.2, §6.3).
#
# The property that matters here is that corpus growth is monotone and encoding
# coverage is automatic: the driver derives the encodings an item does not carry
# from whichever one it does, so a fixture added as XML today starts exercising
# JSON and binary the day those writers land, with no edit to the item.

module Corpus

using TOML
using OpenMath

const ROOT = normpath(joinpath(@__DIR__, "..", "corpus"))

# Vectors harvested from the Content Dictionaries live outside the repository, in
# gitignored refs/, because they are a derived work under a licence that asks more
# of a derived work than a test fixture should carry (see corpus_fetch.jl). They
# are picked up here when present, so a developer who has run `just corpus-fetch`
# gets several hundred extra items and CI runs on the ones we wrote ourselves.
const HARVESTED = normpath(joinpath(@__DIR__, "..", "..", "refs", "corpus-cd"))

roots() = isdir(HARVESTED) ? (ROOT, HARVESTED) : (ROOT,)

const ENCODINGS = (:xml, :json, :mathml, :binary)

const FILENAME = Dict(:xml => "object.xml", :json => "object.json",
    :mathml => "object.mml", :binary => "object.bin")

# Encodings whose reader *and* writer exist. The driver consults this rather than
# a hard-coded list, which is what let Phases 3, 7 and 4 each start exercising
# the whole corpus by flipping one line.
implemented(::Val{:xml}) = true
implemented(::Val{:json}) = true
implemented(::Val{:mathml}) = true
implemented(::Val{:binary}) = true
implemented(e::Symbol) = implemented(Val(e))

struct Item
    name::String
    dir::String
    meta::Dict{String, Any}
    sources::Dict{Symbol, String}       # encoding => file contents present on disk
    expected::Union{Nothing, String}    # object.jl, a Julia expression
end

Base.show(io::IO, i::Item) = print(io, "Corpus.Item(", i.name, ")")

tags(i::Item) = String.(get(i.meta, "tags", String[]))
skipped(i::Item, e::Symbol) = String(e) in String.(get(i.meta, "skip", String[]))
is_invalid(i::Item) = haskey(i.meta, "expect_error")
strictly_valid(i::Item) = get(i.meta, "strict", true)::Bool

function load(dir::AbstractString, root::AbstractString = ROOT)
    meta = TOML.parsefile(joinpath(dir, "meta.toml"))
    sources = Dict{Symbol, String}()
    for e in ENCODINGS
        path = joinpath(dir, FILENAME[e])
        isfile(path) && (sources[e] = read(path, String))
    end
    expected = isfile(joinpath(dir, "object.jl")) ?
               read(joinpath(dir, "object.jl"), String) : nothing
    name = relpath(dir, root)
    root == HARVESTED && (name = joinpath("harvested", name))
    return Item(replace(name, '\\' => '/'), dir, meta, sources, expected)
end

function items()
    out = Item[]
    for root in roots()
        isdir(root) || continue
        for (dir, _, files) in walkdir(root)
            "meta.toml" in files || continue
            push!(out, load(dir, root))
        end
    end
    sort!(out; by = i -> i.name)
    return out
end

# --- encoding plumbing --------------------------------------------------------

function decode(::Val{:xml}, src::AbstractString; mode = :strict)
    OpenMath.parse(src; format = :xml, mode = mode)
end
function decode(::Val{:json}, src::AbstractString; mode = :strict)
    OpenMath.parse(src; format = :json, mode = mode)
end
function decode(::Val{:mathml}, src::AbstractString; mode = :strict)
    OpenMath.parse(src; format = :mathml, mode = mode)
end
# Binary items are held as `String` like every other encoding: a Julia `String`
# is a byte sequence that happens not to be validated, so the corpus machinery —
# reading files, comparing for idempotence, hashing the manifest — needs no
# special case for an encoding that is not text.
function decode(::Val{:binary}, src::AbstractString; mode = :strict)
    OpenMath.parse(src; format = :binary, mode = mode)
end
decode(e::Symbol, src::AbstractString; mode = :strict) = decode(Val(e), src; mode = mode)

encode(::Val{:xml}, obj::OMObject) = OpenMath.xml(obj)
encode(::Val{:json}, obj::OMObject) = OpenMath.json(obj)
encode(::Val{:mathml}, obj::OMObject) = OpenMath.mathml(obj)
encode(::Val{:binary}, obj::OMObject) = String(OpenMath.binary(obj))
encode(e::Symbol, obj::OMObject) = encode(Val(e), obj)

# --- the driver ---------------------------------------------------------------

# Returns "" when the item conforms, otherwise a one-line description of the
# first thing that went wrong. Callers compare against "" so that the failure
# text lands in the assertion, which is what the verifier renders.
function check(item::Item)
    is_invalid(item) && return check_invalid(item)

    present = [e
               for e in ENCODINGS
               if haskey(item.sources, e) && implemented(e) && !skipped(item, e)]
    isempty(present) && return ""     # nothing implemented yet covers this item

    decoded = Dict{Symbol, OMObject}()
    for e in present
        try
            decoded[e] = decode(e, item.sources[e])
        catch err
            return "$(e): parsing failed: $(_brief(err))"
        end
    end

    # 1. Agreement between the encodings the item carries.
    ref = first(present)
    for e in present[2:end]
        canonicalize(decoded[e]) == canonicalize(decoded[ref]) ||
            return "$(e) and $(ref) decode to different objects"
    end

    # 1b. Derive the encodings the item does *not* carry, from one it does. This
    #     is what makes corpus growth monotone: an item added as XML starts
    #     exercising every later encoding with no edit to the item itself.
    derived = Symbol[]
    for e in ENCODINGS
        (implemented(e) && !skipped(item, e) && !haskey(decoded, e)) || continue
        src = try
            encode(e, decoded[ref])
        catch err
            return "$(e): deriving from $(ref) failed while writing: $(_brief(err))"
        end
        try
            decoded[e] = decode(e, src)
        catch err
            return "$(e): deriving from $(ref) failed while re-reading: $(_brief(err))"
        end
        canonicalize(decoded[e]) == canonicalize(decoded[ref]) ||
            return "$(e) derived from $(ref) lost information"
        push!(derived, e)
    end
    available = vcat(present, derived)

    # 2. The recorded expectation, when the item has one.
    if item.expected !== nothing
        want = try
            eval_expected(item)
        catch err
            return "object.jl did not evaluate: $(_brief(err))"
        end
        got = canonicalize(decoded[ref].object)
        canonicalize(want) == got ||
            return "expected $(sprint(show, canonicalize(want))), got $(sprint(show, got))"
    end

    # 3. Round-trip, and 4. byte-level idempotence, per encoding.
    for e in available
        once = try
            encode(e, decoded[e])
        catch err
            return "$(e): writing failed: $(_brief(err))"
        end
        back = try
            decode(e, once)
        catch err
            return "$(e): re-reading our own output failed: $(_brief(err))"
        end
        canonicalize(back) == canonicalize(decoded[e]) ||
            return "$(e): round-trip changed the object"
        twice = encode(e, back)
        twice == once || return "$(e): writing is not idempotent"
    end

    # 5. Cross-encoding agreement through the writers, which is what makes an
    #    item added in one encoding cover the others automatically.
    for a in available, b in available

        a === b && continue
        through = decode(b, encode(b, decoded[a]))
        canonicalize(through) == canonicalize(decoded[a]) ||
            return "$(a) → $(b) → object lost information"
    end

    # 6. Validation agrees with what the item declares.
    isvalid_openmath(decoded[ref].object) == strictly_valid(item) ||
        return "validate disagrees with meta.strict = $(strictly_valid(item))"

    return ""
end

function check_invalid(item::Item)
    for e in ENCODINGS
        (haskey(item.sources, e) && implemented(e) && !skipped(item, e)) || continue
        msg = check_invalid(item, e)
        isempty(msg) || return msg
    end
    return ""
end

function check_invalid(item::Item, encoding::Symbol)
    err = try
        decode(encoding, item.sources[encoding])
        nothing
    catch e
        e
    end
    if err === nothing
        # Some items are well-formed XML but not valid OpenMath objects; those
        # must be caught by `validate` instead of by the reader.
        return "accepted, but the item declares it must be rejected " *
               "($(get(item.meta, "reason", "no reason recorded")))"
    end
    err isa OpenMath.OpenMathError ||
        return "rejected with $(typeof(err)), which is outside the OpenMathError " *
               "family the API promises (REQ-SEC-001)"
    (err isa OpenMath.OpenMathParseError || err isa OpenMath.OpenMathLimitError) ||
        return "rejected with $(typeof(err)); a malformed document should raise " *
               "OpenMathParseError"
    return ""
end

function eval_expected(item::Item)
    mod = Module(:CorpusExpected)
    Base.eval(mod, :(using OpenMath))
    return Base.include_string(mod, item.expected, joinpath(item.dir, "object.jl"))
end

_brief(err) = replace(first(sprint(showerror, err), 160), r"\s*\n\s*" => " │ ")

# --- reporting ----------------------------------------------------------------

function summary()
    all = items()
    covered = count(
        i -> !is_invalid(i) &&
             any(e -> haskey(i.sources, e) && implemented(e), ENCODINGS), all)
    return (; total = length(all),
        valid = count(!is_invalid, all),
        invalid = count(is_invalid, all),
        covered = covered,
        encodings = [e for e in ENCODINGS if implemented(e)])
end

end # module
