# SPDX-License-Identifier: MIT
#
# REQ-BIN-001, REQ-BIN-003, REQ-BIN-005, REQ-BIN-006, REQ-BIN-008 — the binary
# reader (§3.2).
#
# The first test item is the one that matters. Every other encoding could be
# checked against something outside this repository — expat and the reference
# crate for XML, the standard's worked documents for JSON, the MathML 4 element
# table for Strict Content MathML. This one cannot: the reference crate declares
# the binary encoding TODO, and round-trip, idempotence and cross-encoding
# agreement are all satisfied *trivially* by a reader and a writer that share the
# same misunderstanding. The standard's own byte sequences are the entire
# external check, so they are asserted before anything else.

@testitem "binary: the standard's own byte sequences (REQ-BIN-001)" tags = [
    :unit, :binary] begin
    using OpenMath, TOML

    vectors = TOML.parsefile(joinpath(@__DIR__, "..", "corpus",
        "binary-vectors.toml"))["vector"]
    @test length(vectors) >= 12
    @test count(v -> haskey(v, "defect"), vectors) == 2

    for v in vectors
        bytes = hex2bytes(filter(!isspace, v["bytes"]))
        doc = v["kind"] == "document" ? bytes : vcat(UInt8[0x18], bytes, UInt8[0x19])
        if v["expect"] == "reject"
            @test_throws OpenMath.OpenMathParseError OpenMath.read_binary(doc)
        else
            want = include_string(Main, "let\n using OpenMath\n" * v["expect"] * "\nend")
            @test canonicalize(OpenMath.read_binary(doc).object) == canonicalize(want)
        end
    end
end

@testitem "binary: the OpenMath 1 sharing form is read, never written (REQ-BIN-008)" tags = [
    :unit, :binary] begin
    using OpenMath
    # [24] selects the deprecated per-kind tables of §3.2.4.1, where the sharing
    # flag means "back-reference into the table" rather than "will be referenced
    # later". This is the body of Figure 3.5, whose own header is wrong.
    doc = vcat(UInt8[0x18, 0x10],
        UInt8[0x08, 0x06, 0x05], Vector{UInt8}("arith1times"),
        UInt8[0x10],
        UInt8[0x08, 0x06, 0x04], Vector{UInt8}("arith1plus"),
        UInt8[0x05, 0x01, 0x78, 0x05, 0x01, 0x79, 0x11],
        UInt8[0x10, 0x48, 0x01, 0x45, 0x00, 0x05, 0x01, 0x7a, 0x11],
        UInt8[0x11, 0x19])
    want = OMS"arith1#times"(OMS"arith1#plus"(OMVariable("x"), OMVariable("y")),
        OMS"arith1#plus"(OMVariable("x"), OMVariable("z")))
    @test OpenMath.read_binary(doc).object == want
    # We emit [24] too — see D8 — but never its per-kind sharing tables: an
    # object needing no sharing is written with none, and one that does is
    # written [24+64].
    b = OpenMath.binary(OMObject(want))
    @test b[1] == 0x18
    @test !any(t -> t in (0x45, 0x46, 0x47, 0x48), b)

    # A back-reference to a table slot nothing has filled is an encoding error.
    @test_throws OpenMath.OpenMathParseError OpenMath.read_binary(
        UInt8[0x18, 0x48, 0x00, 0x19])
    # Strings share through their own table, and the two widths are separate
    # kinds — "Strings with 8 bit characters and strings with 16 bit characters
    # are two different kinds of objects for this sharing."
    doc = vcat(UInt8[0x18, 0x10, 0x05, 0x01, 0x66],
        UInt8[0x06, 0x01], Vector{UInt8}("a"),
        UInt8[0x07, 0x01, 0x03, 0xbb],
        UInt8[0x46, 0x00], UInt8[0x47, 0x00], UInt8[0x11, 0x19])
    got = OpenMath.read_binary(doc).object
    @test got.arguments == OMNode[OMString("a"), OMString("λ"),
        OMString("a"), OMString("λ")]
    # The OpenMath 2 reference tokens do not exist in that dialect.
    @test_throws OpenMath.OpenMathParseError OpenMath.read_binary(
        UInt8[0x18, 0x10, 0x05, 0x01, 0x66, 0x05, 0x01, 0x61, 0x1e, 0x00, 0x11, 0x19])
end

@testitem "binary: streamed packets are read (REQ-BIN-001)" tags = [:unit, :binary] begin
    using OpenMath
    # §3.2.2: bit 6 marks a non-final packet of a basic object. We never write
    # them — splitting is the producer's choice — but a reader that chokes on
    # them is not a reader of this encoding.

    # Figure 3.4: a big integer split into packets of 255, 255 and 68 digits.
    digits = string(big(10)^577 + 12345)
    @test length(digits) == 578
    doc = vcat(UInt8[0x18],
        UInt8[0x22, 0xff, 0x2b], Vector{UInt8}(digits[1:255]),
        UInt8[0x22, 0xff, 0x2b], Vector{UInt8}(digits[256:510]),
        UInt8[0x02, 0x44, 0x2b], Vector{UInt8}(digits[511:578]),
        UInt8[0x19])
    @test OpenMath.read_binary(doc).object == OMInteger(Base.parse(BigInt, digits))

    # "only the sequence-initial packet may contain a signed integer"
    neg = vcat(UInt8[0x18], UInt8[0x22, 0x03, 0x2d], Vector{UInt8}("123"),
        UInt8[0x02, 0x03, 0x2b], Vector{UInt8}("456"), UInt8[0x19])
    @test OpenMath.read_binary(neg).object == OMInteger(-123456)

    # Strings, byte arrays and foreign objects concatenate.
    @test OpenMath.read_binary(vcat(UInt8[0x18, 0x26, 0x02], Vector{UInt8}("ab"),
        UInt8[0x06, 0x01], Vector{UInt8}("c"), UInt8[0x19])).object == OMString("abc")
    @test OpenMath.read_binary(UInt8[0x18, 0x24, 0x02, 0x01, 0x02,
        0x04, 0x01, 0x03, 0x19]).object == OMBytes(UInt8[1, 2, 3])

    # "all packets making up a basic object must have the same token identifier"
    @test_throws OpenMath.OpenMathParseError OpenMath.read_binary(
        vcat(UInt8[0x18, 0x26, 0x02], Vector{UInt8}("ab"),
        UInt8[0x04, 0x01, 0x03], UInt8[0x19]))
    # A stream that never ends is a truncation, not a hang.
    @test_throws OpenMath.OpenMathParseError OpenMath.read_binary(
        vcat(UInt8[0x18, 0x26, 0x02], Vector{UInt8}("ab")))
end

@testitem "binary: all three integer bases are read" tags = [:unit, :binary] begin
    using OpenMath
    frag(b) = OpenMath.read_binary(vcat(UInt8[0x18], b, UInt8[0x19])).object
    @test frag(vcat(UInt8[0x02, 0x03, 0x2b], Vector{UInt8}("255"))) == OMInteger(255)
    @test frag(vcat(UInt8[0x02, 0x02, 0x6b], Vector{UInt8}("ff"))) == OMInteger(255)
    @test frag(vcat(UInt8[0x02, 0x02, 0x6b], Vector{UInt8}("FF"))) == OMInteger(255)
    @test frag(UInt8[0x02, 0x01, 0xab, 0xff]) == OMInteger(255)
    @test frag(vcat(UInt8[0x02, 0x03, 0x2d], Vector{UInt8}("255"))) == OMInteger(-255)
    @test frag(UInt8[0x02, 0x00, 0x2b]) == OMInteger(0)
    # "it is permitted to encode a 'small' integer in any 'bigger' format"
    @test frag(vcat(UInt8[0x02, 0x02, 0x2b], Vector{UInt8}("16"))) == OMInteger(16)
    @test frag(UInt8[0x81, 0x00, 0x00, 0x00, 0x10]) == OMInteger(16)
end

@testitem "binary: reading consumes one object and no more (REQ-BIN-003)" tags = [
    :unit, :binary] begin
    using OpenMath
    # The reader works over an IO and stops on the end-object token, leaving the
    # rest of the stream untouched. That is what makes it usable on a socket
    # carrying a sequence of objects, which is how SCSCP uses this encoding.
    obj = OMObject(OMS"arith1#plus"(OMInteger(1), OMVariable("x")))
    b = OpenMath.binary(obj)
    io = IOBuffer(vcat(b, b, Vector{UInt8}("trailing")))
    @test read_binary(io) == obj
    @test read_binary(io) == obj
    @test read(io, String) == "trailing"

    # Given a byte vector, by contrast, the whole of it must be the document:
    # there is no second reader to hand the remainder to.
    @test_throws OpenMath.OpenMathParseError OpenMath.read_binary(vcat(b, b))
end

@testitem "binary: malformed input is rejected, never guessed (REQ-BIN-005)" tags = [
    :unit, :binary] begin
    using OpenMath
    bad = [
        UInt8[],                                  # empty
        UInt8[0x01, 0x10],                        # no document tag
        UInt8[0x18],                              # truncated after the tag
        UInt8[0x18, 0x01],                        # truncated inside an integer
        UInt8[0x18, 0x01, 0x10],                  # missing the end tag
        UInt8[0x58, 0x02],                        # truncated in the version bytes
        UInt8[0x18, 0x10, 0x11, 0x19],            # application with no applicant
        UInt8[0x18, 0x0b, 0x19],                  # token 11 is unassigned
        UInt8[0x18, 0x19],                        # an object with no content
        UInt8[0x18, 0x16, 0x05, 0x01, 0x78, 0x17, 0x19],     # error head not a symbol
        UInt8[0x18, 0x1a, 0x05, 0x01, 0x66, 0x1c, 0x01, 0x10, 0x1d,
            0x05, 0x01, 0x78, 0x1b, 0x19],        # a bound "variable" that is an OMI
        UInt8[0x18, 0x12, 0x14, 0x05, 0x01, 0x78, 0x01, 0x10, 0x15,
            0x01, 0x10, 0x13, 0x19],              # attribute key not a symbol
        UInt8[0x58, 0x02, 0x00, 0x1e, 0x00, 0x19],           # reference to nothing
        UInt8[0x58, 0x02, 0x00, 0x06, 0x02, 0x61, 0x19],     # length past the end
        UInt8[0x18, 0x05, 0x01, 0x20, 0x19],      # " " is not a Name (§2.3)
        UInt8[0x18, 0x08, 0x01, 0x01, 0x20, 0x78, 0x19],     # nor is it a cd name
        UInt8[0x18, 0x02, 0x02, 0x2b, 0x39, 0x41, 0x19],     # 'A' is no base-10 digit
        UInt8[0x18, 0x02, 0x01, 0xeb, 0x39, 0x19],           # 0xC0 is no base mask
        UInt8[0x18, 0x02, 0x01, 0x3b, 0x39, 0x19],           # ';' is not a sign
        UInt8[0x18, 0x09, 0x04, 0x3a, 0x2f, 0x2f, 0x61, 0x01, 0x10, 0x19],  # bad cdbase
        UInt8[0x18, 0x07, 0x01, 0xd8, 0x35, 0x19]            # a lone UTF-16 surrogate
    ]
    for doc in bad
        e = try
            OpenMath.read_binary(doc)
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathParseError
    end
    # The offset is reported, since "byte 6" is the only locator a binary stream
    # has (REQ-BIN-005).
    e = try
        OpenMath.read_binary(UInt8[0x18, 0x06, 0x02, 0x61])
    catch err
        err
    end
    @test e.offset !== nothing
end

@testitem "binary: a declared length is checked before it is allocated (REQ-BIN-006)" tags = [
    :unit, :binary] begin
    using OpenMath
    # 0x84 is the long-form byte array tag; the four bytes that follow claim four
    # gigabytes. The budget must be consulted first — a reader that allocates and
    # then discovers the input is six bytes long is a denial of service.
    @test_throws OpenMath.OpenMathLimitError OpenMath.read_binary(
        UInt8[0x18, 0x84, 0xff, 0xff, 0xff, 0xff, 0x19])
    @test_throws OpenMath.OpenMathLimitError OpenMath.read_binary(
        IOBuffer(UInt8[0x18, 0x86, 0x7f, 0xff, 0xff, 0xff, 0x19]))
    @test with_limits(OMLimits(; max_bytes = 8)) do
        try
            OpenMath.read_binary(vcat(UInt8[0x18, 0x06, 0x10],
                Vector{UInt8}(repeat("a", 16)), UInt8[0x19]))
            false
        catch e
            e isa OpenMath.OpenMathLimitError
        end
    end
end

@testitem "binary: limits bound a hostile document (REQ-BIN-006)" tags = [
    :unit, :binary] begin
    using OpenMath
    deep = vcat(UInt8[0x18], fill(0x10, 50), UInt8[0x05, 0x01, 0x78],
        fill(0x11, 50), UInt8[0x19])
    @test OpenMath.read_binary(deep) isa OMObject
    @test with_limits(OMLimits(; max_depth = 10)) do
        try
            OpenMath.read_binary(deep)
            false
        catch e
            e isa OpenMath.OpenMathLimitError
        end
    end
    @test with_limits(OMLimits(; max_nodes = 10)) do
        try
            OpenMath.read_binary(deep)
            false
        catch e
            e isa OpenMath.OpenMathLimitError
        end
    end
end

@testitem "binary: the public entry points (REQ-BIN-002)" tags = [:unit, :binary] begin
    using OpenMath
    obj = OMObject(OMInteger(1))
    b = OpenMath.binary(obj)
    @test OpenMath.parse(b) == obj
    @test OpenMath.parse(b; format = :binary) == obj
    @test OpenMath.sniff_format(b) === :binary
    @test OpenMath.sniff_format(String(copy(b))) === :binary
    # The binary MIME type is not a text one, so `repr` hands back bytes.
    @test !istextmime(MIME("application/openmath+binary"))
    @test repr(MIME("application/openmath+binary"), obj) == b

    io = IOBuffer()
    @test write_binary(io, obj) == length(b)
    @test take!(io) == b

    mktemp() do path, handle
        write(handle, b)
        close(handle)
        @test OpenMath.parsefile(path) == obj
    end
end
