# SPDX-License-Identifier: MIT
#
# Corpus integrity (harness spec §4.2). The corpus is the verifier's ground truth,
# so an agent that can edit it can make any test pass. Existing items are hashed;
# additions are free, modification and deletion are not.
#
#   just corpus-check            verify against the manifest
#   just corpus-check --update   rewrite the manifest (requires a justification)

using SHA

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const CORPUS = joinpath(ROOT, "test", "corpus")
const MANIFEST = joinpath(CORPUS, "MANIFEST.sha256")

const VALID_SOURCES = ["omstd20", "cd-example", "oracle-derived",
    "shrunk-counterexample", "human-authored"]

function corpus_files()
    isdir(CORPUS) || return String[]
    out = String[]
    for (dir, _, files) in walkdir(CORPUS), f in files

        f == "MANIFEST.sha256" && continue
        push!(out, relpath(joinpath(dir, f), CORPUS))
    end
    return sort(out)
end

digest(rel) = bytes2hex(sha256(read(joinpath(CORPUS, rel))))

function read_manifest()
    isfile(MANIFEST) ?
    Dict(String(strip(parts[2])) => String(parts[1])
    for parts in (split(l, "  ", limit = 2) for l in eachline(MANIFEST))
    if length(parts) == 2) : Dict{String, String}()
end

function write_manifest(files)
    mkpath(CORPUS)
    open(MANIFEST, "w") do io
        for f in files
            println(io, digest(f), "  ", f)
        end
    end
end

function main(argv)
    files = corpus_files()
    if "--update" in argv
        write_manifest(files)
        println("corpus manifest rewritten: ", length(files), " files")
        println("record the reason in the commit as `Corpus-Change: <justification>`")
        return 0
    end

    recorded = read_manifest()
    isempty(recorded) && isempty(files) &&
        (println("corpus is empty; nothing to check"); return 0)

    modified = [f for f in files if haskey(recorded, f) && recorded[f] != digest(f)]
    deleted = [f for f in keys(recorded) if !(f in files)]
    added = [f for f in files if !haskey(recorded, f)]

    for f in modified
        println("MODIFIED  ", f)
    end
    for f in sort(deleted)
        println("DELETED   ", f)
    end
    for f in added
        println("added     ", f)
    end

    if !isempty(modified) || !isempty(deleted)
        println()
        println("Existing corpus items may not be modified or deleted. If this is")
        println("deliberate, run `just corpus-check --update` and put the reason in")
        println("the commit as a `Corpus-Change:` trailer so a human reviews it.")
        return 1
    end

    println("corpus OK: ", length(files), " files, ", length(added), " new")
    return 0
end

exit(main(ARGS))
