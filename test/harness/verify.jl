# SPDX-License-Identifier: MIT
#
# The verifier (harness spec §2). One entry point, three latency tiers, a stable
# JSON output contract. This is the agent's primary percept, so it is written as
# an interface rather than as a log: bounded output, a spec back-reference and a
# hand-written hint on every failure, and exactly one recommended next action.
#
# Usage:  julia --project=test test/harness/verify.jl [--tier fast|standard|full]
#                                                     [--json] [--focus PATTERN]

using Test
using TestItemRunner
using Dates

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))

# ---------------------------------------------------------------- arguments ---

function parse_args(argv)
    tier, json, focus = "standard", false, nothing
    i = 1
    while i <= length(argv)
        a = argv[i]
        if a == "--json"
            json = true
        elseif a == "--tier" && i < length(argv)
            tier = argv[i += 1]
        elseif startswith(a, "--tier=")
            tier = split(a, '=', limit = 2)[2]
        elseif a == "--focus" && i < length(argv)
            focus = argv[i += 1]
        elseif startswith(a, "--focus=")
            focus = split(a, '=', limit = 2)[2]
        else
            error("verify: unknown argument $(repr(a))")
        end
        i += 1
    end
    tier in ("fast", "standard", "full") ||
        error("verify: --tier must be fast, standard or full, got $(repr(tier))")
    return (; tier, json, focus)
end

# --------------------------------------------------- failure-collecting testset

struct Failure
    testitem::String
    file::String
    line::Int
    kind::Symbol            # :fail or :error
    message::String
end

const FAILURES = Failure[]

mutable struct HarnessTestSet <: Test.AbstractTestSet
    description::String
    n_pass::Int
    n_fail::Int
    n_error::Int
    n_broken::Int
end

HarnessTestSet(desc::AbstractString; kwargs...) = HarnessTestSet(String(desc), 0, 0, 0, 0)

Test.record(ts::HarnessTestSet, r::Test.Pass) = (ts.n_pass += 1; r)
Test.record(ts::HarnessTestSet, r::Test.Broken) = (ts.n_broken += 1; r)

function Test.record(ts::HarnessTestSet, r::Union{Test.Fail, Test.Error})
    k = r isa Test.Fail ? :fail : :error
    k === :fail ? (ts.n_fail += 1) : (ts.n_error += 1)
    src = r.source
    push!(FAILURES,
        Failure(ts.description,
            src === nothing ? "?" : relpath(String(src.file), ROOT),
            src === nothing ? 0 : src.line,
            k, _one_line(r)))
    return r
end

function Test.record(ts::HarnessTestSet, child::HarnessTestSet)
    ts.n_pass += child.n_pass
    ts.n_fail += child.n_fail
    ts.n_error += child.n_error
    ts.n_broken += child.n_broken
    return child
end

# Any other test set — `Supposition.@check` installs its own — is folded in
# through the standard counting interface, so a property failure is a verifier
# failure like any other rather than an unhandled `record` method.
function Test.record(ts::HarnessTestSet, child::Test.AbstractTestSet)
    c = Test.get_test_counts(child)
    ts.n_pass += c.passes + c.cumulative_passes
    ts.n_fail += c.fails + c.cumulative_fails
    ts.n_error += c.errors + c.cumulative_errors
    ts.n_broken += c.broken + c.cumulative_broken
    if c.fails + c.cumulative_fails + c.errors + c.cumulative_errors > 0
        desc = hasproperty(child, :description) ? String(child.description) :
               string(nameof(typeof(child)))
        push!(FAILURES,
            Failure(desc, "test/property/properties.jl",
                0, :fail,
                "property falsified — the shrunk counterexample is " *
                "printed above; add it to test/corpus/regression/"))
    end
    return child
end

function Test.finish(ts::HarnessTestSet)
    Test.get_testset_depth() > 0 && Test.record(Test.get_testset(), ts)
    return ts
end

# Failure text is truncated hard: a 10 000-line log destroys a context window and
# teaches nothing the first two lines did not.
function _one_line(r)
    s = try
        sprint(show, r; context = :limit => true)
    catch
        string(r)
    end
    s = replace(strip(s), r"\s*\n\s*" => " │ ")
    return length(s) > 400 ? s[1:nextind(s, 0, 400)] * " …" : s
end

# ----------------------------------------------------- spec back-references ----

# Requirement ids declared in the header comment of each test file, so a failure
# can cite the requirement it violates instead of leaving the agent to guess.
function requirements_of(file)
    path = joinpath(ROOT, file)
    isfile(path) || return String[]
    ids = String[]
    for line in Iterators.take(eachline(path), 20)
        startswith(lstrip(line), "#") || break
        for m in eachmatch(r"REQ-[A-Z]+-\d{3}", line)
            m.match in ids || push!(ids, m.match)
        end
    end
    return ids
end

# Hand-written guidance, keyed by requirement. This is the highest-leverage and
# cheapest-to-improve field in the whole harness (harness spec §2.3).
const HINTS = Dict(
    "REQ-OM-006" => "names must match the Name production of omstd20 §2.3; see src/names.jl",
    "REQ-OM-007" => "OpenMathNameError carries the 1-based index of the offending character",
    "REQ-SEC-002" => "check the depth with an explicit-stack pass before recursing; never let the native stack decide",
    "REQ-SEC-003" => "replace the recursion with an explicit Vector stack in src/traversal.jl",
    "REQ-CAN-002" => "canonicalize must be idempotent: expand, resolve, collapse, strip — resolving before collapsing is what makes the normal form independent of where cdbase was written",
    "REQ-CAN-004" => "minimize_cdbase may only emit cdbase where the effective base changes (omstd20 §2.1.4)",
    "REQ-CAN-006" => "expand_references must detect a cycle before copying: an element may not dominate itself",
    "REQ-VAL-008" => "validate reports; it must never throw, whatever the input",
    "REQ-XML-003" => "emit hex= when the value does not round-trip through decimal (NaN, Inf, subnormals)",
    "REQ-JSN-003" => "integers outside the IEEE-754 exact range must be written as a decimal string",
    "REQ-PRJ-003" => "add `# SPDX-License-Identifier: MIT` as the first line of the file",
    "REQ-OM-003" => "a round trip must preserve every field the source encoding carried; compare canonical forms to see what was dropped",
    "REQ-XML-002" => "the corpus driver names the step that failed: parse, expectation, round-trip, idempotence or cross-encoding",
    "REQ-XML-006" => "emit cdbase only where the effective base differs from the inherited one (omstd20 §2.1.4)"
)

function hint_for(reqs)
    for r in reqs
        haskey(HINTS, r) && return HINTS[r]
    end
    return "no hint recorded yet for this assertion — adding one to HINTS in " *
           "test/harness/verify.jl is the cheapest harness improvement available"
end

# ------------------------------------------------------------------- gates -----

const TIER_TAGS = Dict(
    "fast" => [:unit],
    "standard" => [:unit, :quality, :property],
    "full" => [:unit, :quality, :property, :slow]   # :conformance runs via corpus_gate
)

function run_tag_gate(tag::Symbol, focus)
    empty!(FAILURES)
    before = length(FAILURES)
    ts = nothing
    ok = true
    try
        ts = TestItemRunner.run_tests(
            joinpath(ROOT, "test");
            # A `:slow` item belongs to the `slow` gate and nowhere else, even
            # when it also carries `:unit`. Without this the `unit` gate counted
            # six items that the `slow` gate counted again, so `just test-tags
            # unit` and the verifier's unit gate reported different totals for the
            # same word. Two paths that both say "unit" and disagree on the number
            # are how you stop trusting the number.
            filter = ti -> tag in ti.tags &&
                           (tag === :slow || !(:slow in ti.tags)) &&
                           (focus === nothing || occursin(focus, ti.name)),
            testset = HarnessTestSet,
            verbose = false
        )
    catch err
        err isa Test.TestSetException || rethrow()
        ok = false
    end
    fails = copy(FAILURES[(before + 1):end])
    counts = ts isa HarnessTestSet ?
             (ts.n_pass, ts.n_fail, ts.n_error, ts.n_broken) : (0, 0, 0, 0)
    return (; ok = ok && counts[2] == 0 && counts[3] == 0,
        passed = counts[1], failed = counts[2] + counts[3],
        broken = counts[4], failures = fails)
end

# The conformance corpus runs as ordinary test items tagged :conformance. When
# the corpus is empty the gate says so rather than reporting a vacuous pass.
function corpus_gate(focus)
    dir = joinpath(ROOT, "test", "corpus")
    n = isdir(dir) ? count(fs -> "meta.toml" in fs,
        (fs for (_, _, fs) in walkdir(dir))) : 0
    n == 0 && return (; status = "not_run", reason = "no corpus items",
        passed = 0, failed = 0, failures = Failure[])
    r = run_tag_gate(:conformance, focus)
    return (; status = (r.ok ? "pass" : "fail"), reason = "$n corpus items",
        passed = r.passed, failed = r.failed, failures = r.failures)
end

# --------------------------------------------------- verifier tamper detection -

const GUARDED = ["justfile", "test/harness/", ".github/workflows/", "src/limits.jl"]

function verifier_modified()
    try
        out = readchomp(pipeline(`git -C $ROOT status --porcelain`; stderr = devnull))
        isempty(out) && return false
        for line in split(out, '\n')
            path = strip(line[min(4, length(line)):end])
            any(g -> startswith(path, g), GUARDED) && return true
        end
    catch
    end
    return false
end

function git_sha()
    try
        return readchomp(pipeline(`git -C $ROOT rev-parse --short HEAD`;
            stderr = devnull))
    catch
        return "uncommitted"
    end
end

# --------------------------------------------------------------- JSON output ---

function jstr(s)
    '"' *
    replace(string(s),
        '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n", '\r' => "\\r", '\t' => "\\t") * '"'
end
jval(x::Bool) = x ? "true" : "false"
jval(::Nothing) = "null"
jval(x::Real) = string(x)
jval(x::AbstractString) = jstr(x)
jval(x::Vector) = "[" * join(jval.(x), ",") * "]"
jval(x::Pair) = jstr(x.first) * ":" * jval(x.second)
jval(x::Vector{<:Pair}) = "{" * join(jval.(x), ",") * "}"

function failure_json(f::Failure)
    reqs = requirements_of(f.file)
    return Pair{String, Any}[
        "id" => "$(f.file):$(f.line)",
        "testitem" => f.testitem,
        "file" => f.file,
        "line" => f.line,
        "kind" => String(f.kind),
        "requirements" => Any[reqs...],
        "spec" => isempty(reqs) ? "specs/requirements.md" :
                  "specs/requirements.md#$(first(reqs))",
        "message" => f.message,
        "hint" => hint_for(reqs)
    ]
end

const MAX_RENDERED = 4

function main(argv)
    args = parse_args(argv)
    t0 = time()

    gates = Pair{String, Any}[]
    all_failures = Failure[]

    for tag in TIER_TAGS[args.tier]
        r = run_tag_gate(tag, args.focus)
        append!(all_failures, r.failures)
        push!(gates,
            String(tag) => Pair{String, Any}[
                "status" => (r.ok ? "pass" : "fail"),
                "passed" => r.passed, "failed" => r.failed, "broken" => r.broken])
    end

    c = corpus_gate(args.focus)
    append!(all_failures, c.failures)
    push!(gates,
        "conformance" => Pair{String, Any}[
            "status" => c.status, "reason" => c.reason,
            "passed" => c.passed, "failed" => c.failed])

    push!(gates,
        "docs" => Pair{String, Any}[
            "status" => args.tier == "full" ? "not_run" : "skipped",
            "reason" => "run `just docs`"])

    rendered = first(all_failures, MAX_RENDERED)
    ok = isempty(all_failures)

    report = Pair{String, Any}[
        "ok" => ok,
        "tier" => args.tier,
        "sha" => git_sha(),
        "timestamp" => string(now()),
        "duration_s" => round(time() - t0; digits = 2),
        "gates" => gates,
        "failures" => Any[failure_json(f) for f in rendered],
        "failures_truncated" => max(0, length(all_failures) - MAX_RENDERED),
        "next_actionable" => ok ? Any[] :
                             Any["$(first(all_failures).file):$(first(all_failures).line)"],
        "guardrails_fired" => Any[],
        "verifier_modified" => verifier_modified()
    ]

    json = jval(report)

    runs = joinpath(ROOT, ".agent", "runs")
    try
        mkpath(runs)
        open(joinpath(runs, "verify.jsonl"), "a") do io
            println(io, json)
        end
    catch
    end

    if args.json
        println(json)
    else
        print_human(report, rendered, length(all_failures))
    end
    return ok ? 0 : 1
end

function print_human(report, rendered, total)
    d = Dict(report)
    println()
    println("  verify — tier ", d["tier"], "  (", d["duration_s"], "s, ", d["sha"], ")")
    println()
    for (name, g) in d["gates"]
        gd = Dict(g)
        mark = gd["status"] == "pass" ? "✓" : gd["status"] == "fail" ? "✗" : "·"
        line = "  $mark $(rpad(name, 13)) $(gd["status"])"
        haskey(gd, "passed") && gd["status"] != "skipped" &&
            (line *= "   $(gd["passed"]) passed, $(gd["failed"]) failed")
        println(line)
        haskey(gd, "reason") && gd["status"] in ("not_run", "skipped") &&
            println("      ", gd["reason"])
    end
    if !isempty(rendered)
        println()
        for f in rendered
            fd = Dict(failure_json(f))
            println("  ✗ ", fd["testitem"])
            println("    ", fd["file"], ":", fd["line"],
                isempty(fd["requirements"]) ? "" :
                "  [" *
                join(fd["requirements"], ", ") * "]")
            println("    ", fd["message"])
            println("    hint: ", fd["hint"])
            println()
        end
        total > length(rendered) &&
            println("  … and ", total - length(rendered), " more failure(s)\n")
        println("  next: ", first(Dict(report)["next_actionable"]))
    end
    d["verifier_modified"] &&
        println("\n  ⚠ this working tree modifies the verifier itself")
    println()
    println(d["ok"] ? "  OK" : "  FAILED")
    println()
    return nothing
end

exit(main(ARGS))
