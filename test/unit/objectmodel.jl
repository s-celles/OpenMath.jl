# SPDX-License-Identifier: MIT
#
# REQ-OM-001..005, REQ-OM-008..010 — object model, equality, traversal, sugar.

@testitem "every OpenMath kind has a concrete type" tags = [:unit, :model] begin
    using OpenMath
    kinds = Dict(
        OMInteger(1) => :OMI,
        OMFloat(1.0) => :OMF,
        OMString("s") => :OMSTR,
        OMBytes(UInt8[1, 2]) => :OMB,
        OMVariable("x") => :OMV,
        OMSymbol("arith1", "plus") => :OMS,
        OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1)]) => :OMA,
        OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")], OMVariable("x")) =>
            :OMBIND,
        OMError(OMSymbol("error1", "unhandled_symbol"), OMOrForeign[]) => :OME,
        OMAttribution([OMAttributePair(OMSymbol("ecc", "type"), OMString("t"))], OMInteger(1)) =>
            :OMATTR,
        OMForeign("text/plain", "raw") => :OMFOREIGN,
        OMReference("#anchor") => :OMR
    )
    for (node, k) in kinds
        # OMForeign is deliberately not an OMNode: foreign content is not an
        # OpenMath object (see src/types.jl and test/unit/unrepresentable.jl).
        @test node isa OMOrForeign
        @test (node isa OMNode) == !(node isa OMForeign)
        @test kind(node) === k
    end
    @test length(unique(typeof.(keys(kinds)))) == 12
end

@testitem "OMInteger carries unbounded magnitude" tags = [:unit, :model] begin
    using OpenMath
    big = BigInt(2)^200 + 1
    @test OMInteger(big).value == big
    @test OMInteger(typemax(Int64)).value == typemax(Int64)
    # Int64 and BigInt spellings of the same value are the same object.
    @test OMInteger(5) == OMInteger(BigInt(5))
    @test hash(OMInteger(5)) == hash(OMInteger(BigInt(5)))
end

@testitem "structural equality ignores id" tags = [:unit, :model] begin
    using OpenMath
    a = OMInteger(42; id = "n1")
    b = OMInteger(42; id = "n2")
    c = OMInteger(42)
    @test a == b == c
    @test hash(a) == hash(b) == hash(c)
    @test !isequal_with_ids(a, b)
    @test isequal_with_ids(a, OMInteger(42; id = "n1"))
end

@testitem "OMFloat equality follows isequal, not ==" tags = [:unit, :model] begin
    using OpenMath
    # NaN must compare equal to itself: the hex encoding distinguishes bit patterns,
    # so the object model has to as well.
    @test OMFloat(NaN) == OMFloat(NaN)
    @test hash(OMFloat(NaN)) == hash(OMFloat(NaN))
    # +0.0 and -0.0 are distinct bit patterns and must not collapse.
    @test OMFloat(0.0) != OMFloat(-0.0)
    @test OMFloat(Inf) == OMFloat(Inf)
    @test OMFloat(Inf) != OMFloat(-Inf)
end

@testitem "variable names are Strings, never interned Symbols" tags = [:unit, :model] begin
    using OpenMath
    # Julia never garbage-collects Symbols, so interning attacker-controlled names
    # from a parsed document would be an unbounded memory leak (REQ-SEC-001).
    @test fieldtype(OMVariable, :name) === String
    @test fieldtype(OMSymbol, :name) === String
    @test fieldtype(OMSymbol, :cd) === String
end

@testitem "traversal exposes children uniformly" tags = [:unit, :model] begin
    using OpenMath
    f = OMSymbol("arith1", "plus")
    a = OMApplication(f, [OMInteger(1), OMVariable("x")])
    @test children(a) == OMNode[f, OMInteger(1), OMVariable("x")]
    @test isempty(children(OMInteger(1)))

    seen = Symbol[]
    walk(n -> push!(seen, kind(n)), a)
    @test seen == [:OMA, :OMS, :OMI, :OMV]
end

@testitem "walk uses an explicit stack, not native recursion" tags = [:unit, :model] begin
    using OpenMath
    # 200_000 levels would blow the native stack; an explicit stack must survive.
    # Built in a function: at test-module top level a `for`-loop assignment would
    # create a new soft-scope local instead of updating the binding.
    nest(n) = foldl((acc, _) -> OMApplication(OMSymbol("arith1", "plus"), [acc]),
        1:n; init = OMInteger(0))
    n = Ref(0)
    walk(_ -> (n[] += 1), nest(200_000))
    @test n[] == 400_001   # 200_000 × (OMA + OMS) + the leaf
end

@testitem "OMSymbol is callable and builds an application" tags = [:unit, :model] begin
    using OpenMath
    plus = OMSymbol("arith1", "plus")
    e = plus(OMInteger(1), OMVariable("x"))
    @test e isa OMApplication
    @test e.applicant == plus
    @test e.arguments == OMNode[OMInteger(1), OMVariable("x")]
end

@testitem "OMS string macro validates at expansion time" tags = [:unit, :model] begin
    using OpenMath
    @test OMS"arith1#plus" == OMSymbol("arith1", "plus")
    @test OMS"http://example.org/cd#mycd#sym" ==
          OMSymbol("mycd", "sym"; cdbase = "http://example.org/cd")
    @test_throws LoadError @eval OMS"nohash"
end

@testitem "OMObject wraps a root object" tags = [:unit, :model] begin
    using OpenMath
    o = OMObject(OMInteger(1))
    @test o.object == OMInteger(1)
    @test o.version == "2.0"
    @test o.cdbase === nothing
    @test OMObject(OMInteger(1); cdbase = "http://example.org/cd").cdbase ==
          "http://example.org/cd"
end

@testitem "string macros parse at expansion time (REQ-OM-010)" tags = [:unit, :model] begin
    using OpenMath
    # The literal is decoded when the surrounding code is compiled, so a typo in an
    # embedded document is a compile error rather than a runtime surprise.
    @test om"""<OMOBJ xmlns="http://www.openmath.org/OpenMath"><OMI>1</OMI></OMOBJ>""" ==
          OMObject(OMInteger(1))
    @test om"""{"kind":"OMOBJ","object":{"kind":"OMI","integer":1}}""" ==
          OMObject(OMInteger(1))
    @test omxml"""<OMOBJ xmlns="http://www.openmath.org/OpenMath"><OMV name="x"/></OMOBJ>""" ==
          OMObject(OMVariable("x"))
    @test omjson"""{"kind":"OMOBJ","object":{"kind":"OMV","name":"x"}}""" ==
          OMObject(OMVariable("x"))

    # The two encodings of the same object are the same object.
    @test om"""<OMOBJ xmlns="http://www.openmath.org/OpenMath"><OMA><OMS cd="arith1" name="plus"/><OMI>1</OMI></OMA></OMOBJ>""" ==
          om"""{"kind":"OMOBJ","object":{"kind":"OMA","applicant":{"kind":"OMS","cd":"arith1","name":"plus"},"arguments":[{"kind":"OMI","integer":1}]}}"""
end

@testitem "a malformed literal fails at expansion time" tags = [:unit, :model] begin
    using OpenMath
    for bad in (:(om"<OMOBJ><OMI>1</OMI>"), :(omjson"{\"kind\":\"OMOBJ\""),
        :(omxml"{\"kind\":\"OMOBJ\"}"))
        e = try
            Base.eval(@__MODULE__, bad)
            nothing
        catch err
            err
        end
        @test e !== nothing
        @test occursin("OpenMath", sprint(showerror, e))
    end
end
