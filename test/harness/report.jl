# SPDX-License-Identifier: MIT
#
# The machine-readable conformance report (spec §6.1), and the documentation
# page rendered from it.
#
# The point is that the published coverage claim is *measured*. A hand-written
# "supports all four encodings" is a sentence someone believed once; this states
# what the driver did on this commit, per item and per encoding, and the page is
# gated against going stale (`test/conformance/report.jl`).
#
# It deliberately calls `Corpus.check` — the same function the conformance suite
# calls — rather than re-deriving a verdict. A report that could disagree with
# the suite would be a second opinion, and two opinions is none.

module Report

using OpenMath

include("corpus.jl")

# The harvested Content Dictionary vectors live in gitignored `refs/` and are
# absent from a clean checkout, so including them would make the page depend on
# whether the reader had run `just corpus-fetch`. The page says how many there
# are and reports on the corpus that ships.
corpus_items() = filter(i -> !startswith(i.name, "harvested/"), Corpus.items())

harvested_count() = count(i -> startswith(i.name, "harvested/"), Corpus.items())

const ENCODINGS = sort(collect(String.(Corpus.ENCODINGS)))

_group(name::AbstractString) = String(first(split(name, '/')))

function _entry(item::Corpus.Item)
    carried = String[]
    derived = String[]
    skipped = String[]
    for e in Corpus.ENCODINGS
        name = String(e)
        if !Corpus.implemented(e)
            continue
        elseif Corpus.skipped(item, e)
            push!(skipped, name)
        elseif haskey(item.sources, e)
            push!(carried, name)
        else
            push!(derived, name)
        end
    end
    detail = Corpus.check(item)
    return Dict{String, Any}(
        "name" => item.name,
        "group" => _group(item.name),
        "kind" => Corpus.is_invalid(item) ? "invalid" : "valid",
        "status" => isempty(detail) ? "pass" : "fail",
        "detail" => detail,
        "strict" => Corpus.strictly_valid(item),
        "provenance" => String(get(item.meta, "provenance", "")),
        "source" => String(get(item.meta, "source", "")),
        "tags" => sort(Corpus.tags(item)),
        "carried" => sort(carried),
        "derived" => sort(derived),
        "skipped" => sort(skipped))
end

"""
    Report.build() -> Dict

The conformance report for the in-repository corpus: one entry per item, plus
the totals the documentation page is rendered from.

No timestamp and no host detail, so two runs on one commit produce the same
report byte for byte — which is what lets the page be gated rather than trusted.
"""
function build()
    entries = [_entry(i) for i in corpus_items()]
    sort!(entries; by = e -> e["name"])

    counts = Dict{String, Any}()
    for field in ("carried", "derived", "skipped")
        counts[field] = Dict{String, Any}(
            e => count(x -> e in x[field], entries) for e in ENCODINGS)
    end
    totals = Dict{String, Any}(
        "items" => length(entries),
        "passing" => count(e -> e["status"] == "pass", entries),
        "valid" => count(e -> e["kind"] == "valid", entries),
        "invalid" => count(e -> e["kind"] == "invalid", entries),
        "harvested_excluded" => harvested_count())
    merge!(totals, counts)

    return Dict{String, Any}(
        "package" => "OpenMath.jl",
        "version" => string(pkgversion(OpenMath)),
        "standard" => "OpenMath 2.0 (omstd20 rev. 3, 2019-07-01)",
        "encodings" => ENCODINGS,
        "totals" => totals,
        "items" => entries)
end

# --- JSON ---------------------------------------------------------------------
#
# Written here rather than pulled in, for the same reason the package writes its
# own: a harness that needs a dependency to report on a package with none has
# the wrong shape. It is read back by `OpenMath.scan_json`, so the emitter is
# checked by the only JSON reader guaranteed to be present.

function _jstring(io::IO, s::AbstractString)
    print(io, '"')
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        elseif c == '\t'
            print(io, "\\t")
        elseif c < ' '
            print(io, "\\u", lpad(string(UInt32(c); base = 16), 4, '0'))
        else
            print(io, c)
        end
    end
    print(io, '"')
    return nothing
end

_jvalue(io::IO, v::AbstractString, _) = _jstring(io, v)
_jvalue(io::IO, v::Bool, _) = print(io, v ? "true" : "false")
_jvalue(io::IO, v::Integer, _) = print(io, v)

function _jvalue(io::IO, v::AbstractVector, indent::Int)
    isempty(v) && return print(io, "[]")
    pad = "  "^(indent + 1)
    println(io, '[')
    for (n, x) in enumerate(v)
        print(io, pad)
        _jvalue(io, x, indent + 1)
        println(io, n == length(v) ? "" : ",")
    end
    print(io, "  "^indent, ']')
    return nothing
end

function _jvalue(io::IO, v::AbstractDict, indent::Int)
    isempty(v) && return print(io, "{}")
    pad = "  "^(indent + 1)
    println(io, '{')
    keys_sorted = sort(collect(keys(v)))
    for (n, k) in enumerate(keys_sorted)
        print(io, pad)
        _jstring(io, k)
        print(io, ": ")
        _jvalue(io, v[k], indent + 1)
        println(io, n == length(keys_sorted) ? "" : ",")
    end
    print(io, "  "^indent, '}')
    return nothing
end

"""
    Report.json(report) -> String

The report as JSON, with members in sorted order so the output is stable.
"""
function json(report)
    io = IOBuffer()
    _jvalue(io, report, 0)
    println(io)
    return String(take!(io))
end

# `scan_json` gives objects as ordered `Pair` vectors and numbers as text, which
# is right for a reader that reports positions and wrong for comparing against
# what we emitted. This puts it back into the shape `build` produces.
_plain(v::OpenMath.JSONNumber) = v.isintegral ? parse(Int, v.text) : parse(Float64, v.text)
_plain(v::Vector{Pair{String, Any}}) = Dict{String, Any}(k => _plain(x) for (k, x) in v)
_plain(v::Vector{Any}) = isempty(v) ? Any[] : [_plain(x) for x in v]
_plain(v) = v

"""
    Report.roundtrip(text) -> Dict

Parse a report back out of its JSON with the package's own reader.
"""
roundtrip(text::AbstractString) = _plain(OpenMath.scan_json(text))

# --- the documentation page ---------------------------------------------------

_pct(n, d) = d == 0 ? "—" : string(round(Int, 100 * n / d), " %")

function _encoding_rows(r)
    total = r["totals"]["items"]
    rows = String[]
    for e in r["encodings"]
        carried = r["totals"]["carried"][e]
        derived = r["totals"]["derived"][e]
        skipped = r["totals"]["skipped"][e]
        covered = carried + derived
        push!(rows,
            string("| `", e, "` | ", carried, " | ", derived, " | ",
                skipped, " | **", covered, "** | ", _pct(covered, total), " |"))
    end
    return rows
end

function _group_rows(r)
    groups = sort(unique(e["group"] for e in r["items"]))
    rows = String[]
    for g in groups
        entries = filter(e -> e["group"] == g, r["items"])
        passing = count(e -> e["status"] == "pass", entries)
        invalid = count(e -> e["kind"] == "invalid", entries)
        push!(rows,
            string("| `", g, "/` | ", length(entries), " | ", invalid,
                " | ", passing, " | ", passing == length(entries) ? "✅" : "❌", " |"))
    end
    return rows
end

"""
    Report.markdown(report) -> String

The `docs/src/conformance.md` page, rendered from a report.
"""
function markdown(r)
    total = r["totals"]["items"]
    passing = r["totals"]["passing"]
    io = IOBuffer()

    println(io, """
    ```@meta
    EditURL = "https://github.com/s-celles/OpenMath.jl/blob/main/test/harness/report.jl"
    ```

    # Conformance

    !!! note "This page is generated"
        Every number below is produced by the conformance driver
        (`test/harness/corpus.jl`) from the corpus in this repository, rendered by
        `test/harness/report.jl`, and regenerated with `just conformance-report`.
        A test asserts the page matches a fresh run, so it cannot drift from what
        the harness measures. Nothing here is typed by hand.

    OpenMath.jl implements $(r["standard"]). The standard endorses **four**
    encodings, and this package implements all four: an XML encoding (§3.1), a
    binary encoding (§3.2), a JSON encoding (§3.3) and Strict Content MathML
    (MathML 4 §4.1.3).

    ## Corpus

    **$(passing) of $(total)** corpus items conform.

    Each item is a directory carrying at least one encoding of one object. The
    driver decodes what the item carries, **derives every encoding it does not**
    from one it does, and requires all of them to agree — so an item added as XML
    alone exercises the other three the day their writers land, with no edit to
    the item.

    | Group | Items | Negative | Passing | |
    |:--|--:|--:|--:|:--|""")
    foreach(row -> println(io, row), _group_rows(r))

    println(io, """

    ## Coverage per encoding

    *Carried* is an encoding the item holds on disk; *derived* is one the driver
    writes and reads back. Both are checked; the distinction is which one the
    corpus had to store.

    | Encoding | Carried | Derived | Skipped | Covered | |
    |:--|--:|--:|--:|--:|--:|""")
    foreach(row -> println(io, row), _encoding_rows(r))

    failures = filter(e -> e["status"] == "fail", r["items"])
    println(io, """

    ## Failures
    """)
    if isempty(failures)
        println(io, "None. Every item above conforms on this commit.")
    else
        println(io, "| Item | What went wrong |\n|:--|:--|")
        for e in failures
            println(io, "| `", e["name"], "` | ", e["detail"], " |")
        end
    end

    println(io, """

    ## What is not counted here

    $(r["totals"]["harvested_excluded"]) further items are harvested from the
    official Content Dictionaries by `just corpus-fetch`. They are a derived work
    under a licence that asks more of a derived work than a test fixture should
    carry, so they live outside the repository and are **excluded from this
    page**: it reports on what a clean checkout can verify. `just
    conformance-full` runs them too.

    The report behind this page is also available as JSON — `just
    conformance-report` writes it to `refs/conformance.json` — for anyone who
    would rather consume the numbers than read them.""")

    return String(take!(io))
end

end # module
