# SPDX-License-Identifier: MIT
#
# REQ-BIN-002, REQ-BIN-004, REQ-BIN-007, REQ-BIN-008 — the binary writer (§3.2).

@testitem "binary: leaves" tags = [:unit, :binary] begin
    using OpenMath
    # Drop the document tag — one byte for [24], three for [24+64] with its
    # version — and the end tag, leaving the encoding of the object itself.
    body(x) = (b = OpenMath.binary(OMObject(x)); b[(b[1] == 0x58 ? 4 : 2):(end - 1)])

    @test body(OMInteger(16)) == UInt8[0x01, 0x10]
    @test body(OMInteger(-16)) == UInt8[0x01, 0xf0]
    @test body(OMInteger(127)) == UInt8[0x01, 0x7f]
    @test body(OMInteger(128)) == UInt8[0x81, 0x00, 0x00, 0x00, 0x80]
    @test body(OMInteger(-129)) == UInt8[0x81, 0xff, 0xff, 0xff, 0x7f]
    @test body(OMVariable("x")) == UInt8[0x05, 0x01, 0x78]
    @test body(OMString("hi")) == UInt8[0x06, 0x02, 0x68, 0x69]
    @test body(OMBytes(UInt8[0xde, 0xad])) == UInt8[0x04, 0x02, 0xde, 0xad]
    @test body(OMFloat(1.0e-10)) == vcat(UInt8[0x03], hex2bytes("3ddb7cdfd9d7bdbb"))
    @test body(OMSymbol("arith1", "plus")) ==
          vcat(UInt8[0x08, 0x06, 0x04], Vector{UInt8}("arith1plus"))
end

@testitem "binary: the document tag is [24] unless [24+64] buys something (D8)" tags = [
    :unit, :binary] begin
    using OpenMath
    # §3.2.6 keeps [24] valid in OpenMath 2 — "the binary encoding tags without
    # the shared flag can still be used as more compact representations of the
    # objects (which are not shared, and do not have an identifier)" — and it is
    # what GAP, the only other shipping implementation, emits. [24+64] buys
    # exactly two things, so it is written for exactly those two.
    plain = OpenMath.binary(OMObject(OMInteger(1)))
    @test plain == UInt8[0x18, 0x01, 0x01, 0x19]
    @test OpenMath.read_binary(plain).version == "2.0"

    # 1. a version that only the two version bytes can carry
    versioned = OpenMath.binary(OMObject(OMInteger(1); version = "1.1"))
    @test versioned[1] == 0x58
    @test versioned[2:3] == UInt8[0x01, 0x01]
    @test OpenMath.read_binary(versioned).version == "1.1"

    # 2. structure sharing, which exists only under [24+64] (§3.2.4.2)
    inner = OMApplication(OMVariable("f"), [OMVariable("a")]; id = "t")
    shared = OpenMath.binary(OMObject(OMApplication(OMVariable("f"),
        [inner, OMReference("#t")])))
    @test shared[1] == 0x58
    @test shared[2:3] == UInt8[0x02, 0x00]

    # An id nothing refers to buys nothing, so it does not force [24+64].
    @test OpenMath.binary(OMObject(OMInteger(1; id = "unused")))[1] == 0x18
end

@testitem "binary: strings are LATIN-1 or UTF-16, never UTF-8" tags = [:unit, :binary] begin
    using OpenMath
    body(x) = (b = OpenMath.binary(OMObject(x)); b[(b[1] == 0x58 ? 4 : 2):(end - 1)])

    # §3.2.2 gives exactly two string tokens: 6 for ISO-8859-1 and 7 for UTF-16.
    # There is no UTF-8 string token, so a writer has to choose per string.
    @test body(OMString("e")) == UInt8[0x06, 0x01, 0x65]
    @test body(OMString("é")) == UInt8[0x06, 0x01, 0xe9]        # U+00E9 fits LATIN-1
    @test body(OMString("λ")) == UInt8[0x07, 0x01, 0x03, 0xbb]  # U+03BB does not
    # Beyond the BMP: one character, two UTF-16 units, and the length counts units.
    @test body(OMString("𝕏")) == UInt8[0x07, 0x02, 0xd8, 0x35, 0xdd, 0x4f]
    @test body(OMString("")) == UInt8[0x06, 0x00]

    for s in ("", "e", "é", "λ", "𝕏", "a<b&c", "ÿ", repeat("é", 300), repeat("λ", 300))
        @test OpenMath.read_binary(OpenMath.binary(OMObject(OMString(s)))).object ==
              OMString(s)
    end
end

@testitem "binary: integers of every size (REQ-BIN-007)" tags = [:unit, :binary] begin
    using OpenMath
    body(x) = (b = OpenMath.binary(OMObject(OMInteger(x)));
        b[(b[1] == 0x58 ? 4 : 2):(end - 1)])

    # The general form: big integer tag, length, sign/base byte, digits. Of the
    # three bases §3.2.2 allows we write base 10 — not the densest, but the only
    # one any shipping implementation *writes*, so the only one whose reader is
    # exercised by someone else's round trips. See D9 in the design notes.
    @test body(big(2)^200)[1] == 0x02
    @test body(big(2)^200)[2] == 0x3d           # 61 decimal digits
    @test body(big(2)^200)[3] == 0x2b           # '+' | the base-10 mask (0)
    @test body(-big(2)^200)[3] == 0x2d          # '-' | the base-10 mask
    @test String(body(big(2)^200)[4:end]) == string(big(2)^200)

    for v in (0, 1, -1, 127, -128, 128, -129, typemax(Int32), typemin(Int32),
        Int64(typemax(Int32)) + 1, Int64(typemin(Int32)) - 1,
        typemax(Int64), typemin(Int64), big(2)^200, -big(2)^200, big(10)^400)
        @test OpenMath.read_binary(OpenMath.binary(OMObject(OMInteger(v)))).object ==
              OMInteger(v)
    end
end

@testitem "binary: long forms past 255 bytes" tags = [:unit, :binary] begin
    using OpenMath
    body(x) = (b = OpenMath.binary(OMObject(x)); b[(b[1] == 0x58 ? 4 : 2):(end - 1)])

    # "the long flag set if the number of bytes … is greater than or equal to 256"
    @test body(OMString(repeat("a", 255)))[1] == 0x06
    @test body(OMString(repeat("a", 256)))[1] == 0x86
    @test body(OMString(repeat("a", 256)))[2:5] == UInt8[0x00, 0x00, 0x01, 0x00]
    @test body(OMBytes(zeros(UInt8, 255)))[1] == 0x04
    @test body(OMBytes(zeros(UInt8, 256)))[1] == 0x84
    @test body(OMVariable(repeat("a", 256)))[1] == 0x85
    @test body(OMSymbol("cd", repeat("a", 256)))[1] == 0x88

    for x in (OMString(repeat("a", 70000)), OMBytes(rand(UInt8, 70000)),
        OMVariable(repeat("v", 300)), OMSymbol(repeat("c", 300), repeat("n", 300)))
        @test OpenMath.read_binary(OpenMath.binary(OMObject(x))).object == x
    end
end

@testitem "binary: composites" tags = [:unit, :binary] begin
    using OpenMath
    body(x) = (b = OpenMath.binary(OMObject(x)); b[(b[1] == 0x58 ? 4 : 2):(end - 1)])

    @test body(OMApplication(OMVariable("f"), [OMVariable("x")])) ==
          UInt8[0x10, 0x05, 0x01, 0x66, 0x05, 0x01, 0x78, 0x11]

    b = body(OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")], OMVariable("x")))
    @test b[1] == 0x1a && b[end] == 0x1b        # [26] … [27]
    @test 0x1c in b && 0x1d in b                # [28] … [29] around the variables

    b = body(OMAttribution([OMAttributePair(OMS"ecc#type", OMString("R"))],
        OMVariable("x")))
    @test b[1] == 0x12 && b[2] == 0x14 && b[end] == 0x13   # [18] [20] … [19]

    b = body(OMError(OMS"error1#unhandled", OMOrForeign[OMInteger(1)]))
    @test b[1] == 0x16 && b[end] == 0x17        # [22] … [23]
end

@testitem "binary: cdbase is a scoping token, not an attribute" tags = [:unit, :binary] begin
    using OpenMath
    body(x) = (b = OpenMath.binary(OMObject(x)); b[(b[1] == 0x58 ? 4 : 2):(end - 1)])

    # The binary encoding has no cdbase attribute anywhere; §3.2.2 gives token 9,
    # which scopes over exactly one following object. The default base is the
    # OpenMath one, so an ordinary symbol needs no scope at all.
    @test !(0x09 in body(OMS"arith1#plus"))
    @test !(0x09 in body(resolve_cdbase(OMS"arith1#plus")))

    other = OMSymbol("mycd", "f"; cdbase = "http://example.org/cd")
    b = body(other)
    @test b[1] == 0x09
    @test b[2] == 0x15                          # 21 bytes of URI
    @test String(b[3:23]) == "http://example.org/cd"

    for x in (OMObject(other), OMObject(OMApplication(other, [OMInteger(1)])),
        OMObject(OMApplication(OMS"arith1#plus", [other])),
        OMObject(OMS"mycd#f"; cdbase = "http://example.org/cd"),
        OMObject(OMApplication(OMS"mycd#f", [OMS"mycd#g"];
        cdbase = "http://example.org/cd")))
        @test canonicalize(OpenMath.read_binary(OpenMath.binary(x))) == canonicalize(x)
    end
end

@testitem "binary: structure sharing (REQ-BIN-004)" tags = [:unit, :binary] begin
    using OpenMath
    inner = OMApplication(OMVariable("f"), [OMVariable("a"), OMVariable("a")];
        id = "t11")
    t1 = OMApplication(OMVariable("f"), [inner, OMReference("#t11")]; id = "t1")
    obj = OMObject(OMApplication(OMVariable("f"), [t1, OMReference("#t1")]))

    b = OpenMath.binary(obj)
    # The two referenced applications carry [16+64]; the two references are [30].
    @test count(==(0x50), b) == 2
    @test count(==(0x1e), b) == 2
    # This is Figure 3.6 of the standard, with its byte 27 corrected from 0x00 to
    # 0x01; see test/corpus/binary-vectors.toml.
    @test b == hex2bytes("580200100501665005016650050166050161050161111e00111e011119")

    # Reading gives the same object back. The `id` strings do not survive:
    # §3.2.4.2 references by ordinal, and the standard says as much — "in the
    # conversion from the XML to the binary encoding the identifiers on the
    # objects are not preserved".
    back = OpenMath.read_binary(b)
    @test expand_references(back) == expand_references(obj)
    @test canonicalize(back) == canonicalize(obj)

    # An id nothing refers to costs nothing and is simply dropped.
    @test OpenMath.binary(OMObject(OMInteger(1; id = "unused"))) ==
          OpenMath.binary(OMObject(OMInteger(1)))
end

@testitem "binary: external references are a separate token" tags = [:unit, :binary] begin
    using OpenMath
    # Tokens 30 and 31 exist precisely because an internal and an external
    # reference are not the same thing (§3.2.2).
    r = OMReference("http://example.org/doc#x")
    b = OpenMath.binary(OMObject(r))
    @test b[2] == 0x1f
    @test OpenMath.read_binary(b).object == r

    long = OMReference(repeat("http://example.org/", 20))
    @test OpenMath.binary(OMObject(long))[2] == 0x9f
    @test OpenMath.read_binary(OpenMath.binary(OMObject(long))).object == long
end

@testitem "binary: a forward reference is refused, not silently expanded" tags = [
    :unit, :binary] begin
    using OpenMath
    # §3.2.5: "It is an encoding error if the i-th position in the table has not
    # already been assigned (i.e. forward references are not allowed)." The XML
    # encoding permits this order, the binary encoding cannot express it, and
    # quietly inlining the target would change the size of the output by orders
    # of magnitude without saying so.
    obj = OMObject(OMApplication(OMVariable("f"),
        [OMReference("#a"), OMInteger(1; id = "a")]))
    @test_throws OpenMath.OpenMathConversionError OpenMath.binary(obj)
    @test OpenMath.binary(expand_references(obj)) isa Vector{UInt8}

    # A dangling internal reference is a different fault, and keeps its own error.
    @test_throws OpenMath.OpenMathReferenceError OpenMath.binary(
        OMObject(OMReference("#nope")))
end

@testitem "binary: foreign objects carry their encoding and payload" tags = [
    :unit, :binary] begin
    using OpenMath
    for f in (OMForeign("text/plain", "1 + 1"), OMForeign(nothing, "<mi>x</mi>"),
        OMForeign("text/plain", repeat("λ", 300)))
        obj = OMObject(OMError(OMS"error1#unhandled", OMOrForeign[f]))
        @test OpenMath.read_binary(OpenMath.binary(obj)).object.arguments[1] == f
    end
end

@testitem "binary: round-trip and idempotence" tags = [:unit, :binary] begin
    using OpenMath
    objects = [
        OMInteger(0), OMInteger(-1), OMInteger(big(2)^200), OMInteger(typemin(Int64)),
        OMFloat(NaN), OMFloat(-0.0), OMFloat(1e308), OMFloat(5.0e-324), OMFloat(Inf),
        OMString(""), OMString("a<b&c"), OMString("λ ℝ"), OMString("𝕏"),
        OMBytes(UInt8[]), OMBytes(UInt8[0, 1, 255]), OMVariable("λ"),
        OMSymbol("arith1", "plus"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")),
        OMBinding(OMS"fns1#lambda",
            [OMBoundVariable("x"), OMBoundVariable("y")], OMVariable("x")),
        OMBinding(OMS"fns1#lambda",
            [OMBoundVariable("x", [OMAttributePair(OMS"ecc#type", OMString("R"))])],
            OMVariable("x")),
        OMError(OMS"error1#e", OMOrForeign[OMInteger(1)]),
        OMAttribution([OMAttributePair(OMS"ecc#t", OMString("R"))], OMVariable("x")),
        OMApplication(OMSymbol("mycd", "f"; cdbase = "http://example.org/cd"),
            [OMInteger(1)])
    ]
    for obj in objects
        once = OpenMath.binary(OMObject(obj))
        back = OpenMath.read_binary(once)
        @test canonicalize(back.object) == canonicalize(obj)
        @test OpenMath.binary(back) == once
    end
end

@testitem "binary: the four encodings agree" tags = [:unit, :binary] begin
    using OpenMath
    # Four independent implementations of one grammar. Agreement is worth
    # something only because none of them shares code with the others.
    for obj in (OMInteger(big(2)^200), OMFloat(NaN), OMString("a<b&c"),
        OMBytes(UInt8[0, 255]), OMVariable("λ"),
        OMSymbol("arith1", "plus")(OMInteger(1), OMVariable("x")),
        OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")], OMVariable("x")))
        x = canonicalize(OpenMath.parse(OpenMath.xml(OMObject(obj)); format = :xml))
        j = canonicalize(OpenMath.parse(OpenMath.json(OMObject(obj)); format = :json))
        m = canonicalize(OpenMath.parse(OpenMath.mathml(OMObject(obj)); format = :mathml))
        b = canonicalize(OpenMath.read_binary(OpenMath.binary(OMObject(obj))))
        @test x == j
        @test x == m
        @test x == b
    end
end

@testitem "binary: depth is bounded on write" tags = [:unit, :binary] begin
    using OpenMath
    nest(n) = foldl((acc, _) -> OMApplication(OMVariable("f"), [acc]), 1:n;
        init = OMInteger(1))
    @test_throws OpenMath.OpenMathLimitError with_limits(OMLimits(; max_depth = 10)) do
        OpenMath.binary(OMObject(nest(50)))
    end
end
