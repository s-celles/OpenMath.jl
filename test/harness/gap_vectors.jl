# SPDX-License-Identifier: MIT
#
# Binary vectors produced by a *second implementation* (harness spec §6.5).
#
# The binary encoding had no oracle: the reference crate lists §3.2 under TODO.
# GAP's `openmath` package does implement it, and ships binary streams it produced
# itself in its `tst/` directory. Those streams are the one piece of evidence that
# our reading of §3.2 is anyone else's.
#
# What is downloaded is *data* — bytes GAP wrote — not source. No GPL code is read,
# linked or copied, which keeps the clean-room boundary of `spec.md` §1.3 intact:
# the same relationship this repository already has with the Rust crate, which it
# runs as a subprocess and never reads.
#
# Nothing is committed. Everything lands in gitignored `refs/gap-openmath/`, and
# the conformance suite picks the vectors up when they are there.
#
#   just gap-vectors      download them
#   just gap-vectors-clean

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const DEST = joinpath(ROOT, "refs", "gap-openmath")

# gap-packages/openmath, GPL-2+. Package v11.5.5 (2026-08-11) is current; the
# binary encoding itself has been frozen since 2016, which for an oracle is a
# feature — these are the bytes shipping in GAP today.
const BASE = "https://raw.githubusercontent.com/gap-packages/openmath/master/tst/"
const FILES = ["test3.bin", "test3.omt", "test3.out"]

function main(argv)
    mkpath(DEST)
    println("\n  fetching binary vectors from gap-packages/openmath\n")
    for f in FILES
        dest = joinpath(DEST, f)
        try
            download(BASE * f, dest)
            println("    ", rpad(f, 14), filesize(dest), " bytes")
        catch err
            println("    ", rpad(f, 14), "failed: ", sprint(showerror, err))
            return 1
        end
    end
    println("\n  in ", relpath(DEST, ROOT), " (gitignored). `just conformance` uses them.\n")
    return 0
end

exit(main(ARGS))
