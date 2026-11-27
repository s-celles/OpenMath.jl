# SPDX-License-Identifier: MIT
#
# The numeric MathML oracle (docs/src/differential-testing.md).
#
#   just oracle-numeric-setup          # once: environments and the OSR corpus
#   just oracle-numeric elements       # 90 Content MathML elements, both readers
#   just oracle-numeric osr            # OSR rules: truth vs both readers
#   just oracle-numeric-giac           # optional: Giac writes the MathML
#
# `just oracle-mathml` compares the two readers *structurally* on 21 pairs. This
# one compares them *numerically*, which sees through the many shapes one value
# takes in Symbolics (`log(x)/log(10)` against `log10(x)`) and so can run on
# corpora nobody wrote by hand:
#
#   elements  each Content MathML element either reader has a table entry for,
#             as one non-strict document read by MathML.jl and, through Appendix
#             F and the Symbolics phrasebook, by this package. No truth: the two
#             are compared with each other.
#   osr       every integrand and antiderivative of the OSR integration rules
#             with no integral left in it. The OpenMath object is the truth; it
#             is rendered as non-strict Content MathML (below) and, if
#             `just oracle-numeric-giac` has run, by Giac — and each document is
#             read by both readers and evaluated against the truth.
#
# Values are compared at random points (seeded), with a relative tolerance of
# 1e-7. A point where the truth does not evaluate to a finite number is skipped;
# an expression with no comparable point is reported as such, never as agreeing.
#
# It reports and does not gate: a disagreement is a finding to triage, and the
# findings so far are in upstream-bugs.md and the CHANGELOG.
#
# runs under --project=refs/mathml-env, set up by `just oracle-numeric-setup`, so
# its imports are exempt from the declared-dependency gate in test/quality/project.jl.

using OpenMath, Symbolics, MathML, Random
include(joinpath(@__DIR__, "osr_corpus.jl"))

const NS = "http://www.w3.org/1998/Math/MathML"
const P = OpenMath.symbolics_phrasebook()
wrap(body) = "<math xmlns=\"$(NS)\">$(body)</math>"

# --- evaluation -----------------------------------------------------------------

# `Num <: Number`, so a symbolic expression must be unwrapped before asking
# whether it is a plain number; and Symbolics 7 does not fold constants after a
# substitution unless asked to.
function value_at(e, point)
    e isa AbstractArray && return nothing
    u = Symbolics.unwrap(e)
    u isa Number && return ComplexF64(u)
    d = Dict(v => point[Symbol(string(v))] for v in Symbolics.get_variables(e))
    v = Symbolics.value(Symbolics.substitute(e, d; fold = Val(true)))
    v isa Bool && return ComplexF64(v)
    return v isa Number ? ComplexF64(v) : nothing
end

near(a, b) = (isnan(a) && isnan(b)) || isapprox(a, b; rtol = 1e-7, atol = 1e-9)

read_mathml_jl(doc) = only(MathML.parse_str(doc))
read_openmath(doc) = interpret(P, read_mathml(doc; strict = false).object)

function attempt(f, doc)
    try
        return f(doc)
    catch err
        return err
    end
end

firstline(err) = first(first(split(sprint(showerror, err), '\n')), 100)

# --- elements: the two readers against each other --------------------------------

A(op, args...) = "<apply><$(op)/>" * join(args) * "</apply>"
ci(n) = "<ci>$(n)</ci>"
cn(v) = "<cn>$(v)</cn>"
const X, Y, PP, QQ = ci("x"), ci("y"), ci("p"), ci("q")
bvar(v, rest = "") = "<bvar>$(v)$(rest)</bvar>"

const ELEMENTS = Pair{String, String}[
    "plus" => A("plus", X, Y, cn(2)), "plus/1" => A("plus", X),
    "times" => A("times", cn(2), X, Y), "minus" => A("minus", X, Y),
    "minus/1" => A("minus", X), "divide" => A("divide", X, Y),
    "power" => A("power", X, cn(2)), "power/frac" => A("power", X, cn(0.5)),
    "root" => A("root", X), "root/degree" => A("root", "<degree>$(cn(3))</degree>", X),
    "abs" => A("abs", X), "gcd" => A("gcd", cn(12), cn(18)), "lcm" => A("lcm", cn(4), cn(6)),
    "factorial" => A("factorial", cn(5)), "quotient" => A("quotient", cn(7), cn(2)),
    "rem" => A("rem", cn(7), cn(2)), "floor" => A("floor", X), "ceiling" => A("ceiling", X),
    "round" => A("round", X), "trunc" => A("trunc", X), "max" => A("max", X, Y, cn(1)),
    "min" => A("min", X, Y), "exp" => A("exp", X), "ln" => A("ln", X), "log" => A("log", X),
    "log/logbase" => A("log", "<logbase>$(cn(2))</logbase>", X),
    "eq" => A("eq", X, Y), "neq" => A("neq", X, Y), "lt" => A("lt", X, Y),
    "leq" => A("leq", X, Y), "gt" => A("gt", X, Y), "geq" => A("geq", X, Y),
    "approx" => A("approx", X, Y), "and" => A("and", PP, QQ), "or" => A("or", PP, QQ),
    "xor" => A("xor", PP, QQ), "not" => A("not", PP), "implies" => A("implies", PP, QQ),
    "real" => A("real", X), "imaginary" => A("imaginary", X),
    "conjugate" => A("conjugate", X), "arg" => A("arg", X), "ident" => A("ident", X),
    "compose" => "<apply><apply><compose/><sin/><cos/></apply>$(X)</apply>",
    "inverse" => "<apply><apply><inverse/><sin/></apply>$(X)</apply>",
    "lambda" => "<apply><lambda>$(bvar(X))$(A("power", X, cn(2)))</lambda>$(cn(3))</apply>",
    "ci/head" => "<apply>$(ci("f"))$(X)</apply>",
    "mean" => A("mean", X, Y, cn(1)), "median" => A("median", X, Y, cn(1)),
    "mode" => A("mode", X, Y, cn(1)), "sdev" => A("sdev", X, Y, cn(1)),
    "variance" => A("variance", X, Y, cn(1)),
    "vector" => "<vector>$(X)$(Y)</vector>",
    "matrix" => "<matrix><matrixrow>$(X)$(Y)</matrixrow></matrix>",
    "list" => "<list>$(X)$(Y)</list>", "set" => "<set>$(X)$(Y)</set>",
    "pi" => "<pi/>", "exponentiale" => "<exponentiale/>", "imaginaryi" => "<imaginaryi/>",
    "infinity" => "<infinity/>", "notanumber" => "<notanumber/>", "true" => "<true/>",
    "false" => "<false/>", "eulergamma" => "<eulergamma/>", "emptyset" => "<emptyset/>",
    "cn/integer" => cn(2), "cn/real" => cn(2.5), "cn/negative" => cn(-3),
    "cn/rational" => "<cn type=\"rational\">1<sep/>3</cn>",
    "cn/e-notation" => "<cn type=\"e-notation\">2<sep/>3</cn>",
    "cn/base" => "<cn type=\"integer\" base=\"16\">FF</cn>",
    "cn/complex" => "<cn type=\"complex-cartesian\">1<sep/>2</cn>",
    "diff" => A("diff", bvar(X), A("power", X, cn(3))),
    "diff/degree" => A("diff", bvar(X, "<degree>$(cn(2))</degree>"), A("power", X, cn(4))),
    "partialdiff" => A("partialdiff", bvar(X), A("times", X, Y)),
    "int" => A("int", bvar(X), "<lowlimit>$(cn(0))</lowlimit><uplimit>$(cn(1))</uplimit>",
        A("power", X, cn(2))),
    "sum" => A("sum", bvar(X), "<lowlimit>$(cn(1))</lowlimit><uplimit>$(cn(3))</uplimit>", X),
    "limit" => A("limit", bvar(X), "<lowlimit>$(cn(0))</lowlimit>", A("sin", X)),
    "piecewise" => "<piecewise><piece>$(X)$(A("lt", X, cn(1)))</piece>" * "<otherwise>$(Y)</otherwise></piecewise>",
    "forall" => A("forall", bvar(X), A("eq", X, X)),
    "csymbol" => "<apply><csymbol cd=\"transc1\">sin</csymbol>$(X)</apply>"
]
for f in ("sin", "cos", "tan", "sec", "csc", "cot", "sinh", "cosh", "tanh", "sech", "csch",
    "coth", "arcsin", "arccos", "arctan", "arcsec", "arccsc", "arccot", "arcsinh",
    "arccosh", "arctanh", "arcsech", "arccsch", "arccoth")
    # Arguments inside every function's real domain at the sampled points.
    arg = f in ("arcsec", "arccsc", "arccosh", "arccoth") ? Y : X
    push!(ELEMENTS, f => A(f, arg))
end

const ELEMENT_POINTS = [
    Dict(:x => 0.7, :y => 1.3, :p => true, :q => false),
    Dict(:x => 0.2, :y => 2.6, :p => false, :q => true),
    Dict(:x => 0.9, :y => 1.1, :p => true, :q => true)
]

function compare_elements()
    rows = Pair{String, String}[]
    for (name, body) in ELEMENTS
        doc = wrap(body)
        a, b = attempt(read_mathml_jl, doc), attempt(read_openmath, doc)
        verdict = if a isa Exception && b isa Exception
            "both refuse"
        elseif a isa Exception
            "only OpenMath.jl reads it (MathML.jl: $(firstline(a)))"
        elseif b isa Exception
            "only MathML.jl reads it (OpenMath.jl: $(firstline(b)))"
        else
            va = [attempt(_ -> value_at(a, p), nothing) for p in ELEMENT_POINTS]
            vb = [attempt(_ -> value_at(b, p), nothing) for p in ELEMENT_POINTS]
            if any(v -> v === nothing || v isa Exception, [va; vb])
                (a isa AbstractArray) != (b isa AbstractArray) ?
                "different kinds: $(typeof(a)) and $(typeof(b))" : "not comparable"
            else
                all(near.(va, vb)) ? "agree" : "DIFFERENT values"
            end
        end
        push!(rows, name => verdict)
    end
    return rows
end

# --- osr: truth against both readers ------------------------------------------------

# OpenMath -> non-strict Content MathML (MathML 2 built-in elements). `<root>`
# always carries its `<degree>`, which is valid and which Giac never writes.
const ELEMENT_OF = Dict(("arith1", "plus") => "plus", ("arith1", "times") => "times",
    ("arith1", "minus") => "minus", ("arith1", "divide") => "divide",
    ("arith1", "power") => "power", ("arith1", "unary_minus") => "minus",
    ("arith1", "abs") => "abs", ("transc1", "ln") => "ln", ("transc1", "exp") => "exp")
for f in ("sin", "cos", "tan", "sec", "csc", "cot", "sinh", "cosh", "tanh", "sech", "csch",
    "coth", "arcsin", "arccos", "arctan", "arcsec", "arccsc", "arccot", "arcsinh",
    "arccosh", "arctanh", "arcsech", "arccsch", "arccoth")
    ELEMENT_OF[("transc1", f)] = f
end

function render(n)
    n isa OMInteger && return cn(n.value)
    n isa OMFloat && return cn(n.value)
    n isa OMVariable && return ci(n.name)
    (n isa OMApplication && n.applicant isa OMSymbol) ||
        throw(OSRCorpus.Unsupported(string(typeof(n))))
    key = (n.applicant.cd, n.applicant.name)
    if key == ("arith1", "root") && length(n.arguments) == 2
        return "<apply><root/><degree>$(render(n.arguments[2]))</degree>" *
               "$(render(n.arguments[1]))</apply>"
    end
    haskey(ELEMENT_OF, key) || throw(OSRCorpus.Unsupported(join(key, "#")))
    return "<apply><$(ELEMENT_OF[key])/>" * join(render.(n.arguments)) * "</apply>"
end

function verdict(reader, doc, truth_at, points)
    got = attempt(reader, doc)
    got isa Exception && return "refused: " * firstline(got)
    for (p, t) in zip(points, truth_at)
        v = attempt(_ -> value_at(got, p), nothing)
        (v === nothing || v isa Exception) && return "does not evaluate"
        near(t, v) || return "WRONG value"
    end
    return "right"
end

function compare_osr(; npoints = 3, seed = 1)
    rng = MersenneTwister(seed)
    giacfile = joinpath(OSRCorpus.DIR, "giac-mathml.json")
    giac = isfile(giacfile) ? OSRCorpus.read_object(giacfile) : nothing
    tally = Dict{Tuple{String, String, String}, Vector{String}}()
    note(src, reader, v, id) = push!(get!(tally, (src, reader, v), String[]), id)
    for (id, obj) in OSRCorpus.expressions()
        truth = attempt(o -> interpret(P, o), obj)
        truth isa Exception && continue
        names = sort(unique(Symbol.(string.(Symbolics.get_variables(truth)))))
        points, truth_at = Dict{Symbol, Float64}[], ComplexF64[]
        for _ in 1:npoints
            p = Dict(k => 0.3 + 1.4 * rand(rng) for k in names)
            t = attempt(_ -> value_at(truth, p), nothing)
            (t isa ComplexF64 && isfinite(t)) || continue
            push!(points, p)
            push!(truth_at, t)
        end
        isempty(points) && (note("-", "-", "no comparable point", id); continue)
        docs = Pair{String, String}[]
        rendered = attempt(render, obj)
        rendered isa Exception || push!(docs, "rendered" => wrap(rendered))
        giac !== nothing && haskey(giac, id) && push!(docs, "Giac" => giac[id])
        for (src, doc) in docs
            note(src, "MathML.jl", verdict(read_mathml_jl, doc, truth_at, points), id)
            note(src, "OpenMath.jl", verdict(read_openmath, doc, truth_at, points), id)
        end
    end
    return tally, giac !== nothing
end

# --- report ---------------------------------------------------------------------

function versions()
    return "MathML.jl $(pkgversion(MathML)), OpenMath.jl $(pkgversion(OpenMath)), " *
           "Symbolics $(pkgversion(Symbolics)), Julia $(VERSION)"
end

function main(argv)
    mode = isempty(argv) ? "elements" : argv[1]
    println("\n  oracle — numeric, ", mode, "\n  ", versions(), "\n")
    if mode == "elements"
        rows = compare_elements()
        counts = Dict{String, Int}()
        for (_, v) in rows
            key = startswith(v, "only") ? first(split(v, " (")) : v
            counts[key] = get(counts, key, 0) + 1
        end
        for (k, n) in sort(collect(counts); by = first)
            println("  ", rpad(k, 40), n)
        end
        println()
        for (name, v) in rows
            v == "agree" || println("    ", rpad(name, 16), v)
        end
    elseif mode == "osr"
        println("  OSR integration rules at ", OSRCorpus.COMMIT[1:7],
            ", sha256 ", OSRCorpus.DIGEST[1:12], "…\n")
        tally, withgiac = compare_osr()
        withgiac || println("  (no Giac documents: run `just oracle-numeric-giac`)\n")
        for k in sort(collect(keys(tally)))
            println("  ", rpad(join(k, " | "), 100), length(tally[k]))
        end
        println()
        for (k, ids) in sort(collect(tally); by = first)
            (occursin("WRONG", k[3]) || startswith(k[3], "refused")) || continue
            println("    ", join(k, " | "), ": e.g. ", first(ids))
        end
    else
        println("  unknown mode $(repr(mode)); use `elements` or `osr`")
        return 2
    end
    println()
    return 0
end

exit(main(ARGS))
