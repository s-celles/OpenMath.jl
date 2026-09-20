# SPDX-License-Identifier: MIT
#
# The performance baseline (roadmap Phase 8).
#
# Written before any optimisation, on purpose. Phase 8's exit criterion is "no
# regression ≥ 10 % against the Phase 4 baseline", and there was no baseline —
# the number existed in the roadmap and nowhere else. A budget nobody measured
# is a wish, the same way an exit criterion that is not executable is a wish.
#
# Two things are measured, because they fail differently:
#
#   * **Throughput** — bytes per second through each reader and writer, and
#     allocations per node. This is what a large document or an SCSCP firehose
#     runs into.
#
#   * **Time to first X** — how long the *first* `parse` takes in a fresh
#     process. This is what a script that reads one document runs into, and it
#     is usually the number that decides whether a package feels slow.
#
#   just bench              measure and print
#   just bench --json       machine-readable, for the verifier
#   just bench --save       write test/corpus/BASELINE.toml

using BenchmarkTools
using OpenMath
using Printf

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
# Harness data, not corpus data: the corpus manifest forbids modifying an
# existing item, and this file is rewritten every time it is measured.
const BASELINE = joinpath(@__DIR__, "baseline.toml")

# The workload is defined once, in benchmark/workload.jl, because
# AirspeedVelocity measures the same thing on every pull request and two
# definitions of "the document we measure" would drift apart.
include(joinpath(ROOT, "benchmark", "workload.jl"))

struct Measurement
    name::String
    seconds::Float64
    bytes::Int
    allocations::Int
end

function measure(doc::OMObject)
    out = Measurement[]
    nodes = count_nodes(doc.object)
    for (name, write, read) in ENCODINGS
        src = write(doc)
        w = @benchmark $write($doc) samples=30 evals=1
        r = @benchmark $read($src) samples=30 evals=1
        push!(out,
            Measurement("write-$(name)", minimum(w).time / 1e9,
                length(codeunits(src)), Int(minimum(w).allocs)))
        push!(out,
            Measurement("read-$(name)", minimum(r).time / 1e9,
                length(codeunits(src)), Int(minimum(r).allocs)))
    end
    return out, nodes
end

# Time to first X has to be measured in a process that has never done it, so it
# is a subprocess and not a `@benchmark`.
function ttfx()
    out = Dict{String, Float64}()
    for (name, _, _) in ENCODINGS
        script = tempname() * ".jl"
        write(script, """
        t0 = time_ns()
        using OpenMath
        o = OMObject(OMS"arith1#plus"(OMInteger(1), OMVariable("x")))
        s = $(name === :binary ? "String(OpenMath.binary(o))" : "OpenMath.$(name)(o)")
        OpenMath.parse($(name === :binary ? "Vector{UInt8}(codeunits(s))" : "s");
                       format = :$(name))
        println((time_ns() - t0) / 1e9)
        """)
        try
            out[String(name)] = Base.parse(Float64,
                strip(read(
                    `$(Base.julia_cmd()) --project=$(ROOT) --startup-file=no $(script)`,
                    String)))
        finally
            rm(script; force = true)
        end
    end
    return out
end

function main(argv)
    doc = specimen(200)
    println("\n  bench — specimen of ", count_nodes(doc.object), " nodes\n")
    results, nodes = measure(doc)

    @printf("  %-16s %10s %10s %12s %10s\n",
        "", "bytes", "ms", "MiB/s", "alloc/node")
    for m in results
        @printf("  %-16s %10d %10.3f %12.1f %10.2f\n", m.name, m.bytes,
            m.seconds * 1e3, m.bytes / m.seconds / 1024^2, m.allocations / nodes)
    end

    if "--ttfx" in argv || "--save" in argv
        println("\n  time to first parse, in a fresh process\n")
        for (name, t) in sort(collect(ttfx()); by = first)
            @printf("  %-16s %10.2f s\n", name, t)
        end
    end

    if "--save" in argv
        open(BASELINE, "w") do io
            println(io, "# Performance baseline, written by `just bench --save`.")
            println(io, "# Phase 8's exit criterion compares against these numbers.")
            println(io, "#")
            println(io, "# Throughput varies by roughly a factor of two between runs on a")
            println(io, "# shared machine, so a regression budget against these has to be")
            println(io, "# generous: they catch a change of order, not of constant factor.")
            println(io, "# The time-to-first-parse figures are the stable ones.")
            println(io, "nodes = ", nodes)
            println(io, "julia = ", repr(string(VERSION)))
            # Allocation counts differ between operating systems as well as
            # between Julia versions — `read-binary` is 21 % higher on Windows
            # than on Linux, from Base and not from us — so the budget gate has
            # to know which platform produced these numbers.
            println(io, "platform = ", repr(string(Sys.KERNEL)))
            println(io, "date = ", repr(string(Dates.today())))
            for m in results
                println(io, "\n[\"", m.name, "\"]")
                println(io, "seconds = ", m.seconds)
                println(io, "bytes = ", m.bytes)
                println(io, "allocations = ", m.allocations)
            end
        end
        println("\n  saved to ", relpath(BASELINE, ROOT))
    end
    println()
    return 0
end

using Dates
exit(main(ARGS))
