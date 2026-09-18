# SPDX-License-Identifier: MIT
#
# REQ-PHR-001, REQ-PHR-003, REQ-PHR-005 — phrasebooks as values.

@testitem "phrasebook: a phrasebook is a value, not global state (REQ-PHR-001)" tags = [
    :unit, :phrasebook] begin
    using OpenMath

    # Two callers in one session may legitimately disagree about what a symbol
    # means. A method table cannot hold both; a value can.
    celsius = OMS"http://example.org/cd#units#celsius"
    a = Phrasebook()
    b = Phrasebook()
    define!(a, celsius, x -> x, x -> x)                 # identity
    define!(b, celsius, x -> x * 9 // 5 + 32, x -> x)   # to Fahrenheit

    @test interpret(a, celsius(OMInteger(100))) == 100
    @test interpret(b, celsius(OMInteger(100))) == 212
    @test a !== b
    @test celsius in symbols(a)

    # `symbols` returns the resolved form, because the base is part of a symbol's
    # identity (§2.1.4). Interpretation resolves too, so both spellings work
    # there; only the equality of the listed values is affected.
    @test resolve_cdbase(OMS"arith1#plus") in base_vocabulary()
    @test !(OMS"arith1#plus" in base_vocabulary())
    p = Phrasebook()
    @test interpret(p, OMS"arith1#plus"(OMInteger(1), OMInteger(2))) ==
          interpret(p, resolve_cdbase(OMS"arith1#plus")(OMInteger(1), OMInteger(2)))
end

@testitem "phrasebook: the default one is the dispatch-based conversion" tags = [
    :unit, :phrasebook] begin
    using OpenMath
    p = Phrasebook()
    # Everything `from_openmath` already knew, a fresh phrasebook knows.
    @test interpret(p, OMInteger(42)) == 42
    @test interpret(p, OMFloat(1.5)) === 1.5
    @test interpret(p, OMString("hi")) == "hi"
    @test interpret(p, OMS"logic1#true") === true
    @test interpret(p, OMS"nums1#rational"(OMInteger(3), OMInteger(4))) == 3 // 4
    @test interpret(p, OMS"arith1#plus"(OMInteger(1), OMInteger(2))) == 3
    @test interpret(p, OMObject(OMInteger(7))) == 7
end

@testitem "phrasebook: with_phrasebook scopes the default (REQ-PHR-001)" tags = [
    :unit, :phrasebook] begin
    using OpenMath
    p = Phrasebook()
    define!(p, OMS"arith1#plus", (xs...) -> "intercepted")
    @test from_openmath(OMS"arith1#plus"(OMInteger(1), OMInteger(2))) == 3
    @test with_phrasebook(p) do
        from_openmath(OMS"arith1#plus"(OMInteger(1), OMInteger(2)))
    end == "intercepted"
    # Restored, including when the body throws.
    @test from_openmath(OMS"arith1#plus"(OMInteger(1), OMInteger(2))) == 3
    @test_throws ErrorException with_phrasebook(p) do
        error("boom")
    end
    @test from_openmath(OMS"arith1#plus"(OMInteger(1), OMInteger(2))) == 3
end

@testitem "phrasebook: cdbase is part of the key (REQ-PHR-001)" tags = [
    :unit, :phrasebook] begin
    using OpenMath
    # The same cd and name under a different base is a different symbol (§2.1.4),
    # and a phrasebook that keyed on `cd#name` alone would conflate them.
    mine = OMSymbol("arith1", "plus"; cdbase = "http://example.org/cd")
    p = Phrasebook()
    define!(p, mine, (a, b) -> "mine")
    @test interpret(p, mine(OMInteger(1), OMInteger(2))) == "mine"
    @test interpret(p, OMS"arith1#plus"(OMInteger(1), OMInteger(2))) == 3
    # And the official base written out explicitly is the same symbol as the
    # default, because `resolve_cdbase` says so.
    explicit = OMSymbol("arith1", "plus"; cdbase = CD_BASE)
    @test interpret(p, explicit(OMInteger(1), OMInteger(2))) == 3
end

@testitem "phrasebook: an unknown symbol raises, naming it (REQ-PHR-005)" tags = [
    :unit, :phrasebook] begin
    using OpenMath
    p = Phrasebook()
    e = try
        interpret(p, OMS"nowhere#nothing"(OMInteger(1)))
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathConversionError
    @test occursin("nowhere", sprint(showerror, e))
    @test occursin("nothing", sprint(showerror, e))

    # Silently dropping what it cannot represent is the failure mode this guards:
    # a phrasebook that ignores an attribution turns a faithful document into a
    # plausible lie.
    attributed = OMAttribution([OMAttributePair(OMS"nowhere#units", OMString("m"))],
        OMInteger(5))
    @test_throws OpenMath.OpenMathConversionError interpret(p, attributed)
end

@testitem "phrasebook: interpretation is structural, never evaluation (REQ-PHR-003)" tags = [
    :unit, :phrasebook] begin
    using OpenMath
    p = Phrasebook()
    # A symbol name is a key in a map. It is never turned into code, so a name
    # that happens to spell a Julia function does not become one.
    @test_throws OpenMath.OpenMathConversionError interpret(p,
        OMS"nowhere#run"(OMString("rm -rf /")))
    hostile = OMVariable("exit")
    @test interpret(p, hostile) === :exit          # a Symbol, not `Base.exit`
    @test interpret(p, OMString("1 + 1")) == "1 + 1"
end

@testitem "phrasebook: round-trips through the base vocabulary" tags = [
    :unit, :phrasebook] begin
    using OpenMath
    p = Phrasebook()
    for v in (0, 1, -1, big(2)^100, 1.5, -0.0, "", "λ", 3 // 4, -7 // 2,
        true, false, :x, [1, 2, 3], UInt8[1, 2])
        @test interpret(p, to_openmath(v)) == v
    end
    @test isnan(interpret(p, to_openmath(NaN)))
end

@testitem "phrasebook: define! takes both directions" tags = [:unit, :phrasebook] begin
    using OpenMath
    struct Metres
        value::Float64
    end
    p = Phrasebook()
    m = OMS"http://example.org/cd#units#metre"
    define!(p, m, x -> Metres(x), (x::Metres) -> m(to_openmath(x.value)))
    @test interpret(p, m(OMFloat(2.5))) == Metres(2.5)
    @test express(p, Metres(2.5)) == m(OMFloat(2.5))
    # A type the phrasebook has no rule for falls back to `to_openmath`.
    @test express(p, 42) == OMInteger(42)
end

@testitem "phrasebook: the coverage target is met, element by element" tags = [
    :unit, :phrasebook] begin
    using OpenMath
    # Phase 6's exit criterion: match MathML.jl's table symbol by symbol. Its 85
    # element names are the vocabulary a Julia caller coming from SBML or SciML
    # already has, and they line up with the Content Dictionaries because MathML's
    # Content elements were named after them.
    #
    # The list is transcribed rather than computed, so this test fails if the
    # vocabulary shrinks — which is the point of writing an exit criterion down.
    correspondence = Dict(
        "abs" => "arith1#abs", "and" => "logic1#and", "approx" => "relation1#approx",
        "arg" => "complex1#argument", "ceiling" => "rounding1#ceiling",
        "compose" => "fns1#left_compose", "conjugate" => "complex1#conjugate",
        "divide" => "arith1#divide", "eq" => "relation1#eq", "equal" => "relation1#eq",
        "exp" => "transc1#exp", "exponentiale" => "nums1#e",
        "factorial" => "integer1#factorial", "false" => "logic1#false",
        "floor" => "rounding1#floor", "gcd" => "arith1#gcd", "geq" => "relation1#geq",
        "gt" => "relation1#gt", "ident" => "fns1#identity",
        "imaginary" => "complex1#imaginary", "infinity" => "nums1#infinity",
        "inverse" => "fns1#inverse", "lcm" => "arith1#lcm", "leq" => "relation1#leq",
        "ln" => "transc1#ln", "log" => "transc1#log", "lt" => "relation1#lt",
        "max" => "minmax1#max", "mean" => "s_data1#mean", "median" => "s_data1#median",
        "min" => "minmax1#min", "minus" => "arith1#minus", "mode" => "s_data1#mode",
        "neq" => "relation1#neq", "not" => "logic1#not", "notanumber" => "nums1#NaN",
        "or" => "logic1#or", "pi" => "nums1#pi", "plus" => "arith1#plus",
        "power" => "arith1#power", "prod" => "arith1#product",
        "quotient" => "integer1#quotient", "real" => "complex1#real",
        "rem" => "integer1#remainder", "root" => "arith1#root",
        "round" => "rounding1#round", "sdev" => "s_data1#sdev",
        "times" => "arith1#times", "true" => "logic1#true",
        "variance" => "s_data1#variance", "vector" => "linalg2#vector",
        "xor" => "logic1#xor")
    for t in ("sin", "cos", "tan", "sec", "csc", "cot",
        "sinh", "cosh", "tanh", "sech", "csch", "coth")
        correspondence[t] = "transc1#" * t
        correspondence["arc" * t] = "transc1#arc" * t
    end

    have = Set(string(s.cd, "#", s.name) for s in base_vocabulary())
    for (element, symbol) in correspondence
        @test "$(element) → $(symbol): known" ==
              "$(element) → $(symbol): $(symbol in have ? "known" : "MISSING")"
    end
    @test length(correspondence) == 76

    # The nine MathML elements with no entry here are structure, not symbols:
    # `apply`, `bvar`, `ci`, `cn` and `math` are syntax, and `diff`, `lambda` and
    # `piecewise` need the symbolic layer, which is the Symbolics extension.
    for s in ("calculus1#diff", "fns1#lambda", "piece1#piecewise")
        @test !(s in have)
    end
end

@testitem "phrasebook: the number and set constructors Appendix F produces" tags = [
    :unit, :phrasebook] begin
    using OpenMath
    # MathML 4 Appendix F rewrites `<cn base="16">ff</cn>`, `<cn type="constant">γ</cn>`
    # and the `<sep/>` forms into applications of these symbols. They were absent
    # from the vocabulary, so a document could transform correctly and then be
    # refused by the phrasebook — a gap the two files could not see in each
    # other, and that `test/unit/mathml_appendix_f.jl` now gates.

    p = Phrasebook()

    # nums1#based_integer(base, string) — the CD's own signature.
    @test interpret(p, OMS"nums1#based_integer"(OMInteger(16), OMString("ff"))) == 255
    @test interpret(p, OMS"nums1#based_integer"(OMInteger(2), OMString("1011"))) == 11
    @test_throws OpenMath.OpenMathConversionError interpret(p,
        OMS"nums1#based_integer"(OMInteger(16), OMString("g")))

    # nums1#based_float(base, string). Julia parses no float outside base 10, so
    # the two halves are parsed as integers and recombined.
    @test interpret(p, OMS"nums1#based_float"(OMInteger(16), OMString("1.8"))) ≈ 1.5
    @test interpret(p, OMS"nums1#based_float"(OMInteger(2), OMString("101.01"))) ≈ 5.25
    @test interpret(p, OMS"nums1#based_float"(OMInteger(10), OMString("12"))) ≈ 12.0

    # nums1#bigfloat(significand, base, exponent) — the three-argument form
    # Appendix F builds for `<cn type="e-notation">`.
    @test interpret(p, OMS"nums1#bigfloat"(OMInteger(15), OMInteger(10), OMInteger(-1))) ≈
          1.5
    @test interpret(p, OMS"nums1#bigfloat"(OMInteger(3), OMInteger(2), OMInteger(4))) == 48

    # nums1#complex_polar(modulus, argument).
    @test interpret(p, OMS"nums1#complex_polar"(OMInteger(2), OMFloat(0.0))) ≈ 2.0 + 0im
    @test interpret(p, OMS"nums1#complex_polar"(OMInteger(1), OMFloat(π / 2))) ≈ im

    # nums1#gamma is the Euler–Mascheroni constant, not the gamma *function*:
    # `<eulergamma/>` in MathML, `γ` inside a `<cn type="constant">`.
    @test interpret(p, OMS"nums1#gamma") ≈ 0.5772156649015329

    # set1#emptyset.
    @test isempty(interpret(p, OMS"set1#emptyset"))
end

@testitem "phrasebook: a multiset keeps its repeats" tags = [:unit, :phrasebook] begin
    using OpenMath
    # `<set type="multiset">` becomes `multiset1#multiset`, a different symbol
    # from `set1#set` precisely because the repeats are the point.
    p = Phrasebook()
    @test interpret(p, OMS"set1#set"(OMInteger(1), OMInteger(1))) == Set([1])
    @test interpret(p, OMS"multiset1#multiset"(OMInteger(1), OMInteger(1))) == [1, 1]
end
