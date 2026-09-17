# SPDX-License-Identifier: MIT
#
# REQ-JSN-002, REQ-JSN-003, REQ-JSN-006, REQ-OM-003, REQ-API-008 — the JSON
# writer (standard §3.3).

@testitem "json writer: leaves" tags = [:unit, :json] begin
    using OpenMath
    body(x) = begin
        s = OpenMath.json(OMObject(x))
        m = match(r"\"object\":(.*)\}$", s)
        m === nothing ? s : m.captures[1]
    end

    @test body(OMInteger(42)) == """{"kind":"OMI","integer":42}"""
    @test body(OMInteger(-7)) == """{"kind":"OMI","integer":-7}"""
    @test body(OMFloat(1.5)) == """{"kind":"OMF","float":1.5}"""
    @test body(OMString("hi")) == """{"kind":"OMSTR","string":"hi"}"""
    @test body(OMVariable("x")) == """{"kind":"OMV","name":"x"}"""
    @test body(OMSymbol("arith1", "plus")) ==
          """{"kind":"OMS","cd":"arith1","name":"plus"}"""
    @test body(OMBytes(UInt8[0xde, 0xad])) == """{"kind":"OMB","base64":"3q0="}"""
    @test body(OMReference("#a")) == """{"kind":"OMR","href":"#a"}"""
end

@testitem "json writer: large integers become decimal strings (REQ-JSN-003)" tags = [
    :unit, :json] begin
    using OpenMath
    field(v) = match(r"\"(integer|decimal)\":(\"?)([^,\"}]*)", OpenMath.json(OMObject(OMInteger(v))))

    # Inside the range every JSON consumer reads exactly, a number is a number.
    for v in (0, 1, -1, 2^53 - 1, -(2^53) + 1)
        m = field(v)
        @test m.captures[1] == "integer"
        @test m.captures[2] == ""
    end
    # Outside it, a JSON number would be silently rounded through Float64 by a
    # great many consumers, so the value travels as a string instead.
    for v in (BigInt(2)^53, -BigInt(2)^53, typemax(Int64), typemin(Int64), BigInt(2)^200)
        m = field(v)
        @test m.captures[1] == "decimal"
        @test m.captures[2] == "\""
        @test Base.parse(BigInt, m.captures[3]) == v
    end
end

@testitem "json writer: OMF uses hexadecimal when JSON has no literal" tags = [:unit, :json] begin
    using OpenMath
    field(v) = match(r"\"(float|hexadecimal)\":(\"?)([^,\"}]*)",
        OpenMath.json(OMObject(OMFloat(v))))

    for v in (1.5, -1500.0, 0.0, -0.0, 1e308, 5.0e-324, 1 / 3)
        m = field(v)
        @test m.captures[1] == "float"
        @test isequal(Base.parse(Float64, m.captures[3]), v)
    end
    # JSON has no NaN or Infinity literal; the IEEE-754 bit pattern is the only
    # lossless spelling the standard offers (§3.3).
    for v in (NaN, Inf, -Inf)
        m = field(v)
        @test m.captures[1] == "hexadecimal"
        @test length(m.captures[3]) == 16
        @test isequal(reinterpret(Float64, Base.parse(UInt64, m.captures[3]; base = 16)), v)
    end
end

@testitem "json writer: composites" tags = [:unit, :json] begin
    using OpenMath
    body(x) = match(r"\"object\":(.*)\}$", OpenMath.json(OMObject(x))).captures[1]

    @test body(OMSymbol("arith1", "plus")(OMInteger(1))) ==
          """{"kind":"OMA","applicant":{"kind":"OMS","cd":"arith1","name":"plus"},""" *
          """"arguments":[{"kind":"OMI","integer":1}]}"""

    @test body(OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")],
        OMVariable("x"))) ==
          """{"kind":"OMBIND","binder":{"kind":"OMS","cd":"fns1","name":"lambda"},""" *
          """"variables":[{"kind":"OMV","name":"x"}],"object":{"kind":"OMV","name":"x"}}"""

    @test body(OMError(OMSymbol("error1", "e"), OMOrForeign[OMInteger(1)])) ==
          """{"kind":"OME","error":{"kind":"OMS","cd":"error1","name":"e"},""" *
          """"arguments":[{"kind":"OMI","integer":1}]}"""

    @test body(OMAttribution([OMAttributePair(OMSymbol("ecc", "t"), OMString("R"))],
        OMVariable("x"))) ==
          """{"kind":"OMATTR","attributes":[[{"kind":"OMS","cd":"ecc","name":"t"},""" *
          """{"kind":"OMSTR","string":"R"}]],"object":{"kind":"OMV","name":"x"}}"""
end

@testitem "json writer: string escaping" tags = [:unit, :json] begin
    using OpenMath
    s(x) = OpenMath.json(OMObject(OMString(x)))
    @test occursin("\"a\\\"b\"", s("a\"b"))
    @test occursin("\"a\\\\b\"", s("a\\b"))
    @test occursin("\\n", s("\n"))
    @test occursin("\\t", s("\t"))
    # Control characters must be escaped; JSON forbids them raw.
    @test occursin("\\u0000", s("\0"))
    @test occursin("\\u001f", s("\x1f"))
    # Non-ASCII travels as itself, since the document is UTF-8.
    @test occursin("λ", s("λ"))
end

@testitem "json writer: cdbase is emitted only where it changes" tags = [:unit, :json] begin
    using OpenMath
    plain = OMSymbol("arith1", "plus")(OMInteger(1))
    @test !occursin("cdbase", OpenMath.json(OMObject(resolve_cdbase(plain))))

    other = OMApplication(OMSymbol("mycd", "f"; cdbase = "http://example.org/cd"),
        [OMInteger(1)])
    @test occursin("http://example.org/cd", OpenMath.json(OMObject(other)))
end

@testitem "json writer: pretty mode (REQ-JSN-006)" tags = [:unit, :json] begin
    using OpenMath
    obj = OMObject(OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")))
    compact = OpenMath.json(obj)
    pretty = OpenMath.json(obj; pretty = true)
    @test !occursin('\n', compact)
    @test occursin('\n', pretty)
    @test OpenMath.parse(pretty; format = :json) == OpenMath.parse(compact; format = :json)
end

@testitem "json writer: MIME rendering (REQ-API-008)" tags = [:unit, :json] begin
    using OpenMath
    obj = OMObject(OMInteger(1))
    @test repr(MIME("application/openmath+json"), obj) == OpenMath.json(obj)
    @test repr(MIME("application/openmath+json"), OMInteger(1)) ==
          OpenMath.json(OMObject(OMInteger(1)))
end

@testitem "json writer: round-trip preserves canonical form" tags = [:unit, :json] begin
    using OpenMath
    objects = [
        OMInteger(0), OMInteger(-1), OMInteger(BigInt(2)^200), OMInteger(typemin(Int64)),
        OMFloat(NaN), OMFloat(-0.0), OMFloat(1e308), OMFloat(5.0e-324),
        OMString(""), OMString("a\"b\\c\nd"), OMString("λ ℝ"),
        OMBytes(UInt8[]), OMBytes(UInt8[0, 1, 255]), OMVariable("λ"),
        OMSymbol("arith1", "plus"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")),
        OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")], OMVariable("x")),
        OMError(OMSymbol("error1", "e"),
            OMOrForeign[OMInteger(1), OMForeign("text/plain", "raw & <text>")]),
        OMAttribution([OMAttributePair(OMSymbol("ecc", "t"), OMString("R"))],
            OMVariable("x")),
        OMApplication(OMSymbol("mycd", "f"; cdbase = "http://example.org/cd"),
            [OMInteger(1)])
    ]
    for obj in objects, pretty in (false, true)

        s = OpenMath.json(OMObject(obj); pretty = pretty)
        @test canonicalize(OpenMath.parse(s; format = :json).object) == canonicalize(obj)
    end
end

@testitem "json writer: output is byte-stable after one round-trip" tags = [:unit, :json] begin
    using OpenMath
    for obj in (OMInteger(42), OMInteger(BigInt(2)^200), OMFloat(NaN), OMString("a\"b"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")))
        once = OpenMath.json(OMObject(obj))
        @test once == OpenMath.json(OpenMath.parse(once; format = :json))
    end
end

@testitem "json and xml agree on every object (P3)" tags = [:unit, :json] begin
    using OpenMath
    # The two encodings are independent implementations of the same grammar, so
    # agreement between them is a real check rather than a tautology.
    objects = [OMInteger(BigInt(2)^200), OMFloat(NaN), OMFloat(-0.0), OMString("a<b&c"),
        OMBytes(UInt8[0, 255]), OMVariable("λ"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")),
        OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")], OMVariable("x")),
        OMAttribution([OMAttributePair(OMSymbol("ecc", "t"), OMString("R"))],
            OMVariable("x"))]
    for obj in objects
        viaxml = OpenMath.parse(OpenMath.xml(OMObject(obj)); format = :xml)
        viajson = OpenMath.parse(OpenMath.json(OMObject(obj)); format = :json)
        @test canonicalize(viaxml) == canonicalize(viajson)
    end
end

@testitem "json writer: deep objects do not overflow the stack" tags = [:unit, :json, :slow] begin
    using OpenMath
    n = 200_000
    deep = foldl((a, _) -> OMSymbol("arith1", "plus")(a), 1:n; init = OMInteger(0))
    elapsed = @elapsed(s = with_limits(OMLimits(; max_depth = n + 10)) do
        OpenMath.json(OMObject(deep))
    end)
    @test occursin("\"integer\":0", s)
    @test elapsed < 60
end
