# SPDX-License-Identifier: MIT
#
# REQ-OM-006, REQ-OM-007 — OpenMath `Name` production (standard §2.3).

@testitem "isvalidname accepts the Name production" tags = [:unit, :names] begin
    using OpenMath: isvalidname
    # NameStartChar: letters, '_', ':' — then NameChar adds '-', '.', digits.
    for n in ("plus", "x", "_private", "a-b", "a.b", "x0", "ns:local", "A", "_",
        "λ", "ℝ", "Ω", "É", "变量")
        @test isvalidname(n)
    end
end

@testitem "isvalidname rejects non-Names" tags = [:unit, :names] begin
    using OpenMath: isvalidname
    @test !isvalidname("")            # empty
    @test !isvalidname("0abc")        # digit is NameChar but not NameStartChar
    @test !isvalidname("-abc")        # '-' likewise
    @test !isvalidname(".abc")
    @test !isvalidname("a b")         # space is neither
    @test !isvalidname("a\tb")
    @test !isvalidname("a×b")         # U+00D7 sits in the [#xD7] gap of NameStartChar
    @test !isvalidname("a<b")
    @test !isvalidname("plus\n")
end

@testitem "checkname reports the offending position" tags = [:unit, :names] begin
    using OpenMath: checkname, OpenMathNameError
    e = try
        checkname("a b", "symbol name")
        nothing
    catch err
        err
    end
    @test e isa OpenMathNameError
    @test e.position == 2
    @test occursin("symbol name", sprint(showerror, e))

    e2 = try
        checkname("", "variable name")
        nothing
    catch err
        err
    end
    @test e2 isa OpenMathNameError
    @test e2.position == 0
end

@testitem "constructors validate names" tags = [:unit, :names] begin
    using OpenMath
    @test_throws OpenMath.OpenMathNameError OMSymbol("arith1", "0bad")
    @test_throws OpenMath.OpenMathNameError OMSymbol("0bad", "plus")
    @test_throws OpenMath.OpenMathNameError OMVariable("has space")
    @test OMSymbol("arith1", "plus") isa OMSymbol
end

@testitem "cdbase URI syntax is checked" tags = [:unit, :names] begin
    using OpenMath: isvalidcdbase
    @test isvalidcdbase("http://www.openmath.org/cd")
    @test isvalidcdbase("https://example.org/cd/x")
    @test isvalidcdbase("urn:example:cd")
    @test !isvalidcdbase("")
    @test !isvalidcdbase("not a uri")
    @test !isvalidcdbase("/relative/only")
end
