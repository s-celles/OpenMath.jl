# SPDX-License-Identifier: MIT
#
# Build the environment for `just oracle-mathml`.
#
# MathML.jl goes in an environment of its own, under gitignored refs/, rather
# than into test/Project.toml. The reason is in docs/src/design/phrasebook.md: it
# pins `Symbolics = "7.39.2"` — an exact version, not a range — so a test
# dependency on it would pin this package's whole test environment to one
# Symbolics patch release.
#
# The two resolve to the same Symbolics version today, so the cost of getting
# this wrong would currently be zero. The objection is to the lock, not to the
# number: once MathML.jl is a test dependency, this package cannot move past
# 7.39.2 until MathML.jl does.

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const ENVDIR = joinpath(ROOT, "refs", "mathml-env")

function main()
    println("\n  oracle-mathml-setup\n")
    mkpath(ENVDIR)
    script = tempname() * ".jl"
    write(script, """
    using Pkg
    Pkg.develop(PackageSpec(path = raw"$(ROOT)"))
    Pkg.add(["MathML", "Symbolics"])
    Pkg.precompile()
    """)
    try
        run(`$(Base.julia_cmd()) --project=$(ENVDIR) --startup-file=no $(script)`)
    finally
        rm(script; force = true)
    end
    println("\n  ready. `just oracle-mathml`\n")
    return 0
end

exit(main())
