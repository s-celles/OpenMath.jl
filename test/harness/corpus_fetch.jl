# SPDX-License-Identifier: MIT
#
# Harvest conformance vectors from the official Content Dictionaries.
#
# Every `<OMOBJ>` inside a CD — in an `FMP` (formal mathematical property) or an
# `Example` — is a complete OpenMath document written by the people who wrote the
# standard. They are the best test vectors available anywhere: independent of
# this package, numerous, and covering constructions no hand-written corpus would
# think to include.
#
# The output is **not** committed. It lands under refs/, which is gitignored, and
# the conformance driver picks it up from there when it is present.
#
# The reason is the Content Dictionary licence. It permits redistributing a
# dictionary "freely as a verbatim copy", but these extracted fragments are not
# verbatim copies — they are pieces lifted out and reorganised, which makes them a
# derived work. A derived work must carry "a prominent reference in the work to
# the original source" and state "prominently" that it is not the original
# OpenMath document. Per-item provenance in a meta.toml is attribution, not
# prominence, so committing them would put this repository in a position it should
# not be in for the sake of a test fixture.
#
# Harvesting them locally is not redistribution, so the vectors stay available to
# anyone who wants them — they are simply fetched rather than shipped.
#
#   just corpus-fetch             the official dictionaries
#   just corpus-fetch --all       plus the experimental and contributed ones
#   just corpus-fetch --limit N   stop after N items, for a quick look

using OpenMath

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))

slugless(cd, sym, n) = isempty(sym) ? "$(cd)-$(n)" : "$(cd)#$(sym)"
const CLONE = joinpath(ROOT, "refs", "cd")
const OUT = joinpath(ROOT, "refs", "corpus-cd")
const CD_REPO = "https://github.com/OpenMath/CDs.git"

# A harvested object that our own reader rejects is recorded as a negative case
# rather than dropped: a document the standard's own dictionaries get wrong is
# worth being able to reject, and silently discarding it would hide it.
#
# Classifying by observation has an obvious failure mode, though. If the reader
# itself breaks, every vector would be reclassified as "expected to fail" and the
# conformance suite would go green on a broken parser — the exact shape of
# reward hacking the harness exists to prevent. Hence the tripwire: a few bad
# documents among hundreds is upstream, but a large fraction is us.
const MAX_REJECTED_FRACTION = 0.02

function ensure_clone()
    isdir(CLONE) && return true
    println("  cloning $CD_REPO into ", relpath(CLONE, ROOT))
    mkpath(dirname(CLONE))
    try
        run(`git clone --depth 1 --quiet $CD_REPO $CLONE`)
    catch
        println("  clone failed; is the network reachable?")
        return false
    end
    return true
end

# The CD format is XML, but the enclosing document is a `CD`, not an `OMOBJ`, so
# this scans for the embedded documents rather than parsing the whole file. The
# elements are never nested, which makes a bracket scan exact here.
function extract_objects(src::AbstractString)
    out = String[]
    pos = 1
    while true
        s = findnext("<OMOBJ", src, pos)
        s === nothing && break
        e = findnext("</OMOBJ>", src, last(s))
        e === nothing && break
        push!(out, src[first(s):last(e)])
        pos = last(e) + 1
    end
    return out
end

# What the object sits inside, so the item records where it came from.
function context_of(src::AbstractString, at::Int)
    best, kind = 0, "CD"
    for (open, name) in (("<FMP", "FMP"), ("<Example", "Example"),
        ("<CMP", "CMP"), ("<CDSignature", "CDSignature"))
        i = findprev(open, src, at)
        i === nothing && continue
        first(i) > best && ((best, kind) = (first(i), name))
    end
    return kind
end

function symbol_of(src::AbstractString, at::Int)
    i = findprev("<Name>", src, at)
    i === nothing && return ""
    j = findnext("</Name>", src, last(i))
    j === nothing && return ""
    return strip(src[(last(i) + 1):(first(j) - 1)])
end

function main(argv)
    println("\n  corpus-fetch — official Content Dictionaries\n")
    ensure_clone() || return 1

    limit = typemax(Int)
    i = findfirst(==("--limit"), argv)
    i === nothing || (limit = something(tryparse(Int, argv[i + 1]), limit))

    # Official is the normative set and the default. The experimental and
    # contributed dictionaries are valid OpenMath too and add a great deal of
    # coverage, but they carry no standing, so including them is opt-in.
    dirs = ["--all" in argv ?
            [joinpath(CLONE, "cd", "Official"), joinpath(CLONE, "cd", "experimental"),
        joinpath(CLONE, "contrib", "cd")] :
            [joinpath(CLONE, "cd", "Official")]][1]
    files = String[]
    for d in dirs
        isdir(d) || continue
        append!(files, [p for p in readdir(d; join = true) if endswith(p, ".ocd")])
    end
    sort!(files)
    isempty(files) && (println("  no .ocd files found under ", CLONE); return 1)
    println("  ", length(files), " official Content Dictionaries")

    mkpath(OUT)
    written, skipped, seen, bad = 0, 0, Set{String}(), String[]

    for path in files
        cd_name = replace(basename(path), ".ocd" => "")
        status = occursin(joinpath("cd", "Official"), path) ? "official" :
                 occursin("experimental", path) ? "experimental" : "contrib"
        src = read(path, String)
        for (n, obj) in enumerate(extract_objects(src))
            written >= limit && @goto done
            at = first(findfirst(obj, src)::UnitRange)
            kind = context_of(src, at)
            sym = symbol_of(src, at)

            # Identical objects appear in several dictionaries; keep one.
            digest = string(hash(obj); base = 16, pad = 16)[1:8]
            digest in seen && (skipped += 1; continue)
            push!(seen, digest)

            # Does our own reader accept it?
            rejected = try
                OpenMath.parse(obj; format = :xml)
                nothing
            catch err
                err isa OpenMath.OpenMathError ?
                first(replace(sprint(showerror, err), r"\s+" => " "), 160) : rethrow()
            end
            rejected === nothing || push!(bad, slugless(cd_name, sym, n))

            slug = isempty(sym) ? "$(cd_name)-$(n)" : "$(cd_name)-$(sym)-$(n)"
            slug = replace(lowercase(slug), r"[^a-z0-9]+" => "-")
            dir = joinpath(OUT, slug)
            mkpath(dir)
            write(joinpath(dir, "object.xml"), strip(obj) * "\n")
            open(joinpath(dir, "meta.toml"), "w") do io
                println(io,
                    "source = ",
                    repr("$(cd_name).ocd, $(kind)" *
                         (isempty(sym) ? "" : " for symbol $(sym)")))
                println(io, "provenance = \"cd-example\"")
                println(io, "tags = [\"cd\", ", repr(status), ", ", repr(cd_name), "]")
                println(io, "strict = true")
                if rejected === nothing
                    println(io, "skip = []")
                else
                    println(io, "expect_error = \"OpenMathError\"")
                    println(io, "reason = ", repr(rejected))
                    println(io, "skip = []")
                end
            end
            written += 1
        end
    end
    @label done

    println("  ", written, " items written to ", relpath(OUT, ROOT))
    skipped > 0 && println("  ", skipped, " duplicates skipped")

    if !isempty(bad)
        fraction = length(bad) / max(written, 1)
        println("\n  ", length(bad), " of ", written,
            " were rejected by our own reader and recorded as negative cases:")
        for b in first(bad, 6)
            println("    ", b)
        end
        length(bad) > 6 && println("    … and ", length(bad) - 6, " more")
        if fraction > MAX_REJECTED_FRACTION
            println("\n  That is ", round(100 * fraction; digits = 1), "% — above the ",
                round(100 * MAX_REJECTED_FRACTION; digits = 1), "% tripwire.")
            println("  A few bad documents among hundreds is upstream; this many is us.")
            println("  Fix the reader before trusting this harvest.\n")
            return 1
        end
    end
    open(joinpath(OUT, "NOTICE.md"), "w") do io
        println(io, """
        # Harvested Content Dictionary vectors — local only

        Extracted from <https://github.com/OpenMath/CDs> by `just corpus-fetch`.
        These are **not** the original OpenMath documents: each item holds one
        `<OMOBJ>` lifted out of a `.ocd` file and reorganised as a test fixture.
        The original dictionaries are the authority; see the `CDComment` in each
        upstream file for its licence.

        This directory is gitignored and is never redistributed. Delete it freely;
        `just corpus-fetch` rebuilds it.
        """)
    end
    println("\n  Written under refs/, which is gitignored — harvested, not shipped.")
    println("  The conformance driver picks them up automatically.\n")
    return 0
end

exit(main(ARGS))
