# SPDX-License-Identifier: MIT
#
# The OSR corpus for the numeric MathML oracle (docs/src/differential-testing.md):
# the integration rules of OpenSymbolicRules/Integration (MIT, derived from the
# Rubi rules), published as OpenMath 2.0 JSON. Pinned to one commit, fetched into
# gitignored refs/osr, and checked against a recorded digest, so a run is
# reproducible and a silent change upstream is an error rather than a new result.
#
# Read with this package's own JSON scanner — the file is OpenMath JSON, and a
# second JSON parser would only be a second thing to trust.
#
# runs under --project=refs/mathml-env or refs/giac-env (and is included by the
# setup script); `SHA` is a standard library either way.

module OSRCorpus

using OpenMath
using SHA: sha256

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const DIR = joinpath(ROOT, "refs", "osr")
const COMMIT = "11324719adbf65a05d1bb45d3cee11c3f81b1406"
const URL = "https://raw.githubusercontent.com/OpenSymbolicRules/Integration/$(COMMIT)/v1/integration.osr.json"
const FILE = joinpath(DIR, "integration.osr.json")
const DIGEST = "21ec245ec80d1e802543c9d4124ab46a542b8f2aa65de60c15911cbd1fe98b51"

struct Unsupported <: Exception
    what::String
end

"""Download the pinned file into refs/osr, once, and check its digest."""
function fetch()
    mkpath(DIR)
    isfile(FILE) || run(`curl -fsSL -o $(FILE) $(URL)`)
    got = bytes2hex(open(sha256, FILE))
    got == DIGEST || error("$(FILE) has sha256 $(got), expected $(DIGEST); " *
          "delete it to fetch the pinned commit again")
    return FILE
end

function member(obj, name)
    (i = findfirst(p -> p.first == name, obj); i === nothing ? nothing :
                                               obj[i].second)
end

node(value) = OpenMath._build_json(value, OpenMath._JROOT)

function calls_integral(n)
    any(m -> m isa OMSymbol && m.cd in ("calculus1", "fns1"),
        collect_nodes(n))
end

# Every variable becomes `v_<name>`: Giac reads `e` and `i` as constants, and the
# truth, the renderer and Giac must all see the same names.
prefixed(n) = map_openmath(m -> m isa OMVariable ? OMVariable("v_" * m.name) : m, n)

"""
    expressions() -> Vector{Tuple{String, OMNode}}

Each rule's integrand and its replacement, `(id, object)`, skipping any that
still contains an integral or a lambda: neither reader evaluates those to a
number.
"""
function expressions()
    fetch()
    root = OpenMath.scan_json(read(FILE, String))
    out = Tuple{String, OMNode}[]
    for rule in member(root, "rules")
        id = member(rule, "id")
        pattern = node(member(rule, "pattern"))
        if pattern isa OMApplication && pattern.arguments[1] isa OMBinding
            body = pattern.arguments[1].body
            calls_integral(body) || push!(out, ("$id/integrand", prefixed(body)))
        end
        replacement = node(member(member(rule, "replacement"), "object"))
        calls_integral(replacement) ||
            push!(out, ("$id/replacement", prefixed(replacement)))
    end
    return out
end

# A flat JSON object of strings, which is all the Giac step writes and reads.
function json_object(d::Dict{String, String})
    esc(s) = replace(s, "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\t" => "\\t",
        "\r" => "\\r")
    return "{" * join(("\"$(esc(k))\":\"$(esc(v))\"" for (k, v) in sort(collect(d))), ",") *
           "}"
end

function read_object(path)
    Dict{String, String}(p.first => p.second
    for p in OpenMath.scan_json(read(path, String)))
end

end # module
