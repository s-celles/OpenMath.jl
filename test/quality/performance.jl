# SPDX-License-Identifier: MIT
#
# The blocking half of the performance budget (roadmap Phase 8).
#
# Wall time on a shared runner varies by roughly a factor of two between runs,
# so a blocking time comparison generates false failures instead of catching
# real regressions. AirspeedVelocity reports it on a pull request and this does
# not.
#
# Allocation *counts* are deterministic within a Julia version, and this session
# showed they are also the number that matters: interning markup names cut
# allocations by a fifth and, measured as a minimum over forty runs, looked like
# +2 % time — because the minimum is, almost by definition, a run in which the
# collector did not fire. Over 200 consecutive parses it was −11.4 % wall time.
# Reading only the time column would have led to reverting it.

@testitem "performance: allocations stay within budget" tags = [:quality] begin
    using OpenMath, TOML, BenchmarkTools
    root = pkgdir(OpenMath)
    baseline = TOML.parsefile(joinpath(root, "test", "harness", "baseline.toml"))

    # Allocation counts shift between Julia minor versions for reasons that have
    # nothing to do with this package, so the budget is only meaningful on the
    # version it was recorded on. Skipping loudly rather than comparing across
    # versions: a gate that fires for the wrong reason gets switched off, and
    # then it is not a gate.
    recorded = VersionNumber(baseline["julia"])
    here = VERSION
    platform = get(baseline, "platform", nothing)
    # And the operating system, not only the Julia version. The first shape of
    # this gate guarded the version alone and failed on Windows with
    # `read-binary: 12803 allocations against 10596 recorded (+21 %)` — a
    # difference in Base, not a regression in this package. A gate that fires
    # for the wrong reason gets switched off, which is the whole argument for
    # skipping loudly instead.
    if (recorded.major, recorded.minor) != (here.major, here.minor)
        @test_skip "baseline recorded on Julia $(recorded), running $(here); " *
                   "re-record with `just bench --save`"
    elseif platform !== nothing && platform != string(Sys.KERNEL)
        @test_skip "baseline recorded on $(platform), running $(Sys.KERNEL); " *
                   "allocation counts are not comparable across platforms"
    else
        include(joinpath(root, "benchmark", "workload.jl"))
        doc = specimen(200)
        @test count_nodes(doc.object) == baseline["nodes"]

        # ±10 %, which is loose for a deterministic number and is meant to be:
        # it catches a change of shape — a copy reintroduced, a closure per node
        # — not the noise of a `Dict` resizing one bucket differently.
        budget = 1.10
        over = String[]
        for (name, write, read) in ENCODINGS
            src = write(doc)
            for (label, f, arg) in (("write-$(name)", write, doc),
                ("read-$(name)", read, src))
                haskey(baseline, label) || continue
                want = baseline[label]["allocations"]
                got = Int(minimum(@benchmark $f($arg) samples=5 evals=1).allocs)
                got <= want * budget || push!(over,
                    "$(label): $(got) allocations against $(want) recorded " *
                    "(+$(round(Int, 100 * (got - want) / want)) %)")
            end
        end
        isempty(over) || foreach(o -> println("  ", o), over)
        isempty(over) ||
            println("  if the rise is intended, `just bench --save` in the same commit")
        @test isempty(over)
    end
end
