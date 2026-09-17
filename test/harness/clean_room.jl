# SPDX-License-Identifier: MIT
#
# Clean-room gate (harness spec §4.6). This package is MIT; the Rust reference
# crate is GPL-3.0-or-later. Reading it to understand a design decision is fine;
# copying from it is not. An agent stuck on a tricky encoder has that shortcut
# within reach, so the rule is mechanical rather than a line in AGENTS.md.
#
# The reference lives in refs/, which is a *local clone*, not vendored code:
# separate git repository, gitignored, never tracked, never distributed, and not
# referenced by the package at runtime. Vendoring it would put GPL-3 sources in
# an MIT repository, which is the thing this gate exists to prevent.

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const REF = joinpath(ROOT, "refs", "rust-openmath")
# A shared verbatim run of this many tokens is a finding. Overridable so that the
# margin can be measured: `just clean-room --run 4` shows how close we actually
# are, rather than only whether we cleared the bar we set ourselves.
const DEFAULT_RUN = 6

# Text the standard itself mandates. Two implementations of OpenMath necessarily
# spell these the same way, so an identical run inside one of them is not
# copied expression.
#
# The allowance is by *literal*, not by token: a shingle passes only if it occurs
# as a contiguous run inside one of these strings. Allowing individual tokens
# would let an arbitrary sentence through as long as every word appeared
# somewhere in the standard, which is most of them.
const STANDARD_LITERALS = [
    "http://www.openmath.org/cd",
    "http://www.openmath.org/OpenMath",
    "xmlns=\"http://www.openmath.org/OpenMath\"",
    "OMOBJ OMI OMF OMSTR OMB OMV OMS OMA OMBIND OMBVAR OME OMATTR OMATP OMFOREIGN OMR",
    "<OMA><OMS cd=\"arith1\" name=\"plus\"/><OMI>1</OMI><OMV name=\"x\"/></OMA>",
    "<OMOBJ><OMA><OMS cd=\"arith1\" name=\"plus\"/><OMI>1</OMI></OMA></OMOBJ>",
    "cdbase cd name href encoding id version dec hex",
    "cdbase=\"http://www.openmath.org/cd\"",
    "cdbase http://www.openmath.org/cd CD_BASE",
    # The canonical example of the standard, in the standard's own JSON encoding
    # (§3.3). Two conforming implementations serialising arith1#plus applied to 1
    # produce byte-identical output: every member name is mandated and there is
    # no expressive choice left. Both this package and the reference carry it in
    # their doctests, for the same reason.
    """{"kind":"OMOBJ","openmath":"2.0","object":{"kind":"OMA","applicant":{"kind":"OMS","cd":"arith1","name":"plus"},"arguments":[{"kind":"OMI","integer":1},{"kind":"OMV","name":"x"}]}}""",
    """{"kind":"OMOBJ","openmath":"2.0","object":{"kind":"OMA","applicant":{"kind":"OMS","cd":"arith1","name":"plus"},"arguments":[{"kind":"OMI","integer":1}]}}""",
    """{"kind":"OMBIND","binder":{"kind":"OMS","cd":"fns1","name":"lambda"},"variables":[{"kind":"OMV","name":"x"}],"object":{"kind":"OMV","name":"x"}}""",
    """{"kind":"OME","error":{"kind":"OMS"},"arguments":[{"kind":"OMFOREIGN","foreign":"","encoding":""}]}""",
    """{"kind":"OMATTR","attributes":[[{"kind":"OMS"},{"kind":"OMSTR","string":""}]],"object":{"kind":"OMV"}}""",
    """{"kind":"OMB","base64":""} {"kind":"OMB","bytes":[]} {"kind":"OMR","href":""}""",
    """{"kind":"OMI","integer":0} {"kind":"OMI","decimal":""} {"kind":"OMI","hexadecimal":""}""",
    """{"kind":"OMF","float":0} {"kind":"OMF","decimal":""} {"kind":"OMF","hexadecimal":""}"""
]

tokens(s) = [m.match for m in eachmatch(r"[A-Za-z_][A-Za-z0-9_]*|[0-9]+", s)]

# Every contiguous token run of any length that occurs inside a standard literal.
const ALLOWED_RUNS = let set = Set{String}()
    for lit in STANDARD_LITERALS
        ts = tokens(lit)
        for i in eachindex(ts), j in i:length(ts)

            push!(set, join(@view(ts[i:j]), ' '))
        end
    end
    set
end

function shingles(path, n)
    ts = tokens(read(path, String))
    out = Dict{String, Int}()
    for i in 1:(length(ts) - n + 1)
        key = join(@view(ts[i:(i + n - 1)]), ' ')
        key in ALLOWED_RUNS && continue
        out[key] = i
    end
    return out
end

function sources(dir, exts)
    isdir(dir) || return String[]
    [joinpath(d, f) for (d, _, fs) in walkdir(dir)
     for f in fs
     if any(e -> endswith(f, e), exts)]
end

function main(argv = String[])
    run = DEFAULT_RUN
    i = findfirst(==("--run"), argv)
    i === nothing || (run = something(tryparse(Int, argv[i + 1]), DEFAULT_RUN))
    if !isdir(REF)
        println("clean-room: reference checkout absent at ", relpath(REF, ROOT), ".")
        println("It is consulted for architecture only and is not required to build.")
        println("Clone it with `just oracle-setup`. It is a separate repository,")
        println("refs/ is gitignored, and nothing under it is ever tracked or shipped.")
        return 0
    end

    ref = Dict{String, String}()
    for f in sources(REF, [".rs"])
        for (sh, _) in shingles(f, run)
            get!(ref, sh, relpath(f, ROOT))
        end
    end

    findings = Tuple{String, String, String}[]
    for f in sources(joinpath(ROOT, "src"), [".jl"])
        for (sh, _) in shingles(f, run)
            haskey(ref, sh) && push!(findings, (relpath(f, ROOT), ref[sh], sh))
        end
    end

    if isempty(findings)
        println("clean-room OK: no shared ", run, "-token run with the GPL reference ",
            "(", length(ref), " reference shingles)")
        return 0
    end
    for (ours, theirs, sh) in first(findings, 10)
        println("SHARED  ", ours, "  ↔  ", theirs)
        println("        ", sh)
    end
    length(findings) > 10 && println("… and ", length(findings) - 10, " more")
    println()
    println("This package is MIT and the reference is GPL-3.0-or-later. Derive the")
    println("implementation from the published standard, not from the reference.")
    return 1
end

exit(main(ARGS))
