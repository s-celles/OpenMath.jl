# SPDX-License-Identifier: MIT
#
# REQ-XML-001, REQ-XML-002, REQ-OM-003, REQ-API-004 — the conformance corpus
# driver (harness spec §6.3). Each assertion compares against `""` so that the
# description of what went wrong lands in the failure the verifier renders.

@testitem "conformance: the corpus is discoverable and well formed" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "corpus.jl"))
    items = Corpus.items()
    @test !isempty(items)

    allowed = Set(["omstd20", "cd-example", "oracle-derived",
        "shrunk-counterexample", "human-authored"])
    for i in items
        @test "$(i.name): provenance=$(get(i.meta, "provenance", "<missing>"))" ==
              "$(i.name): provenance=$(get(i.meta, "provenance", "<missing>") in allowed ?
                                       get(i.meta, "provenance", "") : "<invalid>")"
        @test "$(i.name): has source" ==
              "$(i.name): $(haskey(i.meta, "source") ? "has source" : "missing source")"
        @test "$(i.name): has an encoding" ==
              "$(i.name): $(isempty(i.sources) ? "carries no encoding" : "has an encoding")"
    end
end

@testitem "conformance: valid items" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "corpus.jl"))
    for item in Corpus.items()
        Corpus.is_invalid(item) && continue
        @test "$(item.name): ok" ==
              "$(item.name): " *
              (isempty(Corpus.check(item)) ? "ok" : Corpus.check(item))
    end
end

@testitem "conformance: invalid items are rejected" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "corpus.jl"))
    for item in Corpus.items()
        Corpus.is_invalid(item) || continue
        @test "$(item.name): ok" ==
              "$(item.name): " *
              (isempty(Corpus.check(item)) ? "ok" : Corpus.check(item))
    end
end

@testitem "conformance: every implemented encoding covers every valid item" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "corpus.jl"))
    # Coverage is carried *or derived*: the driver writes the encodings an item
    # does not have from one it does, so this stays true without editing a single
    # item when a new writer lands. That is exactly what happened when the JSON
    # writer arrived — 39 items gained JSON coverage with no new files.
    for item in Corpus.items()
        Corpus.is_invalid(item) && continue
        for e in Corpus.ENCODINGS
            Corpus.implemented(e) || continue
            Corpus.skipped(item, e) && continue
            covered = haskey(item.sources, e) ||
                      any(f -> haskey(item.sources, f) && Corpus.implemented(f),
                Corpus.ENCODINGS)
            @test "$(item.name)/$(e): covered" ==
                  "$(item.name)/$(e): $(covered ? "covered" : "no source to derive from")"
        end
    end
end

@testitem "conformance: the corpus exercises more than one encoding" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "corpus.jl"))
    s = Corpus.summary()
    @test length(s.encodings) >= 2
    @test s.covered == s.valid

    # Say where the items came from, so the total is never mysterious. The
    # downloaded Content Dictionary vectors are not in the repository — run
    # `just conformance-full` to include them.
    own = count(i -> !startswith(i.name, "harvested/"), Corpus.items())
    harvested = length(Corpus.items()) - own
    println("  corpus: ", own, " in-repository, ", harvested, " downloaded",
        harvested == 0 ? "  (run `just conformance-full` for the rest)" : "")
    @test own >= 50
end

@testitem "conformance: parsing any corpus byte string stays inside OpenMathError" tags = [:conformance] begin
    include(joinpath(@__DIR__, "..", "harness", "corpus.jl"))
    using OpenMath
    # REQ-SEC-001 over real documents and every truncation of them: a prefix of a
    # valid document is exactly the shape a network peer produces when it dies
    # halfway through.
    for item in Corpus.items()
        haskey(item.sources, :xml) || continue
        src = item.sources[:xml]
        n = ncodeunits(src)
        for cut in unique(clamp.([1, 2, 3, n ÷ 4, n ÷ 3, n ÷ 2, 2n ÷ 3, n - 1, n], 0, n))
            piece = String(@view codeunits(src)[1:cut])
            r = try
                OpenMath.parse(piece)
                :ok
            catch err
                err isa OpenMath.OpenMathError ? :openmath_error : err
            end
            @test "$(item.name)[1:$cut]: $(r === :ok || r === :openmath_error ? "ok" : r)" ==
                  "$(item.name)[1:$cut]: ok"
        end
    end
end

@testitem "conformance: streams written by a second implementation (GAP)" tags = [
    :conformance] begin
    using OpenMath

    # The one encoding this repository has no oracle for is the binary one — the
    # reference crate lists §3.2 under TODO. GAP's `openmath` package implements
    # it and ships streams it wrote itself; `just gap-vectors` downloads them into
    # gitignored refs/, so CI runs without them and a developer who has fetched
    # them gets the only external check that exists for §3.2.
    path = normpath(joinpath(@__DIR__, "..", "..", "refs", "gap-openmath", "test3.bin"))
    if !isfile(path)
        @test "gap vectors absent" == "gap vectors absent"   # run `just gap-vectors`
    else
        data = read(path)
        io = IOBuffer(data)
        objects = OMObject[]
        while !eof(io)
            push!(objects, read_binary(io))
        end
        # Ten documents concatenated in one file, which is also the shape SCSCP
        # puts on a socket: the reader must stop at each end tag (REQ-BIN-003).
        @test length(objects) == 10
        @test eof(io)

        for o in objects
            @test canonicalize(read_binary(OpenMath.binary(o))) == canonicalize(o)
            @test canonicalize(OpenMath.parse(OpenMath.xml(o); format = :xml)) ==
                  canonicalize(o)
            @test canonicalize(OpenMath.parse(OpenMath.json(o); format = :json)) ==
                  canonicalize(o)
        end

        # GAP writes the OpenMath 1 document tag [24] throughout, never [24+64].
        # That is worth asserting rather than noting: it means no shipping
        # implementation exercises the §3.2.4.2 sharing mechanism that decision D7
        # is about, and it is the reason our own reader must accept [24].
        starts = data[[1; (findall(==(0x19), data)[1:(end - 1)] .+ 1)]]
        @test unique(starts) == UInt8[0x18]
    end
end
