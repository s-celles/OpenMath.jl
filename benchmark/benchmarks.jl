# SPDX-License-Identifier: MIT
#
# The suite AirspeedVelocity runs to compare a pull request against its base
# (see .github/workflows/Benchmark.yml). It is deliberately the *same* workload
# `just bench` records the baseline from — see benchmark/workload.jl.
#
# This reports; it does not gate. Wall time on a shared runner varies by roughly
# a factor of two between runs, so a blocking time comparison would be a
# generator of false failures rather than a safeguard. The blocking half of the
# budget is on **allocations**, which are deterministic within a Julia version,
# and lives in `test/quality/performance.jl` where `just verify` and CI both
# reach it. `docs/src/performance.md` states the budget.

using BenchmarkTools
using OpenMath

include(joinpath(@__DIR__, "workload.jl"))

const SUITE = BenchmarkGroup()

let doc = specimen(200)
    SUITE["read"] = BenchmarkGroup()
    SUITE["write"] = BenchmarkGroup()
    for (name, write, read) in ENCODINGS
        src = write(doc)
        SUITE["write"][String(name)] = @benchmarkable $write($doc)
        SUITE["read"][String(name)] = @benchmarkable $read($src)
    end
end

SUITE
