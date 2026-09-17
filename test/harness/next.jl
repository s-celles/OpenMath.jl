# SPDX-License-Identifier: MIT
#
# Print the first unblocked task card (harness spec §3.3). The agent never has to
# decide what to work on, which removes a class of plausible-but-wrong
# prioritisation.

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const TASKS = joinpath(ROOT, "specs", "tasks")

# Minimal YAML-ish frontmatter reader: `key: value` and `key: [a, b]` only.
function frontmatter(path)
    lines = readlines(path)
    (isempty(lines) || strip(lines[1]) != "---") && return nothing
    stop = findnext(l -> strip(l) == "---", lines, 2)
    stop === nothing && return nothing
    meta = Dict{String, Any}()
    for l in lines[2:(stop - 1)]
        m = match(r"^(\w+):\s*(.*)$", l)
        m === nothing && continue
        key, raw = m.captures[1], strip(m.captures[2])
        if startswith(raw, "[")
            items = strip.(split(strip(raw, ['[', ']']), ','))
            meta[key] = filter(!isempty, replace.(items, '"' => ""))
        else
            meta[key] = strip(raw, ['"'])
        end
    end
    meta["_body"] = join(lines[(stop + 1):end], '\n')
    meta["_path"] = relpath(path, ROOT)
    return meta
end

function main()
    isdir(TASKS) || (println("no task cards: create $(relpath(TASKS, ROOT))/NNN-slug.md");
        return 0)
    cards = filter(!isnothing, frontmatter.(sort(filter(f -> endswith(f, ".md"),
        readdir(TASKS; join = true)))))
    isempty(cards) && (println("no task cards in $(relpath(TASKS, ROOT))"); return 0)

    done = Set(String[c["id"] for c in cards if get(c, "status", "") == "done"])
    for c in cards
        get(c, "status", "todo") == "done" && continue
        deps = get(c, "depends_on", String[])
        blocked = filter(d -> !(d in done), deps)
        if isempty(blocked)
            println("\n", c["_path"], "\n")
            println("  ", get(c, "id", "?"), "  ", get(c, "title", ""))
            println("  phase      ", get(c, "phase", "?"))
            println("  verify     ", get(c, "verify", "just verify"))
            fa = get(c, "files_allowed", String[])
            isempty(fa) || println("  files      ", join(fa, ", "))
            println("\n", c["_body"])
            return 0
        end
    end
    println("every task card is either done or blocked")
    return 0
end

exit(main())
