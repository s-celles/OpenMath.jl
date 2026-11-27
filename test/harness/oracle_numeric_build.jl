# SPDX-License-Identifier: MIT
#
# Set up `just oracle-numeric` (docs/src/differential-testing.md):
#
#   refs/mathml-env   MathML.jl and Symbolics with this package, as for
#                     `just oracle-mathml` — MathML.jl pins Symbolics exactly, so
#                     it never enters test/Project.toml
#   refs/giac-env     Giac.jl with this package, for `just oracle-numeric-giac`
#                     only. Giac.jl is GPL-3.0: it runs in that environment and
#                     that process, and is never loaded next to the oracle.
#   refs/osr          the OSR integration rules at the pinned commit, checked
#                     against their recorded digest
#
# All three are under gitignored refs/.

include(joinpath(@__DIR__, "osr_corpus.jl"))

const ROOT = OSRCorpus.ROOT

function environment(dir, packages)
    mkpath(dir)
    script = tempname() * ".jl"
    write(script, """
    using Pkg
    Pkg.develop(PackageSpec(path = raw"$(ROOT)"))
    Pkg.add($(repr(packages)))
    Pkg.precompile()
    """)
    try
        run(`$(Base.julia_cmd()) --project=$(dir) --startup-file=no $(script)`)
    finally
        rm(script; force = true)
    end
end

function main()
    println("\n  oracle-numeric-setup\n")
    environment(joinpath(ROOT, "refs", "mathml-env"), ["MathML", "Symbolics"])
    environment(joinpath(ROOT, "refs", "giac-env"), ["Giac"])
    OSRCorpus.fetch()
    println("\n  OSR rules at ", OSRCorpus.COMMIT[1:7], " in refs/osr, digest checked.")
    println("  ready. `just oracle-numeric elements`, `just oracle-numeric osr`,")
    println("  and optionally `just oracle-numeric-giac` before the second.\n")
    return 0
end

exit(main())
