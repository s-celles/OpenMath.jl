# SPDX-License-Identifier: MIT
using Documenter
using OpenMath

DocMeta.setdocmeta!(OpenMath, :DocTestSetup, :(using OpenMath); recursive = true)

makedocs(;
    modules = [OpenMath],
    authors = "Sébastien Celles <s.celles@gmail.com> and contributors",
    sitename = "OpenMath.jl",
    format = Documenter.HTML(;
        canonical = "https://s-celles.github.io/OpenMath.jl",
        edit_link = "main",
        assets = String[]
    ),
    pages = [
        "Home" => "index.md",
        "Object model" => "object-model.md",
        "Encodings" => "encodings.md",
        "Validation & passes" => "passes.md",
        "Security" => "security.md",
        "Round trips" => "round-trip.md",
        "Performance" => "performance.md",
        "Conformance" => "conformance.md",
        "Compatibility" => "compat.md",
        "Design notes" => ["design/xml-backend.md", "design/json-backend.md",
            "design/binary-backend.md", "design/phrasebook.md",
            "design/mathml-appendix-f.md"],
        "API" => "api.md"
    ],
    checkdocs = :exports,
    doctest = true,
    warnonly = false
)

include("llms.jl")

deploydocs(; repo = "github.com/s-celles/OpenMath.jl", devbranch = "main")
