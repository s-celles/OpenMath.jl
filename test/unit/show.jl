# SPDX-License-Identifier: MIT
#
# REQ-API-008 (text/plain half; the encoding MIMEs arrive with Phases 2–3).

@testitem "text/plain renders the functional form" tags = [:unit, :show] begin
    using OpenMath
    @test sprint(show, OMInteger(42)) == "OMI(42)"
    @test sprint(show, OMFloat(1.5)) == "OMF(1.5)"
    @test sprint(show, OMString("hi")) == "OMSTR(\"hi\")"
    @test sprint(show, OMVariable("x")) == "OMV(x)"
    @test sprint(show, OMSymbol("arith1", "plus")) == "OMS(arith1#plus)"
    @test sprint(show, OMBytes(UInt8[0xde, 0xad])) == "OMB(2 bytes)"
    @test sprint(show, OMReference("#a")) == "OMR(#a)"
end

@testitem "composites render their children" tags = [:unit, :show] begin
    using OpenMath
    e = OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1), OMVariable("x")])
    @test sprint(show, e) == "OMA(OMS(arith1#plus), OMI(1), OMV(x))"

    b = OMBinding(OMSymbol("fns1", "lambda"), [OMBoundVariable("x")], OMVariable("x"))
    @test sprint(show, b) == "OMBIND(OMS(fns1#lambda), [x], OMV(x))"
end

@testitem "a non-default cdbase is shown" tags = [:unit, :show] begin
    using OpenMath
    s = OMSymbol("mycd", "sym"; cdbase = "http://example.org/cd")
    @test sprint(show, s) == "OMS(http://example.org/cd#mycd#sym)"
end

@testitem "OMObject renders its root" tags = [:unit, :show] begin
    using OpenMath
    @test sprint(show, OMObject(OMInteger(1))) == "OMOBJ(OMI(1))"
end
