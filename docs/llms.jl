# SPDX-License-Identifier: MIT
#
# Emit llms.txt and llms-full.txt into the *built site*, per the llmstxt.org
# convention. They belong in the documentation output, not at the repository root.

const _BUILD = joinpath(@__DIR__, "build")
const _SRC = joinpath(@__DIR__, "src")

const _PAGES = ["index.md", "object-model.md", "passes.md", "security.md",
    "design/xml-backend.md", "design/json-backend.md",
    "api.md"]

function _write_llms()
    isdir(_BUILD) || return nothing
    base = "https://s-celles.github.io/OpenMath.jl"

    open(joinpath(_BUILD, "llms.txt"), "w") do io
        println(io, "# OpenMath.jl\n")
        println(io, "> A Julia implementation of the OpenMath 2.0 standard: an object")
        println(io, "> model for the semantics of mathematical objects, and readers and")
        println(io, "> writers for the official encodings.\n")
        println(io, "## Documentation\n")
        for p in _PAGES
            title = _first_heading(joinpath(_SRC, p))
            slug = p == "index.md" ? "" : replace(p, ".md" => "/")
            println(io, "- [", title, "](", base, "/", slug, ")")
        end
        println(io, "\n## Source\n")
        println(io, "- [Repository](https://github.com/s-celles/OpenMath.jl)")
        println(io,
            "- [Requirements (EARS/MoSCoW)](https://github.com/s-celles/OpenMath.jl/blob/main/specs/requirements.md)")
        println(io, "- [Roadmap](https://github.com/s-celles/OpenMath.jl/blob/main/ROADMAP.md)")
    end

    open(joinpath(_BUILD, "llms-full.txt"), "w") do io
        println(io, "# OpenMath.jl — full documentation\n")
        for p in _PAGES
            path = joinpath(_SRC, p)
            isfile(path) || continue
            println(io, "\n\n<!-- ", p, " -->\n")
            println(io, read(path, String))
        end
    end
    return nothing
end

function _first_heading(path)
    isfile(path) || return basename(path)
    for line in eachline(path)
        startswith(line, "# ") && return strip(line[3:end])
    end
    return basename(path)
end

_write_llms()
