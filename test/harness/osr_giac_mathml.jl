# SPDX-License-Identifier: MIT
#
# Content MathML written by Giac, for the numeric MathML oracle
# (docs/src/differential-testing.md).
#
#   just oracle-numeric-setup      # once
#   just oracle-numeric-giac       # this script
#   just oracle-numeric osr        # reads what it wrote
#
# Each OSR expression is handed to Giac in Giac's own syntax, and Giac exports it
# with `export_mathml(expr, content)`. The documents are written to
# refs/osr/giac-mathml.json, which the oracle then reads with MathML.jl and with
# this package — so the MathML under test comes from a third implementation
# rather than from a renderer written here.
#
# Giac.jl is GPL-3.0. It runs here, in a process and an environment of its own
# (refs/giac-env), and nothing of it is linked into the oracle or this package:
# the same boundary the risk register draws for the GPL-3 `openmath` crate.
#
# runs under --project=refs/giac-env, set up by `just oracle-numeric-setup`, so its
# imports are exempt from the declared-dependency gate in test/quality/project.jl.

include(joinpath(@__DIR__, "osr_corpus.jl"))
using OpenMath
using Giac: Giac
using Pkg: Pkg

# Giac reserves e, i, pi, I, D, …; the oracle prefixes every variable with `v_`.
const GIACNAME = Dict("sin" => "sin", "cos" => "cos", "tan" => "tan", "sec" => "sec",
    "csc" => "csc", "cot" => "cot", "sinh" => "sinh", "cosh" => "cosh", "tanh" => "tanh",
    "sech" => "sech", "csch" => "csch", "coth" => "coth", "arcsin" => "asin",
    "arccos" => "acos", "arctan" => "atan", "arcsinh" => "asinh", "arccosh" => "acosh",
    "arctanh" => "atanh", "arcsec" => "asec", "arccsc" => "acsc", "arccot" => "acot",
    "ln" => "ln", "exp" => "exp")

function giac_syntax(n)
    n isa OMInteger && return "($(n.value))"
    n isa OMFloat && return "($(n.value))"
    n isa OMVariable && return n.name
    (n isa OMApplication && n.applicant isa OMSymbol) || throw(OSRCorpus.Unsupported(
        string(typeof(n))))
    cd, name, a = n.applicant.cd, n.applicant.name, n.arguments
    g = giac_syntax
    if cd == "arith1"
        name == "plus" && return "(" * join(g.(a), "+") * ")"
        name == "times" && return "(" * join(g.(a), "*") * ")"
        name == "minus" && return "(" * g(a[1]) * "-" * g(a[2]) * ")"
        name == "divide" && return "(" * g(a[1]) * "/" * g(a[2]) * ")"
        name == "power" && return "(" * g(a[1]) * "^" * g(a[2]) * ")"
        name == "unary_minus" && return "(-" * g(a[1]) * ")"
        name == "abs" && return "abs(" * g(a[1]) * ")"
        name == "root" && return a[2] == OMInteger(2) ? "sqrt(" * g(a[1]) * ")" :
               "surd(" * g(a[1]) * "," * g(a[2]) * ")"
    elseif cd == "transc1" && haskey(GIACNAME, name)
        return GIACNAME[name] * "(" * g(a[1]) * ")"
    end
    throw(OSRCorpus.Unsupported("$cd#$name"))
end

# A development build keeps its version string ("giac 2.1.0") and its JLL
# version across rebuilds; only the artifact's git-tree hash tells two builds
# apart, so the record carries it.
#
# Every hash that is available goes in: the giac source commit, which the JLL's
# README records (Yggdrasil writes it there); the artifact's git-tree hash; and
# Giac.jl's revision and git-tree hash from the Manifest.
function giac_artifact()
    id = Base.PkgId(Base.UUID("cf749d6c-42f5-550d-8800-4812740c2942"), "GIAC_jll")
    haskey(Base.loaded_modules, id) || return ""
    jll = Base.loaded_modules[id]
    parts = ["GIAC_jll $(pkgversion(jll))"]
    readme = joinpath(pkgdir(jll), "README.md")
    if isfile(readme)
        m = match(r"revision: `([0-9a-f]{7,40})`", read(readme, String))
        m === nothing || push!(parts, "giac source $(m.captures[1][1:12])")
    end
    isdefined(jll, :artifact_dir) &&
        push!(parts, "artifact $(basename(jll.artifact_dir)[1:12])")
    return ", " * join(parts, ", ") * giac_jl_hash()
end

function giac_jl_hash()
    info = get(Pkg.dependencies(), Base.UUID("e4421f97-9838-4fd0-9fa5-94f11373bf78"),
        nothing)
    info === nothing && return ""
    rev = info.git_revision === nothing ? "" : " rev $(info.git_revision)"
    tree = info.tree_hash === nothing ? "" : " tree $(info.tree_hash[1:12])"
    return isempty(rev * tree) ? "" : ", Giac.jl" * rev * tree
end

function main()
    docs = Dict{String, String}()
    skipped = 0
    exprs = OSRCorpus.expressions()
    for (k, (id, obj)) in enumerate(exprs)
        # Progress on stderr, written before the call: Giac's evaluator can
        # ignore its time limit, and a hang should name the expression.
        println(stderr, k, "/", length(exprs), " ", id)
        flush(stderr)
        src = try
            giac_syntax(obj)
        catch err
            err isa OSRCorpus.Unsupported || rethrow()
            skipped += 1
            continue
        end
        # Giac returns a string object; its printed form is quoted.
        s = string(Giac.giac_eval("export_mathml($(src),content)"))
        (startswith(s, '"') && endswith(s, '"')) && (s = s[2:(end - 1)])
        docs[id] = s
    end
    # Which Giac wrote these documents, for the report: the oracle prints it.
    engine = string(Giac.giac_eval("version()"))
    docs["__giac__"] = "Giac.jl $(pkgversion(Giac)), " *
                       first(split(strip(engine, '"'), ',')) * giac_artifact()
    out = joinpath(OSRCorpus.DIR, "giac-mathml.json")
    open(out, "w") do io
        print(io, OSRCorpus.json_object(docs))
    end
    println(
        "  ", length(docs) - 1, " documents from ", docs["__giac__"], ", ", skipped,
        " skipped; written to ", relpath(out, OSRCorpus.ROOT))
    return 0
end

exit(main())
