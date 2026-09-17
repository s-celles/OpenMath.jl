# SPDX-License-Identifier: MIT
#
# Differential testing against the reference implementation (harness spec §4.7).
#
# This is the one signal in the harness that nothing on our side can influence:
# the oracle's behaviour lives in someone else's crate. A disagreement is either
# our bug or an upstream finding, and both are worth having.
#
# The comparison is *canonical*, never textual. The two implementations legally
# differ on attribute order and on where they choose to write `cdbase`; only the
# meaning has to agree.
#
#   just oracle          run the corpus through both implementations
#   just oracle --json   the same, as a machine-readable report

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const ORACLE = joinpath(ROOT, "refs", "om-oracle", "target", "release", "om-oracle")

include(joinpath(@__DIR__, "corpus.jl"))
using .Corpus
using OpenMath

struct Outcome
    item::String
    direction::Symbol  # :read (their reader) or :write (our writer)
    verdict::Symbol    # :agree, :oracle_rejected, :disagree, :we_rejected
    detail::String
end

function run_oracle(mode::AbstractString, src::AbstractString)
    out, err = IOBuffer(), IOBuffer()
    ok = try
        success(pipeline(`$ORACLE $mode`; stdin = IOBuffer(src), stdout = out, stderr = err))
    catch e
        return (false, "", "could not run the oracle: $(sprint(showerror, e))")
    end
    return (ok, String(take!(out)), strip(String(take!(err))))
end

# Two independent directions, and they check different things.
#
#   :read   the corpus document → their reader → their writer → our reader.
#           Checks that we agree on what a document *means*.
#
#   :write  the corpus document → our reader → OUR writer → their reader →
#           their writer → our reader. Checks that what we *produce* is readable
#           by an implementation that is not ours. Without this the oracle never
#           looks at our writer at all, and a writer can be perfectly
#           self-consistent while emitting something only it can read.
function compare(item::Corpus.Item, direction::Symbol)
    src = item.sources[:xml]

    ours = try
        canonicalize(OpenMath.parse(src; format = :xml))
    catch err
        return Outcome(item.name, direction, :we_rejected, Corpus._brief(err))
    end

    input = if direction === :read
        src
    else
        try
            OpenMath.xml(OpenMath.parse(src; format = :xml))
        catch err
            return Outcome(item.name, direction, :we_rejected,
                "our writer failed: $(Corpus._brief(err))")
        end
    end

    ok, out, err = run_oracle("xml", input)
    ok || return Outcome(item.name, direction, :oracle_rejected, err)

    theirs = try
        canonicalize(OpenMath.parse(out; format = :xml))
    catch err
        return Outcome(item.name, direction, :disagree,
            "we cannot read the oracle's output: $(Corpus._brief(err))")
    end

    theirs == ours && return Outcome(item.name, direction, :agree, "")
    return Outcome(item.name, direction, :disagree,
        "ours: " * first(sprint(show, ours.object), 120) *
        " │ theirs: " * first(sprint(show, theirs.object), 120))
end

function main(argv)
    isfile(ORACLE) || begin
        println("oracle not built. Run `just oracle-setup` (needs git and a Rust toolchain).")
        println("It links the GPL-3 reference crate, so it lives under refs/ and is")
        println("never part of the distributed package.")
        return 0
    end

    outcomes = Outcome[]
    for item in Corpus.items()
        Corpus.is_invalid(item) && continue
        haskey(item.sources, :xml) || continue
        for direction in (:read, :write)
            push!(outcomes, compare(item, direction))
        end
    end

    by = Dict{Symbol, Vector{Outcome}}()
    for o in outcomes
        push!(get!(by, o.verdict, Outcome[]), o)
    end

    if "--json" in argv
        print("{\"total\":", length(outcomes))
        for (k, v) in sort(collect(by); by = first)
            print(",\"", k, "\":", length(v))
        end
        println("}")
    else
        println()
        println("  differential vs. the reference implementation — ",
            length(outcomes) ÷ 2, " items × 2 directions")
        println()
        println("  ", rpad("", 17), rpad(":read", 8), ":write")
        for verdict in (:agree, :oracle_rejected, :disagree, :we_rejected)
            v = get(by, verdict, Outcome[])
            isempty(v) && continue
            r = count(o -> o.direction === :read, v)
            w = count(o -> o.direction === :write, v)
            println("  ", rpad(String(verdict), 17), rpad(r, 8), w)
        end
        println()
        println("  :read  = document → their reader → their writer → us")
        println("  :write = document → us → OUR writer → their reader → them → us")
        for verdict in (:disagree, :we_rejected)
            for o in get(by, verdict, Outcome[])
                println(
                    "\n  ✗ ", o.item, "  [", o.direction, "/", verdict, "]\n    ", o.detail)
            end
        end
        rejected = get(by, :oracle_rejected, Outcome[])
        if !isempty(rejected)
            println("\n  The oracle rejected ", length(rejected),
                " of the ", length(outcomes), " documents we handed it:")
            reasons = Dict{String, Vector{String}}()
            for o in rejected
                push!(get!(reasons, o.detail, String[]), o.item)
            end
            for (reason, items) in sort(collect(reasons); by = first)
                println("\n    ", reason)
                println("      ", join(first(items, 6), ", "),
                    length(items) > 6 ? " … (+$(length(items) - 6))" : "")
            end
            println("\n  Each distinct reason is either a document we get wrong or an")
            println("  upstream limitation for `upstream-bugs.md`. It is never nothing.")
        end
        println()
    end

    # A disagreement on meaning is a failure; an upstream limitation is a finding
    # to record, not a reason to fail the build.
    return isempty(get(by, :disagree, Outcome[])) &&
           isempty(get(by, :we_rejected, Outcome[])) ? 0 : 1
end

exit(main(ARGS))
