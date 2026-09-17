# SPDX-License-Identifier: MIT
#
# The binary-encoding oracle: GAP's `openmath` package (harness spec §6.5).
#
# This is the differential test the binary encoding went without. The reference
# crate lists §3.2 under TODO, so `just oracle` says nothing about it; GAP
# implements it, and is what SCSCP deployments actually talk to.
#
# The test is symmetric and GAP chooses the values, which matters more than it
# sounds. GAP is a computer algebra system, not a document processor: handed
# `arith1#plus(1, x)` it tries to *evaluate* it and fails on the unbound
# variable. So a naive "push the corpus through it" oracle measures GAP's
# phrasebook rather than its codec. Letting GAP name the values keeps the
# comparison on the encoding, which is the part under test.
#
#   GAP writes v  →  we read it        →  compare against what GAP said v was
#   we write that →  GAP reads it back →  GAP compares with its own `=`
#
# Licence boundary, as with the Rust oracle: GAP is GPL and runs as a subprocess.
# Nothing is linked, no source is read, and everything lives in gitignored refs/.
#
#   just oracle-gap-setup     install GAP and the openmath package into refs/
#   just oracle-gap

using OpenMath

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const GAP = joinpath(ROOT, "refs", "gap-env", "bin", "gap")
const GAPROOT = joinpath(ROOT, "refs", "gap-root")

# Values GAP can name, covering the leaf kinds the encoding distinguishes and the
# sizes at which its four integer formats change over.
const VALUES = [
    "0", "1", "-1", "127", "-128", "128", "-129",
    "2147483647", "-2147483648", "2147483648", "-2147483649",
    "2^63-1", "-2^63", "2^100", "-2^100", "2^1000",
    "\"\"", "\"hello\"", "\"a<b&c\"",
    "1.5", "-1.5", "1.e-10", "1.e300",
    "[1,2,3]", "[]", "[[1,2],[3,4]]",
    "true", "false", "1/3", "-22/7"
]

# Values GAP cannot *write* in this encoding — its binary float writer raises
# "Comparison of float and 0 is not supported" before emitting anything (see
# upstream-bugs.md). It reads them perfectly well, so they are still worth
# testing: we encode them and GAP checks the result against its own value. This
# is the direction that decides whether our output is usable, so leaving floats
# out of it would hide the one thing this oracle is for.
const WE_WRITE_ONLY = [("1.5", OMFloat(1.5)), ("-1.5", OMFloat(-1.5)),
    ("1.e-10", OMFloat(1.0e-10)), ("1.e300", OMFloat(1.0e300))]

# Known upstream defects, probed rather than assumed. Each is a base-256 big
# integer, the digit bytes and what GAP returns for them today. Writing the
# expected *wrong* answers down does two things: it keeps the characterisation in
# `upstream-bugs.md` honest — it was wrong once, from a sample of four values
# that all had the same shape — and it tells us the day GAP fixes it.
#
# The rule: each digit byte is rendered as hexadecimal without being padded to
# two characters, so a byte below 0x10 contributes one digit instead of two.
const GAP_INTEGER_PROBES = [
    # digits              correct        what GAP returns today
    (UInt8[0xff, 0xff, 0xff, 0xf1], 4294967281, 4294967281),  # §3.2.2's own example
    (UInt8[0xff, 0x01, 0xff], 16712191, 1044991),
    (UInt8[0xff, 0x00, 0xff], 16711935, 1044735),
    (UInt8[0x01, 0x00], 256, 16),
    (UInt8[0x10, 0x00], 4096, 256),
    (UInt8[0x0f, 0xff], 4095, 4095)                           # dropped zero was leading
]

gap_available() = isfile(GAP) && isdir(GAPROOT)

function run_gap(script::AbstractString)
    path = tempname() * ".g"
    write(path, script)
    out = try
        read(`$GAP -l "$(GAPROOT);" -q -b $path`, String)
    catch err
        rethrow()
    finally
        rm(path; force = true)
    end
    # GAP warns about its own missing package manager on a minimal install.
    return join(filter(l -> !startswith(l, "#I"), split(out, '\n')), "\n")
end

struct Disagreement
    value::String
    direction::Symbol
    detail::String
end

function main(argv)
    if !gap_available()
        println("\n  GAP is not installed. Run `just oracle-gap-setup` first.\n")
        return 2
    end
    dir = mktempdir()
    println("\n  oracle — GAP openmath, ", length(VALUES), " values\n")

    # --- direction 1: GAP writes, we read ------------------------------------
    #
    # One GAP process per value. Batching them looked tempting and was wrong
    # twice: an uncaught error aborts the whole script, and GAP runs out of open
    # streams after about a dozen files. An opt-in oracle can afford the startups.
    findings = Disagreement[]
    ours = String[]
    objects = Union{Nothing, OMObject}[]
    for (i, v) in enumerate(VALUES)
        path = joinpath(dir, "v$(i).bin")
        run_gap("""
        LoadPackage("openmath");;
        s := OutputTextFile("$(path)", false);;
        SetPrintFormattingStatus(s, false);;
        OMPutObject(OpenMathBinaryWriter(s), $(v));;
        CloseStream(s);;
        QUIT;""")
        if !isfile(path) || filesize(path) == 0
            push!(findings, Disagreement(v, :gap_write, "GAP wrote nothing"))
            push!(ours, "")
            push!(objects, nothing)
            continue
        end
        obj = try
            read_binary(read(path))
        catch err
            push!(findings, Disagreement(v, :read, sprint(showerror, err)))
            push!(ours, "")
            push!(objects, nothing)
            continue
        end
        push!(objects, obj)
        back = joinpath(dir, "r$(i).bin")
        try
            write(back, OpenMath.binary(obj))
            push!(ours, back)
        catch err
            push!(findings, Disagreement(v, :write, sprint(showerror, err)))
            push!(ours, "")
        end
    end

    # --- direction 2: we write, GAP reads and compares with its own value ----
    agreed = 0
    for (i, v) in enumerate(VALUES)
        isempty(ours[i]) && continue
        verdict = run_gap("""
        LoadPackage("openmath");;
        s := InputTextFile("$(ours[i])");;
        o := OMGetObject(s);;
        CloseStream(s);;
        if o = $(v) then Print("AGREE\\n"); else
            Print("MISMATCH | ", String(o), "\\n"); fi;
        QUIT;""")
        if occursin("AGREE", verdict)
            agreed += 1
        else
            m = match(r"MISMATCH \| (.*)", verdict)
            push!(findings,
                Disagreement(v, :roundtrip,
                    m === nothing ? "GAP could not read our bytes" :
                    "GAP read it as " * String(m.captures[1])))
        end
    end

    # --- the same direction for values GAP cannot write ----------------------
    for (expr, node) in WE_WRITE_ONLY
        path = joinpath(dir, "w" * string(hash(expr); base = 16) * ".bin")
        write(path, OpenMath.binary(OMObject(node)))
        verdict = run_gap("""
        LoadPackage("openmath");;
        s := InputTextFile("$(path)");;
        o := OMGetObject(s);;
        CloseStream(s);;
        if o = $(expr) then Print("AGREE\\n"); else
            Print("MISMATCH | ", String(o), "\\n"); fi;
        QUIT;""")
        if occursin("AGREE", verdict)
            agreed += 1
        else
            m = match(r"MISMATCH \| (.*)", verdict)
            push!(findings,
                Disagreement(expr, :we_write_gap_reads,
                    m === nothing ? "GAP could not read our bytes" :
                    "GAP read it as " * String(m.captures[1])))
        end
    end
    total = length(VALUES) + length(WE_WRITE_ONLY)

    # --- probe the known upstream defect -------------------------------------
    fixed = 0
    for (digits, correct, known) in GAP_INTEGER_PROBES
        doc = vcat(UInt8[0x18, 0x02, UInt8(length(digits)), 0xab], digits, UInt8[0x19])
        @assert read_binary(doc).object.value == correct   # our own reading, first
        path = joinpath(dir, "probe" * bytes2hex(digits) * ".bin")
        write(path, doc)
        out = run_gap("""
        LoadPackage("openmath");;
        s := InputTextFile("$(path)");;
        Print(OMGetObject(s), "\\n");;
        CloseStream(s);;
        QUIT;""")
        got = tryparse(BigInt, strip(replace(out, r"[^0-9-]" => "")))
        if got == correct && known != correct
            fixed += 1
        elseif got != known
            push!(findings,
                Disagreement("base-256 " * bytes2hex(digits), :probe,
                    "expected GAP to return $(known), got $(got)"))
        end
    end

    # Report by direction. They are not the same question: "can GAP read what we
    # write" decides whether this package is usable on an SCSCP wire, and "can we
    # read what GAP writes" is bounded by what GAP can write at all.
    blocked = [f for f in findings if f.direction === :gap_write || f.direction === :read]
    real = [f for f in findings if !(f in blocked)]

    println("  we write → GAP reads   ", total - length(real), "/", total, " agree")
    println("  GAP writes → we read   ", length(VALUES) - length(blocked), "/",
        length(VALUES), " agree, ", length(blocked),
        " blocked by an upstream defect")
    println()
    for f in real
        println("    ✗ ", rpad(f.value, 14), f.direction, ": ",
            first(replace(f.detail, r"\s+" => " "), 120))
    end
    for f in blocked
        println("    · ", rpad(f.value, 14),
            "GAP's binary writer cannot emit this — see upstream-bugs.md")
    end
    if fixed > 0
        println("    ! ", fixed, " base-256 probe(s) now correct — the upstream ",
            "defect looks fixed; revisit decision D9 and upstream-bugs.md")
    end
    println()
    rm(dir; recursive = true, force = true)
    return isempty(real) ? 0 : 1
end

exit(main(ARGS))
