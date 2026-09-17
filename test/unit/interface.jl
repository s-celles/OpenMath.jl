# SPDX-License-Identifier: MIT
#
# REQ-CVT-001, REQ-CVT-002 — the conversion extension points.

@testitem "built-in scalar conversions" tags = [:unit, :convert] begin
    using OpenMath
    @test to_openmath(42) == OMInteger(42)
    @test to_openmath(BigInt(2)^100) == OMInteger(BigInt(2)^100)
    @test to_openmath(1.5) == OMFloat(1.5)
    @test to_openmath("hi") == OMString("hi")
    @test to_openmath(:x) == OMVariable("x")
    @test to_openmath(UInt8[1, 2]) == OMBytes(UInt8[1, 2])
end

@testitem "booleans map to logic1" tags = [:unit, :convert] begin
    using OpenMath
    @test to_openmath(true) == OMSymbol("logic1", "true")
    @test to_openmath(false) == OMSymbol("logic1", "false")
    @test from_openmath(to_openmath(true)) === true
end

@testitem "rationals and complexes map to nums1" tags = [:unit, :convert] begin
    using OpenMath
    @test to_openmath(3 // 4) ==
          OMApplication(OMSymbol("nums1", "rational"), [OMInteger(3), OMInteger(4)])
    @test to_openmath(complex(1.0, 2.0)) ==
          OMApplication(OMSymbol("nums1", "complex_cartesian"),
        [OMFloat(1.0), OMFloat(2.0)])
end

@testitem "vectors and matrices map to linalg2" tags = [:unit, :convert] begin
    using OpenMath
    v = to_openmath([1, 2, 3])
    @test v.applicant == OMSymbol("linalg2", "vector")
    @test v.arguments == OMNode[OMInteger(1), OMInteger(2), OMInteger(3)]

    m = to_openmath([1 2; 3 4])
    @test m.applicant == OMSymbol("linalg2", "matrix")
    @test length(m.arguments) == 2
    @test m.arguments[1].applicant == OMSymbol("linalg2", "matrixrow")
end

@testitem "special float values survive conversion" tags = [:unit, :convert] begin
    using OpenMath
    for x in (NaN, Inf, -Inf, 0.0, -0.0, 1e308, 5.0e-324)
        @test from_openmath(to_openmath(x)) === x
    end
end

@testitem "round-trip through the interface" tags = [:unit, :convert] begin
    using OpenMath
    for x in (0, 1, -1, typemax(Int64), BigInt(2)^200, "text", 3 // 4, [1, 2, 3])
        @test from_openmath(to_openmath(x)) == x
    end
end

@testitem "a user type extends to_openmath by dispatch" tags = [:unit, :convert] begin
    using OpenMath
    struct Point2D
        x::Float64
        y::Float64
    end
    OpenMath.to_openmath(p::Point2D) = OMSymbol("mycd", "point"; cdbase = "http://example.org/cd")(
        to_openmath(p.x), to_openmath(p.y))

    om = to_openmath(Point2D(1.0, 2.0))
    @test om isa OMApplication
    @test om.applicant.cdbase == "http://example.org/cd"
    @test om.arguments == OMNode[OMFloat(1.0), OMFloat(2.0)]
end

@testitem "unconvertible values raise a clear error" tags = [:unit, :convert] begin
    using OpenMath
    struct Unconvertible end
    e = try
        to_openmath(Unconvertible())
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathConversionError
    @test occursin("Unconvertible", sprint(showerror, e))
end
