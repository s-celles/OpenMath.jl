# SPDX-License-Identifier: MIT
#
# The machine-readable conformance report (spec §6.1) and the page rendered from
# it. The report exists so the published documentation states coverage the
# harness actually measured, rather than coverage somebody typed once.

@testitem "report: it covers every corpus item, exactly once" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "report.jl"))
    r = Report.build()
    names = [i["name"] for i in r["items"]]
    @test length(names) == length(unique(names))
    @test Set(names) == Set(i.name for i in Report.corpus_items())
    @test r["totals"]["items"] == length(names)
    @test issorted(names)
end

@testitem "report: its verdict is the driver's verdict" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "report.jl"))
    # The report must not be a second opinion. It calls the same `Corpus.check`
    # the conformance suite calls, so a page that says "passing" and a suite that
    # says "failing" cannot both be true.
    r = Report.build()
    by_name = Dict(i["name"] => i for i in r["items"])
    for item in Report.corpus_items()
        entry = by_name[item.name]
        detail = Report.Corpus.check(item)
        @test "$(item.name): $(entry["status"])" ==
              "$(item.name): $(isempty(detail) ? "pass" : "fail")"
        @test entry["detail"] == detail
    end
end

@testitem "report: carried and derived are disjoint and cover the encodings" tags = [
    :conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "report.jl"))
    r = Report.build()
    all_encodings = Set(r["encodings"])
    for entry in r["items"]
        carried = Set(entry["carried"])
        derived = Set(entry["derived"])
        skipped = Set(entry["skipped"])
        @test isempty(intersect(carried, derived))
        @test isempty(intersect(carried, skipped))
        @test isempty(intersect(derived, skipped))
        # Every implemented encoding is accounted for: an item either carries it,
        # has it derived, or skips it. That is the claim the page makes, and it
        # is the one that would quietly stop being true if an encoding were added
        # to the writers and not to the driver.
        @test union(carried, derived, skipped) == all_encodings
    end

    # An item added as XML alone still covers all four — the monotone-growth
    # promise of §6.2, stated here as a fact about the report rather than prose.
    xml_only = filter(e -> e["carried"] == ["xml"] && isempty(e["skipped"]), r["items"])
    @test !isempty(xml_only)
    @test all(e -> Set(e["derived"]) == setdiff(all_encodings, Set(["xml"])), xml_only)
end

@testitem "report: the JSON it emits parses back to what it said" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "report.jl"))
    r = Report.build()
    text = Report.json(r)
    @test startswith(text, "{")
    @test endswith(strip(text), "}")
    # This package writes its own JSON everywhere else, so the report does too
    # rather than adding a dependency to the harness. It is therefore read back
    # by *our* reader, which is the only parser guaranteed to be present — and
    # which makes this a round-trip test of the emitter.
    @test Report.roundtrip(text) == r
end

@testitem "report: the published page is current" tags = [:quality] begin
    include(joinpath(@__DIR__, "..", "harness", "report.jl"))
    using OpenMath
    # A generated page committed to the repository is a page that can go stale,
    # and a stale conformance page is worse than none: it states measured
    # coverage that was not measured. So it is regenerated here and compared.
    #
    # `just conformance-report` rewrites it. The comparison is on the
    # in-repository corpus only, which is what CI can see.
    page = joinpath(pkgdir(OpenMath), "docs", "src", "conformance.md")
    @test isfile(page)
    want = Report.markdown(Report.build())
    got = read(page, String)

    # Compared by code unit, not by character index: the page contains `✅` and
    # `—`, so indexing a `String` at an arbitrary integer raises rather than
    # comparing — which is how this diagnostic first reported staleness as an
    # exception instead of a failure.
    a, b = codeunits(want), codeunits(got)
    n = findfirst(i -> a[i] != b[i], 1:min(length(a), length(b)))
    n === nothing && (n = min(length(a), length(b)) + 1)
    line = count(==(UInt8('\n')), view(a, 1:min(n, length(a)))) + 1

    # Asserted as a short string rather than `want == got`, so a stale page
    # reports its line instead of printing the whole document twice.
    @test "conformance.md is current" ==
          (want == got ? "conformance.md is current" :
           "conformance.md is stale from line $(line); run `just conformance-report`")
end
