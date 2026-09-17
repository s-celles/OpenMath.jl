# SPDX-License-Identifier: MIT
#
# REQ-JSN-001, REQ-JSN-004, REQ-JSN-005, REQ-API-002, REQ-API-007, REQ-SEC-001,
# REQ-SEC-002 — the JSON reader (standard §3.3).

@testitem "json reader: every leaf kind" tags = [:unit, :json] begin
    using OpenMath
    om(body) = OpenMath.parse("""{"kind":"OMOBJ","openmath":"2.0","object":$body}""").object

    @test om("""{"kind":"OMI","integer":42}""") == OMInteger(42)
    @test om("""{"kind":"OMI","integer":-7}""") == OMInteger(-7)
    @test om("""{"kind":"OMF","float":1.5}""") == OMFloat(1.5)
    @test om("""{"kind":"OMSTR","string":"hi"}""") == OMString("hi")
    @test om("""{"kind":"OMSTR","string":""}""") == OMString("")
    @test om("""{"kind":"OMV","name":"x"}""") == OMVariable("x")
    @test om("""{"kind":"OMS","cd":"arith1","name":"plus"}""") == OMSymbol("arith1", "plus")
    @test om("""{"kind":"OMR","href":"#a"}""") == OMReference("#a")
end

@testitem "json reader: the three OMI spellings (standard §3.3)" tags = [:unit, :json] begin
    using OpenMath
    om(body) = OpenMath.parse("""{"kind":"OMOBJ","object":$body}""").object

    @test om("""{"kind":"OMI","integer":42}""") == OMInteger(42)
    @test om("""{"kind":"OMI","decimal":"-120"}""") == OMInteger(-120)
    @test om("""{"kind":"OMI","hexadecimal":"-x78"}""") == OMInteger(-120)
    @test om("""{"kind":"OMI","hexadecimal":"x1F"}""") == OMInteger(31)

    # Precision is the point of `decimal`: a value past 2^53 must survive exactly.
    big = BigInt(2)^200
    @test om("""{"kind":"OMI","decimal":"$big"}""") == OMInteger(big)
    # …and a JSON number that large must not be rounded through Float64 either.
    @test om("""{"kind":"OMI","integer":$big}""") == OMInteger(big)
    @test om("""{"kind":"OMI","integer":$(typemin(Int64))}""") == OMInteger(typemin(Int64))
end

@testitem "json reader: the three OMF spellings (standard §3.3)" tags = [:unit, :json] begin
    using OpenMath
    om(body) = OpenMath.parse("""{"kind":"OMOBJ","object":$body}""").object

    @test om("""{"kind":"OMF","float":1e-10}""") == OMFloat(1e-10)
    @test om("""{"kind":"OMF","decimal":"1.0e-10"}""") == OMFloat(1e-10)
    @test om("""{"kind":"OMF","hexadecimal":"3DDB7CDFD9D7BDBB"}""") ==
          OMFloat(reinterpret(Float64, 0x3DDB7CDFD9D7BDBB))
    # JSON has no NaN or Infinity literal, so `hexadecimal` is how they travel.
    @test om("""{"kind":"OMF","hexadecimal":"7FF8000000000000"}""") == OMFloat(NaN)
    @test om("""{"kind":"OMF","hexadecimal":"FFF0000000000000"}""") == OMFloat(-Inf)
    @test om("""{"kind":"OMF","hexadecimal":"8000000000000000"}""") == OMFloat(-0.0)
end

@testitem "json reader: OMB accepts bytes and base64 (REQ-JSN-004)" tags = [:unit, :json] begin
    using OpenMath
    om(body) = OpenMath.parse("""{"kind":"OMOBJ","object":$body}""").object

    @test om("""{"kind":"OMB","base64":"3q2+7w=="}""") ==
          OMBytes(UInt8[0xde, 0xad, 0xbe, 0xef])
    @test om("""{"kind":"OMB","bytes":[222,173,190,239]}""") ==
          OMBytes(UInt8[0xde, 0xad, 0xbe, 0xef])
    @test om("""{"kind":"OMB","bytes":[]}""") == OMBytes(UInt8[])
    @test om("""{"kind":"OMB","base64":""}""") == OMBytes(UInt8[])
end

@testitem "json reader: composites" tags = [:unit, :json] begin
    using OpenMath
    om(body) = OpenMath.parse("""{"kind":"OMOBJ","object":$body}""").object

    @test om("""{"kind":"OMA","applicant":{"kind":"OMS","cd":"arith1","name":"plus"},
                 "arguments":[{"kind":"OMI","integer":1},{"kind":"OMV","name":"x"}]}""") ==
          OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x"))

    # `arguments` is optional (standard §3.3).
    @test om("""{"kind":"OMA","applicant":{"kind":"OMS","cd":"a","name":"b"}}""") ==
          OMApplication(OMSymbol("a", "b"), OMNode[])

    @test om("""{"kind":"OMBIND","binder":{"kind":"OMS","cd":"fns1","name":"lambda"},
                 "variables":[{"kind":"OMV","name":"x"}],
                 "object":{"kind":"OMV","name":"x"}}""") ==
          OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")], OMVariable("x"))

    @test om("""{"kind":"OME","error":{"kind":"OMS","cd":"error1","name":"unhandled_symbol"},
                 "arguments":[{"kind":"OMI","integer":1}]}""") ==
          OMError(OMSymbol("error1", "unhandled_symbol"), OMOrForeign[OMInteger(1)])

    @test om("""{"kind":"OMATTR",
                 "attributes":[[{"kind":"OMS","cd":"ecc","name":"type"},
                                {"kind":"OMSTR","string":"R"}]],
                 "object":{"kind":"OMV","name":"x"}}""") ==
          OMAttribution([OMAttributePair(OMSymbol("ecc", "type"), OMString("R"))],
        OMVariable("x"))

    @test om("""{"kind":"OME","error":{"kind":"OMS","cd":"error1","name":"e"},
                 "arguments":[{"kind":"OMFOREIGN","encoding":"text/plain","foreign":"raw"}]}""").arguments[1] ==
          OMForeign("text/plain", "raw")
end

@testitem "json reader: cdbase, id and version" tags = [:unit, :json] begin
    using OpenMath
    o = OpenMath.parse("""{"kind":"OMOBJ","openmath":"2.0","cdbase":"http://example.org/cd",
        "object":{"kind":"OMA","id":"n1","applicant":{"kind":"OMS","cd":"mycd","name":"f"},
                  "arguments":[{"kind":"OMI","id":"n2","integer":1}]}}""")
    @test o.version == "2.0"
    @test o.cdbase == "http://example.org/cd"
    @test o.object.id == "n1"
    @test o.object.arguments[1].id == "n2"

    s = OpenMath.parse("""{"kind":"OMOBJ","object":
        {"kind":"OMS","cdbase":"http://other.example/cd","cd":"a","name":"b"}}""").object
    @test s.cdbase == "http://other.example/cd"
end

@testitem "json reader: member order does not matter (REQ-JSN-005)" tags = [:unit, :json] begin
    using OpenMath
    a = OpenMath.parse("""{"kind":"OMOBJ","object":{"kind":"OMS","cd":"c","name":"n"}}""")
    b = OpenMath.parse("""{"object":{"name":"n","cd":"c","kind":"OMS"},"kind":"OMOBJ"}""")
    @test a.object == b.object
end

@testitem "json reader: escapes and Unicode" tags = [:unit, :json] begin
    using OpenMath
    om(body) = OpenMath.parse("""{"kind":"OMOBJ","object":$body}""").object

    @test om("""{"kind":"OMSTR","string":"a\\"b\\\\c\\/d"}""") == OMString("a\"b\\c/d")
    @test om("""{"kind":"OMSTR","string":"\\n\\t\\r\\b\\f"}""") == OMString("\n\t\r\b\f")
    @test om("""{"kind":"OMSTR","string":"\\u03bb"}""") == OMString("λ")
    # Surrogate pair for U+1D400 MATHEMATICAL BOLD CAPITAL A.
    @test om("""{"kind":"OMSTR","string":"\\ud835\\udc00"}""") == OMString("\U1D400")
    @test om("""{"kind":"OMSTR","string":"λ ℝ 変数"}""") == OMString("λ ℝ 変数")
end

@testitem "json reader: :auto sniffs JSON (REQ-API-002)" tags = [:unit, :json] begin
    using OpenMath
    @test OpenMath.parse("""  {"kind":"OMOBJ","object":{"kind":"OMI","integer":1}}""").object ==
          OMInteger(1)
    @test OpenMath.sniff_format("""{"kind":"OMOBJ"}""") === :json
end

@testitem "json reader: malformed input is rejected with an offset" tags = [:unit, :json] begin
    using OpenMath
    bad = ["""{"kind":"OMOBJ","object":{"kind":"OMNOPE"}}""",
        """{"kind":"OMOBJ","object":{"kind":"OMI"}}""",
        """{"kind":"OMOBJ","object":{"kind":"OMI","integer":1.5}}""",
        """{"kind":"OMOBJ","object":{"kind":"OMS","cd":"a"}}""",
        """{"kind":"OMOBJ","object":{"kind":"OMA"}}""",
        """{"kind":"OMOBJ","object":{"kind":"OME","error":{"kind":"OMI","integer":1}}}""",
        """{"kind":"OMOBJ","object":{"kind":"OMB","base64":"!!!!"}}""",
        """{"kind":"OMI","integer":1}""",
        """{"kind":"OMOBJ"}""",
        """{"kind":"OMOBJ","object":{"kind":"OMI","integer":1}""",
        """{"kind":"OMOBJ","object":}""",
        """[1,2,3]""",
        """{"kind":"OMOBJ","object":{"kind":"OMI","integer":01}}"""]
    for src in bad
        e = try
            OpenMath.parse(src; format = :json)
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathParseError
        @test e.offset isa Int || e.path !== nothing
    end
end

@testitem "json reader: depth is bounded (REQ-SEC-002)" tags = [:unit, :json] begin
    using OpenMath
    nest(n) = foldl(
        (acc, _) -> """{"kind":"OMA","applicant":{"kind":"OMS","cd":"a","name":"b"},
                        "arguments":[$acc]}""",
        1:n; init = """{"kind":"OMI","integer":0}""")
    deep = """{"kind":"OMOBJ","object":$(nest(200))}"""
    e = try
        with_limits(OMLimits(; max_depth = 20)) do
            OpenMath.parse(deep; format = :json)
        end
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathLimitError
    @test OpenMath.parse(deep; format = :json).object isa OMApplication
end

@testitem "json reader: never throws anything but OpenMathError (REQ-SEC-001)" tags = [
    :unit, :json] begin
    using OpenMath
    srcs = ["", "{", "}", "[", "{\"", "{\"a", "{\"a\":", "{\"a\":1", "null", "true",
        "1e999999999", "-", "0x1", "\"\\u\"", "\"\\ud800\"", "\"\\udc00\"",
        "\xff\xfe", "{\"kind\":}", "{\"kind\":\"OMI\",\"integer\":--1}",
        "[[[[[[[[[[", "{\"kind\":\"OMOBJ\",\"object\":null}"]
    for src in srcs
        r = try
            OpenMath.parse(src; format = :json)
            :ok
        catch err
            err isa OpenMath.OpenMathError ? :openmath_error : err
        end
        @test r === :ok || r === :openmath_error
    end
end

@testitem "json reader: a 200_000-deep document does not overflow the stack" tags = [
    :unit, :json, :slow] begin
    using OpenMath
    # The XML reader has had this test since E1 №1. The JSON reader had none, and
    # two defects survived in the gap: error paths built eagerly, allocating
    # O(depth) per node — the same quadratic shape that caused an out-of-memory
    # in the XML reader — and a *recursive* builder, where every other reader and
    # writer in this package uses an explicit stack. It is on a stack now.
    n = 200_000
    prefix = """{"kind":"OMA","applicant":{"kind":"OMV","name":"f"},"arguments":["""
    src = string("{\"kind\":\"OMOBJ\",\"object\":", prefix^n,
        """{"kind":"OMI","integer":0}""", "]}"^n, "}")

    # The budget is on *JSON* nesting, not OpenMath nesting: one OpenMath level
    # is an object inside an array inside an object, so the scanner sees more
    # levels than `depth` reports. That is right for a stack-safety ceiling, and
    # it does mean the same `max_depth` admits a shallower OpenMath object in
    # JSON than in XML, which is worth knowing when tuning it.
    elapsed = @elapsed(o = with_limits(OMLimits(; max_depth = 4n)) do
        OpenMath.parse(src; format = :json)
    end)
    @test depth(o.object) == n + 1

    # Parsing must be linear in depth. Depth is attacker-controlled, so quadratic
    # is a denial of service rather than a slow path. Loose on purpose: it catches
    # a change of order, not of constant factor.
    @test elapsed < 60
end
