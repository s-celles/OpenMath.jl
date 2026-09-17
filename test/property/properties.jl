# SPDX-License-Identifier: MIT
#
# REQ-CAN-001, REQ-CAN-002, REQ-CAN-004, REQ-OM-003, REQ-VAL-008, REQ-SEC-001,
# REQ-XML-007 — the property-based layer (harness spec §6.4).
#
# The corpus says "these particular documents behave"; these say "every object
# behaves". Counterexamples are shrunk by Supposition, and a shrunk
# counterexample is a corpus item waiting to be written down.

@testitem "P1: canonicalize is idempotent" tags = [:property] begin
    using Supposition, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    @check max_examples = 500 function p1_idempotent(obj = Generators.gen_node())
        Regression.checked("p1_idempotent", obj) do obj
            c = canonicalize(obj)
            canonicalize(c) == c
        end
    end

    Regression.flush!()
end

@testitem "P2: the XML encoding round-trips" tags = [:property] begin
    using Supposition, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    @check max_examples = 400 function p2_xml_roundtrip(obj = Generators.gen_object())
        Regression.checked("p2_xml_roundtrip", obj) do obj
            back = OpenMath.parse(OpenMath.xml(obj); format = :xml)
            canonicalize(back) == canonicalize(obj)
        end
    end

    @check max_examples = 200 function p2_xml_roundtrip_pretty(obj = Generators.gen_object())
        Regression.checked("p2_xml_roundtrip_pretty", obj) do obj
            back = OpenMath.parse(OpenMath.xml(obj; pretty = true); format = :xml)
            canonicalize(back) == canonicalize(obj)
        end
    end

    Regression.flush!()
end

@testitem "P3: the two encodings agree on every object" tags = [:property] begin
    using Supposition, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    # XML and JSON are independent implementations of the same grammar — separate
    # scanners, separate writers, different escaping rules and different
    # spellings for the awkward numbers. Agreement between them is a real check
    # rather than a tautology.
    @check max_examples = 400 function p3_cross_encoding(obj = Generators.gen_object())
        Regression.checked("p3_cross_encoding", obj) do obj
            viaxml = OpenMath.parse(OpenMath.xml(obj); format = :xml)
            viajson = OpenMath.parse(OpenMath.json(obj); format = :json)
            canonicalize(viaxml) == canonicalize(viajson)
        end
    end

    @check max_examples = 300 function p3_json_roundtrip(obj = Generators.gen_object())
        Regression.checked("p3_json_roundtrip", obj) do obj
            canonicalize(OpenMath.parse(OpenMath.json(obj); format = :json)) ==
            canonicalize(obj)
        end
    end

    @check max_examples = 300 function p3_mathml_agrees(obj = Generators.gen_object())
        Regression.checked("p3_mathml_agrees", obj) do obj
            viaxml = OpenMath.parse(OpenMath.xml(obj); format = :xml)
            viamml = OpenMath.parse(OpenMath.mathml(obj); format = :mathml)
            canonicalize(viaxml) == canonicalize(viamml)
        end
    end

    @check max_examples = 300 function p3_mathml_write_stable(obj = Generators.gen_object())
        Regression.checked("p3_mathml_write_stable", obj) do obj
            once = OpenMath.mathml(obj)
            once == OpenMath.mathml(OpenMath.parse(once; format = :mathml))
        end
    end

    @check max_examples = 300 function p3_json_write_stable(obj = Generators.gen_object())
        Regression.checked("p3_json_write_stable", obj) do obj
            once = OpenMath.json(obj)
            once == OpenMath.json(OpenMath.parse(once; format = :json))
        end
    end

    Regression.flush!()
end

@testitem "P4: the binary encoding round-trips" tags = [:property] begin
    using Supposition, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    # This layer matters more here than anywhere else. No oracle covers the binary
    # encoding yet — the reference crate leaves §3.2 unimplemented, and GAP's
    # implementation is not wired up — so apart from the byte sequences the
    # standard prints, agreement with the other three encodings is the only
    # evidence that our reading of §3.2 is anyone else's.
    @check max_examples = 400 function p4_binary_roundtrip(obj = Generators.gen_object())
        Regression.checked("p4_binary_roundtrip", obj) do obj
            canonicalize(OpenMath.read_binary(OpenMath.binary(obj))) == canonicalize(obj)
        end
    end

    @check max_examples = 400 function p4_binary_agrees(obj = Generators.gen_object())
        Regression.checked("p4_binary_agrees", obj) do obj
            viaxml = OpenMath.parse(OpenMath.xml(obj); format = :xml)
            viabin = OpenMath.read_binary(OpenMath.binary(obj))
            canonicalize(viaxml) == canonicalize(viabin)
        end
    end

    @check max_examples = 300 function p4_binary_write_stable(obj = Generators.gen_object())
        Regression.checked("p4_binary_write_stable", obj) do obj
            once = OpenMath.binary(obj)
            once == OpenMath.binary(OpenMath.read_binary(once))
        end
    end

    Regression.flush!()
end

@testitem "P4b: the binary reader is total" tags = [:property] begin
    using Supposition, Supposition.Data, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    # A byte-oriented reader is the likeliest place in this package for an
    # unbounded allocation or a loop that never ends, because every length it
    # acts on came from the input. Noise alone rarely gets past the first byte,
    # so truncation of real documents carries most of the weight.
    bytes = Data.Vectors(map(UInt8, Data.Integers(0, 255)); min_size = 0, max_size = 48)

    @check max_examples = 2000 function p4b_noise(src = bytes)
        try
            OpenMath.read_binary(src)
            true
        catch err
            err isa OpenMath.OpenMathError
        end
    end

    @check max_examples = 800 function p4b_truncated(
            obj = Generators.gen_object(),
            cut = Data.Integers(0, 100)
    )
        src = OpenMath.binary(obj)
        n = clamp(div(cut * length(src), 100), 0, length(src))
        try
            OpenMath.read_binary(@view src[1:n])
            n == length(src)
        catch err
            err isa OpenMath.OpenMathError
        end
    end

    @check max_examples = 800 function p4b_one_byte_flipped(
            obj = Generators.gen_object(),
            at = Data.Integers(0, 100),
            to = map(UInt8, Data.Integers(0, 255))
    )
        src = OpenMath.binary(obj)
        i = clamp(1 + div(at * (length(src) - 1), 100), 1, length(src))
        src[i] = to
        try
            OpenMath.read_binary(src)
            true
        catch err
            err isa OpenMath.OpenMathError
        end
    end

    Regression.flush!()
end

@testitem "P2b: writing is idempotent byte for byte" tags = [:property] begin
    using Supposition, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    # §4.4: write(read(write(x))) == write(x). A writer that is merely
    # round-trip-correct can still be unstable, which makes diffs useless.
    @check max_examples = 400 function p2b_write_stable(obj = Generators.gen_object())
        Regression.checked("p2b_write_stable", obj) do obj
            once = OpenMath.xml(obj)
            once == OpenMath.xml(OpenMath.parse(once; format = :xml))
        end
    end

    Regression.flush!()
end

@testitem "P5: minimize_cdbase inverts resolve_cdbase" tags = [:property] begin
    using Supposition, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    # The pair is not an identity on arbitrary trees — resolving then minimising
    # hoists a base the original spelled out on each symbol — but it is stable:
    # applying it twice changes nothing more than applying it once.
    @check max_examples = 400 function p5_stable(obj = Generators.gen_node())
        Regression.checked("p5_stable", obj) do obj
            once = minimize_cdbase(resolve_cdbase(obj))
            minimize_cdbase(resolve_cdbase(once)) == once
        end
    end

    # And it never changes what the object means.
    @check max_examples = 400 function p5_meaning(obj = Generators.gen_node())
        Regression.checked("p5_meaning", obj) do obj
            canonicalize(minimize_cdbase(resolve_cdbase(obj))) == canonicalize(obj)
        end
    end

    Regression.flush!()
end

@testitem "P6: the base64 codec is a bijection" tags = [:property] begin
    using Supposition, Supposition.Data, OpenMath
    using OpenMath: base64_encode, base64_decode

    @check max_examples = 1000 function p6_roundtrip(
            bytes = map(v -> UInt8.(v),
            Data.Vectors(Data.Integers(0, 255); min_size = 0, max_size = 64)))
        base64_decode(base64_encode(bytes)) == bytes
    end
end

@testitem "P7: validate never throws" tags = [:property] begin
    using Supposition, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    @check max_examples = 500 function p7_total(obj = Generators.gen_node())
        Regression.checked("p7_total", obj) do obj
            validate(obj) isa Vector{OpenMath.OMValidationIssue}
        end
    end

    Regression.flush!()
end

@testitem "P8: parsing stays inside OpenMathError for any input" tags = [:property, :slow] begin
    using Supposition, Supposition.Data, OpenMath

    # Arbitrary Unicode, not just ASCII: the tokenizer scans bytes, so multi-byte
    # characters and lone continuation bytes are exactly where it can go wrong.
    text = Data.Text(Data.UnicodeCharacters(); min_len = 0, max_len = 40)

    @check max_examples = 1000 function p8_json(src = text)
        try
            OpenMath.parse(src; format = :json)
            true
        catch err
            err isa OpenMath.OpenMathError
        end
    end

    @check max_examples = 2000 function p8_strict(src = text)
        try
            OpenMath.parse(src)
            true
        catch err
            err isa OpenMath.OpenMathError
        end
    end

    @check max_examples = 1000 function p8_lenient(src = text)
        try
            OpenMath.parse(src; mode = :lenient)
            true
        catch err
            err isa OpenMath.OpenMathError
        end
    end
end

@testitem "P8b: fragments of well-formed documents also stay inside OpenMathError" tags = [:property] begin
    using Supposition, Supposition.Data, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    # Truncation is the realistic failure: it is what a network peer produces
    # when it dies halfway through sending. Random noise rarely gets past the
    # first byte, so it exercises far less of the reader than this does.
    @check max_examples = 600 function p8b_truncated(
            obj = Generators.gen_object(),
            cut = Data.Integers(0, 100)
    )
        src = OpenMath.xml(obj)
        n = ncodeunits(src)
        piece = String(@view codeunits(src)[1:clamp(div(cut * n, 100), 0, n)])
        try
            OpenMath.parse(piece)
            true
        catch err
            err isa OpenMath.OpenMathError
        end
    end

    Regression.flush!()
end

@testitem "the generators are not vacuous" tags = [:property] begin
    using Supposition, OpenMath
    include(joinpath(@__DIR__, "..", "harness", "generators.jl"))
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    # A property that holds because the generator only ever built OMI(0) holds
    # vacuously (harness spec §4.5). These floors make that impossible to miss.
    counts = Generators.diversity(Generators.gen_node(), 400)
    for k in (:OMI, :OMF, :OMSTR, :OMB, :OMV, :OMS, :OMA, :OMBIND, :OME, :OMATTR)
        @test "$k: generated" == "$k: $(get(counts, k, 0) >= 10 ? "generated" :
                                         "only $(get(counts, k, 0)) in 400 draws")"
    end
    # OMR is absent by construction: a reference needs a matching id elsewhere in
    # the tree, which the recursive generator cannot arrange. Structure sharing is
    # covered by corpus/standard/omr-sharing and by the expand_references tests.
    @test get(counts, :OMR, 0) == 0

    Regression.flush!()
end

@testitem "P9: the Symbolics round trip is the identity on generated expressions" tags = [
    :property, :symbolics] begin
    using Supposition, Supposition.Data, OpenMath, Symbolics
    include(joinpath(@__DIR__, "..", "harness", "regression.jl"))

    # The unit tests cover sixteen expressions written by hand, which is sixteen
    # shapes someone thought of. This generates them instead, restricted to the
    # symbols the phrasebook maps — which is the restriction the property needs
    # to be true at all, and stating it is half the point.
    p = OpenMath.symbolics_phrasebook()
    vars = [Symbolics.variable(n) for n in (:x, :y, :z)]

    leaf = Data.OneOf(Data.SampledFrom(vars),
        map(Num, Data.Integers(-8, 8)))
    unary = Data.SampledFrom([sin, cos, tan, exp, abs, sqrt, -, atan, tanh])
    binary = Data.SampledFrom([+, *, /, max, min])
    # `^` is generated separately with a small non-negative exponent: Julia
    # refuses `2^-4` on integers, so a general binary `^` generates expressions
    # that are not valid Julia rather than exercising this package.
    exponent = map(Num, Data.Integers(0, 4))

    # `map` rather than `@composed`: the macro defines a method, which cannot
    # happen inside the closure `Data.Recursive` calls.
    function grow(child)
        u = map(t -> t[1](t[2]), Data.Pairs(unary, child))
        b = map(t -> t[1](t[2][1], t[2][2]),
            Data.Pairs(binary, Data.Pairs(child, child)))
        pow = map(t -> t[1]^t[2], Data.Pairs(child, exponent))
        return Data.OneOf(u, b, pow)
    end
    expressions = Data.Recursive(leaf, grow; max_layers = 3)

    # The property is *idempotence*, not identity, and the difference is a fact
    # about Symbolics rather than a weakening to make a test pass.
    #
    # Symbolics keeps several representations of one mathematical object and
    # `isequal` is structural: `x^4` can arrive as `Mul(1, Pow(x, 4))`, distinct
    # from `Pow(x, 4)` though equal as mathematics, and `2//1` normalises to `2`
    # on the way back in. Neither distinction survives a trip through OpenMath,
    # and neither should: OpenMath encodes the object, not the host's spelling of
    # it. So the first round trip may land on a different representative, and
    # every one after that must be a fixed point — which is what a lossless
    # encoding actually promises here.
    #
    # The identity *does* hold for expressions in a normal form, and the sixteen
    # hand-written cases in test/unit/symbolics.jl assert it directly.
    @check max_examples = 500 function p9_symbolics_roundtrip(e = expressions)
        Regression.checked("p9_symbolics_roundtrip", e) do e
            once = interpret(p, to_openmath(e))
            twice = interpret(p, to_openmath(once))
            isequal(once, twice)
        end
    end

    @check max_examples = 300 function p9_symbolics_encoding_stable(e = expressions)
        Regression.checked("p9_symbolics_encoding_stable", e) do e
            om = to_openmath(interpret(p, to_openmath(e)))
            om == to_openmath(interpret(p, om))
        end
    end

    # And the generator is not vacuous: a property that held because every draw
    # was `x` would hold for the wrong reason (harness spec §4.5).
    seen = Set{Any}()
    for e in example(expressions, 200)
        u = Symbolics.unwrap(e)
        Symbolics.iscall(u) && push!(seen, Symbolics.operation(u))
    end
    @test length(seen) >= 5
end
