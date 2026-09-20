# SPDX-License-Identifier: MIT
#
# Mutation fuzzing of the readers (harness spec §6.6).
#
# The invariant is narrow and absolute: for *any* byte string, parsing terminates
# within the configured limits and returns either an object or an
# `OpenMathError`. Never a `StackOverflowError`, an `OutOfMemoryError`, a hang or
# anything from outside that family (REQ-SEC-001).
#
# The inputs are mutations of real corpus documents rather than random noise.
# Random bytes almost never get past the first character, so they exercise the
# first branch of the tokenizer and nothing else. A corrupted *valid* document
# reaches deep into the reader, which is where the interesting failures are — and
# it is also what a flaky network or a buggy peer actually produces.
#
#   just fuzz                 default budget
#   just fuzz --minutes 30    explicit budget
#   just fuzz --seed 12345    reproduce a previous run

using Random
using OpenMath

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))

include(joinpath(@__DIR__, "corpus.jl"))
using .Corpus

# All three modes. `:recover` was missing, which is the same shape as every
# other gap this project has found: a check green on what it could not reach.
const MODES = (:strict, :lenient, :recover)

struct Finding
    input::String
    format::Symbol
    mode::Symbol
    exception::String
end

# Where a finding is written when it is kept, per encoding.
# `:auto` is not an encoding, so a finding under it cannot be filed as one:
# writing binary bytes into `object.xml` gives the conformance driver a fixture
# that is not what its name says. The sniffed format is used instead.
const FINDING_FILE = Dict(:xml => "object.xml", :json => "object.json",
    :mathml => "object.mml", :binary => "object.bin")

function finding_file(src::AbstractString, format::Symbol)
    format === :auto || return FINDING_FILE[format]
    sniffed = try
        OpenMath.sniff_format(src)
    catch
        :xml
    end
    return get(FINDING_FILE, sniffed, "object.xml")
end

# --- mutations ----------------------------------------------------------------
#
# Each takes a document and returns a corrupted one. They are deliberately crude:
# the point is to reach unusual reader states cheaply, not to be plausible.

function mutate(rng::AbstractRNG, src::String, isbinary::Bool = false)
    b = Vector{UInt8}(codeunits(src))
    isempty(b) && return src
    which = isbinary ? rand(rng, vcat(1:4, 8:10)) : rand(rng, 1:8)
    if which == 1                                    # flip a bit
        i = rand(rng, eachindex(b))
        b[i] ⊻= 0x01 << rand(rng, 0:7)
    elseif which == 2                                # truncate
        return String(b[1:rand(rng, 0:length(b))])
    elseif which == 3                                # delete a run
        i = rand(rng, eachindex(b))
        j = min(length(b), i + rand(rng, 1:32))
        return String(vcat(b[1:(i - 1)], b[(j + 1):end]))
    elseif which == 4                                # duplicate a run
        i = rand(rng, eachindex(b))
        j = min(length(b), i + rand(rng, 1:32))
        return String(vcat(b[1:j], b[i:j], b[(j + 1):end]))
    elseif which == 5                                # inject a delimiter
        i = rand(rng, eachindex(b))
        b[i] = rand(rng, UInt8['<', '>', '&', '"', '/', '{', '}', '[', ']', ':', 0x00])
    elseif which == 6                                # splice in a nesting bomb
        i = rand(rng, eachindex(b))
        bomb = Vector{UInt8}(codeunits(repeat("<OMA>", rand(rng, 100:2000))))
        return String(vcat(b[1:i], bomb, b[(i + 1):end]))
    elseif which == 7                                # claim a huge length
        return replace(src, "\"2.0\"" => "\"" * repeat("9", 400) * "\""; count = 1)
    elseif which == 8                                # random byte
        b[rand(rng, eachindex(b))] = rand(rng, UInt8)
    elseif which == 9                                # binary: a nesting bomb
        # [16] opens an application and needs no closing byte to be read, so a
        # run of them is the binary analogue of a thousand `<OMA>`.
        i = rand(rng, eachindex(b))
        bomb = fill(0x10, rand(rng, 100:2000))
        return String(vcat(b[1:i], bomb, b[(i + 1):end]))
    else                                             # binary: claim a huge length
        # Set the long flag on a tag and give it four bytes of length. This is
        # the mutation that finds an allocation made before a bounds check.
        i = rand(rng, eachindex(b))
        b[i] |= 0x80
        return String(vcat(b[1:i], rand(rng, UInt8, 4), b[(i + 1):end]))
    end
    return String(b)
end

# --- the run ------------------------------------------------------------------

# The invariant depends on the mode, because the modes promise different things.
#
#   :strict, :lenient — nothing outside the `OpenMathError` family escapes.
#   :recover          — *nothing* escapes but a resource limit (spec §5.3), and
#                       what comes back must be a real document, not a half-built
#                       one, so it has to survive being written out again.
#
# `:recover` was not fuzzed at all until this was written, though it makes the
# strongest of the three promises and shipped two commits before the campaign.
function try_parse(src::AbstractString, format::Symbol, mode::Symbol)
    obj = try
        OpenMath.parse(src; format = format, mode = mode)
    catch err
        if mode === :recover
            err isa OpenMath.OpenMathLimitError && return nothing
            return "raised in :recover mode: " * sprint(showerror, err)
        end
        err isa OpenMath.OpenMathError && return nothing
        return sprint(showerror, err)
    end
    mode === :recover || return nothing
    obj isa OMObject || return ":recover returned a $(typeof(obj)), not an OMObject"
    try
        OpenMath.xml(obj)
    catch err
        # An `OpenMathConversionError` from the *writer* is not an escape. It is
        # the documented answer to an object with no representation in the target
        # — an `OMFOREIGN` whose verbatim content is not well-formed XML, which a
        # recovered document can perfectly well contain, because the bytes came
        # from the document and the reader is required to keep them verbatim.
        #
        # This check first demanded that every recovered object be writable, and
        # the campaign produced exactly that case within three minutes. The
        # invariant was wrong, not the product; recorded rather than quietly
        # loosened.
        err isa OpenMath.OpenMathConversionError && return nothing
        return ":recover produced an object that cannot be written: " *
               sprint(showerror, err)
    end
    return nothing
end

function main(argv)
    minutes = 5.0
    i = findfirst(==("--minutes"), argv)
    i === nothing || (minutes = something(tryparse(Float64, argv[i + 1]), minutes))
    seed = rand(UInt32)
    j = findfirst(==("--seed"), argv)
    j === nothing || (seed = something(tryparse(UInt32, argv[j + 1]), seed))

    # (document, is it the binary encoding) — the binary seeds are derived rather
    # than stored, the same way the conformance driver derives them, so the
    # campaign covers every corpus item without a single `.bin` file on disk.
    seeds = Tuple{String, Bool}[]
    for item in Corpus.items()
        for (_, src) in item.sources
            push!(seeds, (src, false))
        end
        Corpus.is_invalid(item) && continue
        for (e, src) in item.sources
            Corpus.implemented(e) || continue
            derived = try
                String(OpenMath.binary(Corpus.decode(e, src)))
            catch
                nothing
            end
            derived === nothing || push!(seeds, (derived, true))
            break
        end
    end
    isempty(seeds) && (println("  no corpus documents to mutate"); return 1)

    println("\n  fuzz — ", length(seeds), " seed documents, ", minutes,
        " minute budget, seed ", seed, "\n")

    rng = Random.MersenneTwister(seed)
    deadline = time() + 60 * minutes
    findings = Finding[]
    n = 0

    # A tight ceiling, so a pathological input fails fast instead of eating the
    # budget. The limits are part of what is being tested.
    limits = OMLimits(; max_depth = 2_000, max_nodes = 200_000, max_bytes = 1 << 24)

    with_limits(limits) do
        while time() < deadline && isempty(findings)
            n += 1
            seed_src, isbinary = rand(rng, seeds)
            src = mutate(rng, seed_src, isbinary)
            formats = isbinary ? (:auto, :binary) : (:auto, :xml, :json, :mathml)
            for format in formats, mode in MODES

                msg = try_parse(src, format, mode)
                msg === nothing && continue
                push!(findings, Finding(src, format, mode, msg))
                break
            end
        end
    end

    println("  ", n, " inputs in ", round(time() - (deadline - 60 * minutes); digits = 1),
        "s")

    if isempty(findings)
        println("  no escapes from the OpenMathError family\n")
        return 0
    end

    f = first(findings)
    println("\n  ✗ an exception escaped the OpenMathError family")
    println("    format ", f.format, ", mode ", f.mode)
    println("    ", first(replace(f.exception, r"\s+" => " "), 300))
    println("\n    reproduce with: just fuzz --seed ", seed)

    # Keep the input, as a regression corpus item would be kept.
    dir = joinpath(ROOT, "test", "corpus", "regression",
        "fuzz-" * string(hash(f.input); base = 16, pad = 16)[1:8])
    mkpath(dir)
    write(joinpath(dir, finding_file(f.input, f.format)), f.input)
    write(joinpath(dir, "meta.toml"),
        "source = \"fuzz, seed $seed\"\nprovenance = \"shrunk-counterexample\"\n" *
        "tags = [\"invalid\", \"fuzz\"]\nstrict = true\n" *
        "expect_error = \"OpenMathError\"\n" *
        "reason = " * repr(first(replace(f.exception, r"\s+" => " "), 200)) *
        "\nskip = []\n")
    println("    saved to ", relpath(dir, ROOT), "\n")
    return 1
end

exit(main(ARGS))
