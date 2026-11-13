# SPDX-License-Identifier: MIT
#
# REQ-API-008 (text/plain half; the encoding MIMEs arrive with Phases 2–3).

@testitem "show renders the functional form" tags = [:unit, :show] begin
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

@testitem "text/plain renders Popcorn (REQ-POP-003)" tags = [:unit, :show, :popcorn] begin
    using OpenMath
    plain(x) = repr(MIME"text/plain"(), x)
    e = OMS"arith1#times"(OMS"arith1#plus"(OMVariable("x"), OMInteger(1)), OMInteger(2))
    @test plain(e) == "(\$x + 1)*2"
    @test plain(OMInteger(42)) == "42"
    @test plain(OMS"nums1#pi") == "pi"
    # The two-argument form, used by `repr` and inside containers, is unchanged.
    @test sprint(show, e) ==
          "OMA(OMS(arith1#times), OMA(OMS(arith1#plus), OMV(x), OMI(1)), OMI(2))"
    # And so is an OMObject, whose envelope Popcorn has no syntax for.
    @test plain(OMObject(OMInteger(1))) == "OMOBJ(OMI(1))"
end

@testitem "text/plain falls back where Popcorn would hide something" tags = [
    :unit, :show, :popcorn] begin
    using OpenMath
    plain(x) = repr(MIME"text/plain"(), x)
    # Popcorn has no syntax for cdbase: showing `arith1.plus` would hide it.
    s = OMSymbol("arith1", "plus"; cdbase = "http://example.org/cd")
    a = OMApplication(s, [OMInteger(1), OMInteger(2)])
    @test plain(a) == sprint(show, a)
    @test plain(OMApplication(OMS"arith1#plus", [OMInteger(1)];
        cdbase = "http://example.org/cd")) ==
          "OMA(cdbase=http://example.org/cd, OMS(arith1#plus), OMI(1))"
    # Nor for an OMFOREIGN encoding.
    err = OMError(OMS"moreerrors#encodingError", [OMForeign("text/plain", "x")])
    @test plain(err) == sprint(show, err)
    # Without an encoding, Popcorn shows everything.
    @test plain(OMError(OMS"moreerrors#encodingError", [OMForeign(nothing, "<b/>")])) ==
          "moreerrors.encodingError!(`<b/>`)"
end

@testitem "text/plain on a deep tree does not overflow the stack" tags = [
    :unit, :show, :popcorn, :security] begin
    using OpenMath
    node = foldl((n, _) -> OMS"transc1#sin"(n), 1:50_000; init = OMVariable("x"))
    @test endswith(repr(MIME"text/plain"(), node), "\$x" * ")"^50_000)
end
