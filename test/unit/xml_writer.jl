# SPDX-License-Identifier: MIT
#
# REQ-XML-002, REQ-XML-003, REQ-XML-004, REQ-XML-006, REQ-XML-010, REQ-API-008 —
# the XML writer (standard §3.1).

@testitem "writer: leaves" tags = [:unit, :xml] begin
    using OpenMath
    body(x) = begin
        s = OpenMath.xml(OMObject(x))
        m = match(r"<OMOBJ[^>]*>(.*)</OMOBJ>"s, s)
        m === nothing ? s : m.captures[1]
    end

    @test body(OMInteger(42)) == "<OMI>42</OMI>"
    @test body(OMInteger(-7)) == "<OMI>-7</OMI>"
    @test body(OMInteger(BigInt(2)^200)) == "<OMI>$(BigInt(2)^200)</OMI>"
    @test body(OMInteger(typemin(Int64))) == "<OMI>$(typemin(Int64))</OMI>"
    @test body(OMString("hi")) == "<OMSTR>hi</OMSTR>"
    @test body(OMVariable("x")) == """<OMV name="x"/>"""
    @test body(OMSymbol("arith1", "plus")) == """<OMS cd="arith1" name="plus"/>"""
    @test body(OMBytes(UInt8[0xde, 0xad, 0xbe, 0xef])) == "<OMB>3q2+7w==</OMB>"
    @test body(OMReference("#a")) == """<OMR href="#a"/>"""
end

@testitem "writer: OMF selects hex only when decimal loses the value" tags = [:unit, :xml] begin
    using OpenMath
    attr(x) = match(r"<OMF ([a-z]+)=\"([^\"]*)\"/>", OpenMath.xml(OMObject(OMFloat(x)))).captures

    # REQ-XML-004: a value that round-trips through decimal is written as dec.
    for x in (1.5, -1500.0, 0.0, -0.0, 1e308, 5.0e-324, 1 / 3)
        k, v = attr(x)
        @test k == "dec"
        @test isequal(Base.parse(Float64, v), x)
    end
    # REQ-XML-003: a value that does not gets the IEEE-754 bit pattern instead.
    for x in (NaN, Inf, -Inf)
        k, v = attr(x)
        @test k == "hex"
        @test length(v) == 16
        @test isequal(reinterpret(Float64, Base.parse(UInt64, v; base = 16)), x)
    end
end

@testitem "writer: composites" tags = [:unit, :xml] begin
    using OpenMath
    body(x) = match(r"<OMOBJ[^>]*>(.*)</OMOBJ>"s, OpenMath.xml(OMObject(x))).captures[1]

    @test body(OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x"))) ==
          """<OMA><OMS cd="arith1" name="plus"/><OMI>1</OMI><OMV name="x"/></OMA>"""

    @test body(OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")],
        OMVariable("x"))) ==
          """<OMBIND><OMS cd="fns1" name="lambda"/><OMBVAR><OMV name="x"/></OMBVAR>""" *
          """<OMV name="x"/></OMBIND>"""

    @test body(OMError(OMSymbol("error1", "unhandled_symbol"),
        OMOrForeign[OMInteger(1)])) ==
          """<OME><OMS cd="error1" name="unhandled_symbol"/><OMI>1</OMI></OME>"""

    @test body(OMAttribution([OMAttributePair(OMSymbol("ecc", "type"), OMString("R"))],
        OMVariable("x"))) ==
          """<OMATTR><OMATP><OMS cd="ecc" name="type"/><OMSTR>R</OMSTR></OMATP>""" *
          """<OMV name="x"/></OMATTR>"""
end

@testitem "writer: an attributed bound variable round-trips" tags = [:unit, :xml] begin
    using OpenMath
    bv = OMBoundVariable("x", [OMAttributePair(OMSymbol("ecc", "type"), OMString("R"))])
    b = OMBinding(OMSymbol("fns1", "lambda"), [bv], OMVariable("x"))
    s = OpenMath.xml(OMObject(b))
    @test occursin("<OMBVAR><OMATTR>", s)
    @test canonicalize(OpenMath.parse(s).object) == canonicalize(b)
end

@testitem "writer: OMFOREIGN content is emitted verbatim" tags = [:unit, :xml] begin
    using OpenMath
    e = OMError(OMSymbol("error1", "unhandled_symbol"),
        OMOrForeign[OMForeign("text/html", """<b class="x">bold</b>""")])
    s = OpenMath.xml(OMObject(e))
    @test occursin("""<OMFOREIGN encoding="text/html"><b class="x">bold</b></OMFOREIGN>""", s)
    @test canonicalize(OpenMath.parse(s).object) == canonicalize(e)
end

@testitem "writer: foreign content that cannot be read back is refused" tags = [:unit, :xml] begin
    using OpenMath
    bad = OMError(OMSymbol("error1", "unhandled_symbol"),
        OMOrForeign[OMForeign("text/plain", "raw & <text>")])
    e = try
        OpenMath.xml(OMObject(bad))
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathConversionError
    @test occursin("well-formed", sprint(showerror, e))
end

@testitem "writer: cdbase is emitted only where it changes (REQ-XML-006)" tags = [
    :unit, :xml] begin
    using OpenMath

    # A resolved object carries the default base on every symbol; none of it is
    # redundant output.
    plain = OMSymbol("arith1", "plus")(OMInteger(1))
    @test !occursin("cdbase", OpenMath.xml(OMObject(resolve_cdbase(plain))))
    @test !occursin("cdbase", OpenMath.xml(OMObject(plain)))

    # The writer is faithful, not clever: each symbol whose base differs from the
    # one it inherits carries the attribute. That is two here, and correct.
    shared = OMApplication(OMSymbol("mycd", "f"; cdbase = "http://example.org/cd"),
        [OMSymbol("mycd", "g"; cdbase = "http://example.org/cd")])
    @test count(_ -> true, eachmatch(r"cdbase=", OpenMath.xml(OMObject(shared)))) == 2

    # Hoisting the shared base is minimize_cdbase's job, and then it appears once.
    once = OpenMath.xml(OMObject(minimize_cdbase(shared)))
    @test count(_ -> true, eachmatch(r"cdbase=", once)) == 1
    @test canonicalize(OpenMath.parse(once).object) == canonicalize(shared)

    # An inner override is emitted where it takes effect.
    nested = OMApplication(OMSymbol("a", "f"; cdbase = "http://outer.example/cd"),
        [OMSymbol("b", "g"; cdbase = "http://inner.example/cd")])
    s2 = OpenMath.xml(OMObject(nested))
    @test occursin("http://outer.example/cd", s2)
    @test occursin("http://inner.example/cd", s2)
end

@testitem "writer: escaping" tags = [:unit, :xml] begin
    using OpenMath
    s = OpenMath.xml(OMObject(OMString("a<b&c>d\"e'f")))
    @test occursin("a&lt;b&amp;c&gt;d", s)
    @test !occursin("<b&c>", s)
    # Attribute values are escaped too.
    v = OpenMath.xml(OMObject(OMReference("#a\"b&c")))
    @test occursin("""href="#a&quot;b&amp;c\"""", v)
    # And the CDATA-close sequence cannot appear verbatim in character data.
    @test !occursin("]]>", OpenMath.xml(OMObject(OMString("]]>"))))
end

@testitem "writer: whitespace in OMSTR survives both modes (REQ-XML-010)" tags = [
    :unit, :xml] begin
    using OpenMath
    for text in ("  two  spaces\n", "\t\ttabs", "trailing   ", "")
        obj = OMApplication(OMSymbol("arith1", "plus"), [OMString(text), OMInteger(1)])
        for pretty in (false, true)
            s = OpenMath.xml(OMObject(obj); pretty = pretty)
            @test OpenMath.parse(s).object.arguments[1] == OMString(text)
        end
    end
end

@testitem "writer: pretty mode is only whitespace between elements" tags = [:unit, :xml] begin
    using OpenMath
    obj = OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x"))
    compact = OpenMath.xml(OMObject(obj))
    pretty = OpenMath.xml(OMObject(obj); pretty = true)
    @test occursin('\n', pretty)
    @test !occursin('\n', compact)
    @test OpenMath.parse(pretty).object == OpenMath.parse(compact).object
end

@testitem "writer: ids are emitted and OMR resolves against them" tags = [:unit, :xml] begin
    using OpenMath
    shared = OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1)]; id = "s1")
    obj = OMApplication(OMSymbol("arith1", "times"), [shared, OMReference("#s1")])
    s = OpenMath.xml(OMObject(obj))
    @test occursin("""id="s1\"""", s)
    back = OpenMath.parse(s).object
    @test expand_references(back) == expand_references(obj)
end

@testitem "writer: the OMOBJ shell carries the namespace" tags = [:unit, :xml] begin
    using OpenMath
    s = OpenMath.xml(OMObject(OMInteger(1)))
    @test occursin("""xmlns="http://www.openmath.org/OpenMath\"""", s)
    @test occursin("""version="2.0\"""", s)
    # Strict parsing of our own output must succeed.
    @test OpenMath.parse(s).object == OMInteger(1)
end

@testitem "writer: MIME rendering (REQ-API-008)" tags = [:unit, :xml] begin
    using OpenMath
    obj = OMObject(OMInteger(1))
    @test repr(MIME("application/openmath+xml"), obj) == OpenMath.xml(obj)
    @test repr(MIME("application/openmath+xml"), OMInteger(1)) ==
          OpenMath.xml(OMObject(OMInteger(1)))
end

@testitem "writer: round-trip through XML preserves canonical form" tags = [:unit, :xml] begin
    using OpenMath
    objects = [
        OMInteger(0), OMInteger(-1), OMInteger(BigInt(2)^200), OMFloat(NaN),
        OMFloat(-0.0), OMFloat(1e308), OMString(""), OMString("a<b&c"),
        OMBytes(UInt8[]), OMBytes(UInt8[0, 1, 255]), OMVariable("λ"),
        OMSymbol("arith1", "plus"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")),
        OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")], OMVariable("x")),
        OMError(OMSymbol("error1", "unhandled_symbol"),
            OMOrForeign[OMInteger(1), OMForeign("text/plain", "raw &amp; text"),
                OMForeign("text/html", "<b class=\"x\">bold</b>")]),
        OMAttribution([OMAttributePair(OMSymbol("ecc", "type"), OMString("R"))],
            OMVariable("x")),
        OMApplication(OMSymbol("mycd", "f"; cdbase = "http://example.org/cd"),
            [OMInteger(1)])
    ]
    for obj in objects, pretty in (false, true)

        s = OpenMath.xml(OMObject(obj); pretty = pretty)
        @test canonicalize(OpenMath.parse(s).object) == canonicalize(obj)
    end
end

@testitem "writer: output is byte-stable after one round-trip" tags = [:unit, :xml] begin
    using OpenMath
    # §4.4: write(read(write(x))) == write(x), for every corpus-shaped object.
    for obj in (OMInteger(42), OMFloat(NaN), OMString("a<b"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")),
        OMApplication(OMSymbol("mycd", "f"; cdbase = "http://example.org/cd"),
        [OMInteger(1)]))
        once = OpenMath.xml(OMObject(obj))
        twice = OpenMath.xml(OpenMath.parse(once))
        @test once == twice
    end
end

@testitem "writer: deep objects do not overflow the stack (REQ-SEC-003)" tags = [
    :unit, :xml, :slow] begin
    using OpenMath
    n = 200_000
    deep = foldl((a, _) -> OMSymbol("arith1", "plus")(a), 1:n; init = OMInteger(0))
    elapsed = @elapsed(s = with_limits(OMLimits(; max_depth = n + 10)) do
        OpenMath.xml(OMObject(deep))
    end)
    @test occursin("<OMI>0</OMI>", s)
    @test elapsed < 60          # linear in depth, not quadratic
end

@testitem "writer: foreign content cannot be a document root" tags = [:unit, :xml] begin
    using OpenMath
    # Foreign content is not an OpenMath object, so it cannot be the root of a
    # document. The writers used to accept OMOrForeign and then raise a bare
    # MethodError from inside OMObject — outside the OpenMathError family the API
    # promises. Found by JET; nothing in the corpus, the property layer or the
    # oracle covered it, because foreign content only ever appears *inside* a
    # document there.
    f = OMForeign("text/plain", "raw")
    @test !hasmethod(OpenMath.xml, Tuple{typeof(f)})
    @test !hasmethod(OpenMath.json, Tuple{typeof(f)})
    @test !hasmethod(OpenMath.write_xml, Tuple{IO, typeof(f)})
    @test !hasmethod(OMObject, Tuple{typeof(f)})
    # Inside a document, where the grammar allows it, it still works.
    e = OMError(OMSymbol("error1", "e"), OMOrForeign[f])
    @test canonicalize(OpenMath.parse(OpenMath.xml(OMObject(e))).object) == canonicalize(e)
    @test canonicalize(OpenMath.parse(OpenMath.json(OMObject(e)); format = :json).object) ==
          canonicalize(e)
end
