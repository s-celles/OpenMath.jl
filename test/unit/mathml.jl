# SPDX-License-Identifier: MIT
#
# REQ-MML-001..005 — the Strict Content MathML encoding (MathML 4 §4.1.3), the
# fourth encoding the OpenMath standard endorses.

@testitem "mathml: leaves" tags = [:unit, :mathml] begin
    using OpenMath
    body(x) = match(r"<math[^>]*>(.*)</math>"s, OpenMath.mathml(OMObject(x))).captures[1]

    @test body(OMInteger(42)) == """<cn type="integer">42</cn>"""
    @test body(OMInteger(-7)) == """<cn type="integer">-7</cn>"""
    @test body(OMFloat(1.5)) == """<cn type="double">1.5</cn>"""
    @test body(OMString("hi")) == "<cs>hi</cs>"
    @test body(OMVariable("x")) == "<ci>x</ci>"
    @test body(OMSymbol("arith1", "plus")) == """<csymbol cd="arith1">plus</csymbol>"""
    @test body(OMBytes(UInt8[0xde, 0xad])) == "<cbytes>3q0=</cbytes>"
    @test body(OMReference("#a")) == """<share href="#a"/>"""
end

@testitem "mathml: cn carries a mandatory type, and hexdouble for the rest" tags = [
    :unit, :mathml] begin
    using OpenMath
    attr(x) = match(r"""<cn type="([a-z]+)">([^<]*)</cn>""",
        OpenMath.mathml(OMObject(OMFloat(x))))

    # §4.1.3 makes `type` mandatory in Strict Content MathML, from
    # {integer, real, double, hexdouble}.
    for x in (1.5, -1500.0, 0.0, -0.0, 1e308, 5.0e-324)
        t, v = attr(x)
        @test t == "double"
        @test isequal(Base.parse(Float64, v), x)
    end
    # MathML has no literal for NaN or the infinities in a strict `cn` either, so
    # `hexdouble` carries them — the same answer as XML's hex= and JSON's
    # hexadecimal.
    for x in (NaN, Inf, -Inf)
        t, v = attr(x)
        @test t == "hexdouble"
        @test length(v) == 16
        @test isequal(reinterpret(Float64, Base.parse(UInt64, v; base = 16)), x)
    end
end

@testitem "mathml: composites" tags = [:unit, :mathml] begin
    using OpenMath
    body(x) = match(r"<math[^>]*>(.*)</math>"s, OpenMath.mathml(OMObject(x))).captures[1]

    @test body(OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x"))) ==
          """<apply><csymbol cd="arith1">plus</csymbol>""" *
          """<cn type="integer">1</cn><ci>x</ci></apply>"""

    @test body(OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")],
        OMVariable("x"))) ==
          """<bind><csymbol cd="fns1">lambda</csymbol><bvar><ci>x</ci></bvar>""" *
          """<ci>x</ci></bind>"""

    @test body(OMError(OMSymbol("error1", "e"), OMOrForeign[OMInteger(1)])) ==
          """<cerror><csymbol cd="error1">e</csymbol>""" *
          """<cn type="integer">1</cn></cerror>"""
end

@testitem "mathml: the namespace and document element" tags = [:unit, :mathml] begin
    using OpenMath
    s = OpenMath.mathml(OMObject(OMInteger(1)))
    @test occursin("""<math xmlns="http://www.w3.org/1998/Math/MathML\"""", s)
    @test OpenMath.MATHML_NS == "http://www.w3.org/1998/Math/MathML"
end

@testitem "mathml: cdbase is emitted only where it changes" tags = [:unit, :mathml] begin
    using OpenMath
    # The default CD base is the OpenMath one (§4.1.3), so an ordinary symbol
    # needs no cdbase attribute.
    @test !occursin("cdbase", OpenMath.mathml(OMObject(OMS"arith1#plus")))
    @test !occursin("cdbase",
        OpenMath.mathml(OMObject(resolve_cdbase(OMS"arith1#plus"))))
    other = OMSymbol("mycd", "f"; cdbase = "http://example.org/cd")
    @test occursin("""cdbase="http://example.org/cd\"""",
        OpenMath.mathml(OMObject(other)))
end

@testitem "mathml: round-trip preserves canonical form" tags = [:unit, :mathml] begin
    using OpenMath
    objects = [
        OMInteger(0), OMInteger(-1), OMInteger(BigInt(2)^200), OMInteger(typemin(Int64)),
        OMFloat(NaN), OMFloat(-0.0), OMFloat(1e308), OMFloat(5.0e-324),
        OMString(""), OMString("a<b&c"), OMString("λ ℝ"),
        OMBytes(UInt8[]), OMBytes(UInt8[0, 1, 255]), OMVariable("λ"),
        OMSymbol("arith1", "plus"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")),
        OMBinding(OMSymbol("fns1", "lambda"),
            [OMBoundVariable("x"), OMBoundVariable("y")], OMVariable("x")),
        OMError(OMSymbol("error1", "e"), OMOrForeign[OMInteger(1)]),
        OMAttribution([OMAttributePair(OMSymbol("ecc", "t"), OMString("R"))],
            OMVariable("x")),
        OMApplication(OMSymbol("mycd", "f"; cdbase = "http://example.org/cd"),
            [OMInteger(1)])
    ]
    for obj in objects
        s = OpenMath.mathml(OMObject(obj))
        @test canonicalize(OpenMath.parse(s; format = :mathml).object) == canonicalize(obj)
    end
end

@testitem "mathml: writing is idempotent byte for byte" tags = [:unit, :mathml] begin
    using OpenMath
    for obj in (OMInteger(42), OMFloat(NaN), OMString("a<b"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")))
        once = OpenMath.mathml(OMObject(obj))
        @test once == OpenMath.mathml(OpenMath.parse(once; format = :mathml))
    end
end

@testitem "mathml: the three encodings agree" tags = [:unit, :mathml] begin
    using OpenMath
    # Four independent implementations of the same grammar now, so agreement is a
    # real check rather than a tautology.
    for obj in (OMInteger(BigInt(2)^200), OMFloat(NaN), OMString("a<b&c"),
        OMBytes(UInt8[0, 255]), OMVariable("λ"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")),
        OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")], OMVariable("x")))
        x = canonicalize(OpenMath.parse(OpenMath.xml(OMObject(obj)); format = :xml))
        j = canonicalize(OpenMath.parse(OpenMath.json(OMObject(obj)); format = :json))
        m = canonicalize(OpenMath.parse(OpenMath.mathml(OMObject(obj)); format = :mathml))
        @test x == j
        @test x == m
    end
end

@testitem "mathml: non-strict Content MathML is rejected, not guessed (REQ-MML-004)" tags = [
    :unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    # The normative correspondence is with *Strict* Content MathML. The full
    # language has constructs with no OpenMath counterpart, and guessing at them
    # is how this bridge usually goes wrong.
    bad = ["<math$ns><apply><plus/><cn>1</cn></apply></math>",   # operator element
        "<math$ns><cn>1</cn></math>",                            # no type attribute
        "<math$ns><cn type=\"rational\">1<sep/>2</cn></math>",   # non-strict type
        "<math$ns><mrow><mi>x</mi></mrow></math>",               # presentation
        "<math$ns><apply/></math>",                              # no applicant
        "<math$ns></math>",                                      # empty
        "<math$ns><ci/></math>",                                 # no name
        "<math$ns><csymbol>plus</csymbol></math>"]               # no cd
    for src in bad
        e = try
            OpenMath.parse(src; format = :mathml)
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathParseError
    end
end

@testitem "mathml: :auto does not guess between XML and MathML" tags = [:unit, :mathml] begin
    using OpenMath
    # Both encodings are XML, so sniffing on the leading byte cannot separate
    # them. The document element does, and that is what the reader dispatches on.
    m = OpenMath.mathml(OMObject(OMInteger(1)))
    @test OpenMath.parse(m).object == OMInteger(1)
    x = OpenMath.xml(OMObject(OMInteger(1)))
    @test OpenMath.parse(x).object == OMInteger(1)
    @test OpenMath.sniff_format(m) === :xml     # still XML at the byte level
end

@testitem "mathml: MIME rendering (REQ-MML-005)" tags = [:unit, :mathml] begin
    using OpenMath
    obj = OMObject(OMInteger(1))
    @test repr(MIME("application/mathml+xml"), obj) == OpenMath.mathml(obj)
end
