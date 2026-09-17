# SPDX-License-Identifier: MIT
#
# REQ-XML-007 — the base64 codec used by OMB (standard §3.1.1). Property P6.

@testitem "base64: known vectors" tags = [:unit, :base64] begin
    using OpenMath: base64_encode, base64_decode
    vectors = [
        UInt8[] => "",
        b"f" => "Zg==",
        b"fo" => "Zm8=",
        b"foo" => "Zm9v",
        b"foob" => "Zm9vYg==",
        b"fooba" => "Zm9vYmE=",
        b"foobar" => "Zm9vYmFy",
        UInt8[0xde, 0xad, 0xbe, 0xef] => "3q2+7w==",
        UInt8[0x00] => "AA==",
        UInt8[0xff, 0xff, 0xff] => "////"
    ]
    for (bytes, text) in vectors
        @test base64_encode(collect(UInt8, bytes)) == text
        @test base64_decode(text) == collect(UInt8, bytes)
    end
end

@testitem "base64: whitespace in the encoded form is ignored" tags = [:unit, :base64] begin
    using OpenMath: base64_decode
    @test base64_decode("Zm9v YmFy") == collect(UInt8, b"foobar")
    @test base64_decode("Zm9v\n\tYmFy\r\n") == collect(UInt8, b"foobar")
    @test base64_decode("  ") == UInt8[]
end

@testitem "base64: invalid input is rejected with an offset" tags = [:unit, :base64] begin
    using OpenMath
    using OpenMath: base64_decode
    for bad in ("!!!!", "Zg=", "Zm9v=", "Zg===", "Z", "Zg==Zg==", "Zm8=x", "=Zm8")
        e = try
            base64_decode(bad)
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathParseError
        @test e.offset isa Int
    end
end

@testitem "base64: round-trip is the identity (P6)" tags = [:unit, :base64] begin
    using OpenMath: base64_encode, base64_decode
    using Random
    rng = Random.MersenneTwister(0x0f4a7)
    for n in 0:64
        b = rand(rng, UInt8, n)
        @test base64_decode(base64_encode(b)) == b
    end
    for _ in 1:200
        b = rand(rng, UInt8, rand(rng, 0:4096))
        @test base64_decode(base64_encode(b)) == b
    end
end

@testitem "base64: decoding never throws anything but OpenMathError" tags = [:unit, :base64] begin
    using OpenMath
    using OpenMath: base64_decode
    using Random
    rng = Random.MersenneTwister(1)
    alphabet = collect("ABCZaz09+/=\n \t!@é")
    for _ in 1:500
        s = String(rand(rng, alphabet, rand(rng, 0:12)))
        r = try
            base64_decode(s)
            :ok
        catch err
            err isa OpenMath.OpenMathError ? :openmath_error : err
        end
        @test r === :ok || r === :openmath_error
    end
end
