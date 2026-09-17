# SPDX-License-Identifier: MIT
#
# REQ-XML-001, REQ-XML-005, REQ-XML-007, REQ-API-001, REQ-API-002, REQ-API-003,
# REQ-API-004, REQ-API-007, REQ-SEC-002 — the XML reader (standard §3.1).

@testitem "reader: every leaf kind" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    om(body) = OpenMath.parse("<OMOBJ$ns>$body</OMOBJ>").object

    @test om("<OMI>42</OMI>") == OMInteger(42)
    @test om("<OMI>-7</OMI>") == OMInteger(-7)
    @test om("<OMF dec=\"1.5\"/>") == OMFloat(1.5)
    @test om("<OMSTR>hi</OMSTR>") == OMString("hi")
    @test om("<OMSTR></OMSTR>") == OMString("")
    @test om("<OMV name=\"x\"/>") == OMVariable("x")
    @test om("<OMS cd=\"arith1\" name=\"plus\"/>") == OMSymbol("arith1", "plus")
    @test om("<OMR href=\"#a\"/>") == OMReference("#a")
end

@testitem "reader: OMI accepts decimal and hexadecimal (REQ-XML-005)" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    om(body) = OpenMath.parse("<OMOBJ$ns>$body</OMOBJ>").object

    @test om("<OMI>x1F</OMI>") == OMInteger(31)
    @test om("<OMI>-x1F</OMI>") == OMInteger(-31)
    @test om("<OMI>xdeadBEEF</OMI>") == OMInteger(0xdeadbeef)
    @test om("<OMI> 42 </OMI>") == OMInteger(42)          # §3.1.1 allows padding
    @test om("<OMI>$(BigInt(2)^200)</OMI>") == OMInteger(BigInt(2)^200)
    @test om("<OMI>$(typemin(Int64))</OMI>") == OMInteger(typemin(Int64))
end

@testitem "reader: OMF accepts dec and hex" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    om(body) = OpenMath.parse("<OMOBJ$ns>$body</OMOBJ>").object

    @test om("<OMF dec=\"-1.5e3\"/>") == OMFloat(-1500.0)
    @test om("<OMF hex=\"7FF8000000000000\"/>") == OMFloat(NaN)
    @test om("<OMF hex=\"7FF0000000000000\"/>") == OMFloat(Inf)
    @test om("<OMF hex=\"8000000000000000\"/>") == OMFloat(-0.0)
    @test om("<OMF hex=\"0000000000000001\"/>") == OMFloat(5.0e-324)
end

@testitem "reader: OMB decodes base64 (REQ-XML-007)" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    om(body) = OpenMath.parse("<OMOBJ$ns>$body</OMOBJ>").object

    @test om("<OMB>3q2+7w==</OMB>") == OMBytes(UInt8[0xde, 0xad, 0xbe, 0xef])
    @test om("<OMB></OMB>") == OMBytes(UInt8[])
    @test om("<OMB>3q2+\n  7w==</OMB>") == OMBytes(UInt8[0xde, 0xad, 0xbe, 0xef])
end

@testitem "reader: applications and bindings" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    om(body) = OpenMath.parse("<OMOBJ$ns>$body</OMOBJ>").object

    @test om("""<OMA><OMS cd="arith1" name="plus"/><OMI>1</OMI><OMV name="x"/></OMA>""") ==
          OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1), OMVariable("x")])

    b = om("""<OMBIND><OMS cd="fns1" name="lambda"/>
                <OMBVAR><OMV name="x"/></OMBVAR>
                <OMV name="x"/></OMBIND>""")
    @test b == OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")],
        OMVariable("x"))
end

@testitem "reader: errors, attributions and foreign content" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    om(body) = OpenMath.parse("<OMOBJ$ns>$body</OMOBJ>").object

    @test om("""<OME><OMS cd="error1" name="unhandled_symbol"/><OMI>1</OMI></OME>""") ==
          OMError(OMSymbol("error1", "unhandled_symbol"), OMOrForeign[OMInteger(1)])

    a = om("""<OMATTR><OMATP><OMS cd="ecc" name="type"/><OMSTR>R</OMSTR></OMATP>
                <OMV name="x"/></OMATTR>""")
    @test a == OMAttribution(
        [OMAttributePair(OMSymbol("ecc", "type"), OMString("R"))], OMVariable("x"))

    f = om("""<OME><OMS cd="error1" name="unhandled_symbol"/>
                <OMFOREIGN encoding="text/plain">raw &amp; text</OMFOREIGN></OME>""")
    # Foreign content is kept as verbatim source, entity references included.
    @test f.arguments[1] == OMForeign("text/plain", "raw &amp; text")
end

@testitem "reader: OMFOREIGN captures embedded markup verbatim" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    src = """<OMOBJ$ns><OME><OMS cd="error1" name="unhandled_symbol"/>
      <OMFOREIGN encoding="text/html"><b class="x">bold</b></OMFOREIGN></OME></OMOBJ>"""
    f = OpenMath.parse(src).object.arguments[1]
    @test f isa OMForeign
    @test f.value == """<b class="x">bold</b>"""
end

@testitem "reader: attributes id, cdbase and version" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    o = OpenMath.parse("""<OMOBJ$ns version="2.0" cdbase="http://example.org/cd">
           <OMA id="n1"><OMS cd="mycd" name="f"/><OMI id="n2">1</OMI></OMA></OMOBJ>""")
    @test o.version == "2.0"
    @test o.cdbase == "http://example.org/cd"
    @test o.object.id == "n1"
    @test o.object.arguments[1].id == "n2"
    @test resolve_cdbase(o).object.applicant.cdbase == "http://example.org/cd"
end

@testitem "reader: namespace prefixes are accepted" tags = [:unit, :xml] begin
    using OpenMath
    o = OpenMath.parse("""<om:OMOBJ xmlns:om="http://www.openmath.org/OpenMath">
                            <om:OMI>1</om:OMI></om:OMOBJ>""")
    @test o.object == OMInteger(1)
end

@testitem "reader: :auto sniffs the encoding (REQ-API-002)" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    @test OpenMath.parse("  <OMOBJ$ns><OMI>1</OMI></OMOBJ>").object == OMInteger(1)
    @test OpenMath.parse("""<?xml version="1.0"?><OMOBJ$ns><OMI>1</OMI></OMOBJ>""").object ==
          OMInteger(1)
end

@testitem "reader: strict mode rejects malformed documents (REQ-API-004)" tags = [
    :unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    bad = ["<OMOBJ$ns><OMA/></OMOBJ>",                       # no applicant, §2.1.1
        "<OMOBJ$ns><OME><OMI>1</OMI></OME></OMOBJ>",      # error head not a symbol
        "<OMOBJ$ns><OMNOPE/></OMOBJ>",                    # unknown element
        "<OMOBJ$ns><OMS cd=\"arith1\"/></OMOBJ>",         # OMS without name
        "<OMOBJ$ns><OMV/></OMOBJ>",                       # OMV without name
        "<OMOBJ$ns><OMI>notaninteger</OMI></OMOBJ>",
        "<OMOBJ$ns><OMF dec=\"nope\"/></OMOBJ>",
        "<OMOBJ$ns><OMF/></OMOBJ>",                       # neither dec nor hex
        "<OMOBJ$ns><OMB>!!!!</OMB></OMOBJ>",              # invalid base64
        "<OMOBJ$ns><OMI>1</OMI><OMI>2</OMI></OMOBJ>",     # two roots
        "<OMI>1</OMI>"]                                   # root is not OMOBJ
    for src in bad
        e = try
            OpenMath.parse(src)
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathParseError
        @test e.path !== nothing || e.offset !== nothing
    end
end

@testitem "reader: lenient mode accepts a missing namespace (REQ-API-005)" tags = [
    :unit, :xml] begin
    using OpenMath
    o = OpenMath.parse("<OMOBJ><OMI>1</OMI></OMOBJ>"; mode = :lenient)
    @test o.object == OMInteger(1)
    @test !isempty(o.warnings)
    @test any(w -> occursin("namespace", w), o.warnings)
    @test_throws OpenMath.OpenMathParseError OpenMath.parse("<OMOBJ><OMI>1</OMI></OMOBJ>")
end

@testitem "reader: depth is bounded (REQ-SEC-002)" tags = [:unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    deep = "<OMOBJ$ns>" * "<OMA><OMS cd=\"a\" name=\"b\"/>"^200 *
           "<OMI>0</OMI>" * "</OMA>"^200 * "</OMOBJ>"
    e = try
        with_limits(OMLimits(; max_depth = 20)) do
            OpenMath.parse(deep)
        end
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathLimitError
    @test e.limit === :max_depth
    # Well within the limit, the same shape parses.
    @test OpenMath.parse(deep).object isa OMApplication
end

@testitem "reader: a 200_000-deep document does not overflow the stack" tags = [
    :unit, :xml, :slow] begin
    using OpenMath
    n = 200_000
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    src = "<OMOBJ$ns>" * "<OMA><OMS cd=\"a\" name=\"b\"/>"^n * "<OMI>0</OMI>" *
          "</OMA>"^n * "</OMOBJ>"
    elapsed = @elapsed(o = with_limits(OMLimits(; max_depth = n + 10)) do
        OpenMath.parse(src)
    end)
    @test depth(o.object) == n + 1

    # Parsing must be linear in depth. Two earlier implementations were quadratic
    # here — a materialised error path, then a namespace scope stack searched from
    # the top — and depth is attacker-controlled, so quadratic is a denial of
    # service rather than a slow path. This budget is deliberately loose (the
    # linear implementation runs in ~3 s); it exists to catch a reintroduction of
    # quadratic behaviour, not to police constant factors.
    @test elapsed < 60
end

@testitem "reader: never throws anything but OpenMathError (REQ-SEC-001)" tags = [
    :unit, :xml] begin
    using OpenMath
    srcs = ["", "<", "<OMOBJ>", "<OMOBJ/>", "<OMOBJ></OMOBJ>", "\xff\xfe",
        "<OMOBJ><OMI></OMI></OMOBJ>", "<OMOBJ><OMATTR><OMATP/></OMATTR></OMOBJ>",
        "<OMOBJ><OMBIND><OMS cd=\"a\" name=\"b\"/></OMBIND></OMOBJ>",
        "<OMOBJ><OMBVAR/></OMOBJ>", "<OMOBJ><OMATP/></OMOBJ>",
        "<OMOBJ><OMFOREIGN/></OMOBJ>", "<OMOBJ><OMR/></OMOBJ>"]
    for src in srcs, mode in (:strict, :lenient)

        r = try
            OpenMath.parse(src; mode = mode)
            :ok
        catch err
            err isa OpenMath.OpenMathError ? :openmath_error : err
        end
        @test r === :ok || r === :openmath_error
    end
end

@testitem "reader: lenient warnings are bounded (REQ-SEC-001)" tags = [:unit, :xml] begin
    using OpenMath
    # Warnings come from attacker-controlled input, so the list needs a ceiling:
    # otherwise a hostile document in :lenient mode grows one as large as itself.
    n = 5_000
    src = "<OMOBJ><OMA><OMS cd=\"a\" name=\"b\"/>" *
          repeat("<OMSTR>x</OMSTR>junk", n) * "</OMA></OMOBJ>"
    o = OpenMath.parse(src; mode = :lenient)
    @test length(o.warnings) <= 101
    @test occursin("suppressed", o.warnings[end])
    # The namespace warning is document-wide and is reported exactly once.
    @test count(w -> occursin("no OpenMath namespace declared", w), o.warnings) == 1
end
