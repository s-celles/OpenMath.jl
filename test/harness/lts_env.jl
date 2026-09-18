# SPDX-License-Identifier: MIT
#
# The environment `just verify-lts` runs in.
#
# It lives under gitignored refs/ rather than reusing test/, for a reason that
# cost a while to find: `Manifest.toml` is shared between Julia versions, so
# resolving the test environment on 1.13 pins versions 1.10 cannot load — the
# current `PrecompileTools` declares `julia = "1.12"` — and resolving it back on
# 1.10 would pin versions 1.13 would then re-resolve. The two would fight over
# one file.
#
# CI never sees this, because it resolves from a clean checkout where the
# manifest does not exist; it is purely an artefact of running both versions on
# one machine, which is what `verify-lts` is for.
#
# runs under --project=test but writes refs/lts-test

using Pkg
using TOML

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const ENVDIR = joinpath(ROOT, "refs", "lts-test")

function main()
    mkpath(ENVDIR)
    deps = keys(TOML.parsefile(joinpath(ROOT, "test", "Project.toml"))["deps"])
    wanted = sort!(collect(filter(!=("OpenMath"), deps)))
    Pkg.activate(ENVDIR)
    Pkg.develop(PackageSpec(path = ROOT))
    Pkg.add(wanted)
    Pkg.precompile()
    println("\n  ", relpath(ENVDIR, ROOT), " ready for `just verify-lts`\n")
    return 0
end

exit(main())
