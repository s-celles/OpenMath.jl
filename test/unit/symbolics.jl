# SPDX-License-Identifier: MIT
#
# REQ-PHR-002 — the Symbolics.jl phrasebook, as a package extension.
#
# Both directions are tested, and they are not the same problem. Symbolics →
# OpenMath is structural: walk the expression tree and relabel. OpenMath →
# Symbolics goes through a `Phrasebook`, because a variable has to become a
# Symbolics variable rather than a `Symbol`, and that is a property of the
# phrasebook rather than of `interpret` (REQ-PHR-001).

@testitem "symbolics: leaves and variables" tags = [:unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x y

    @test to_openmath(x) == OMVariable("x")
    @test to_openmath(Num(2)) == OMInteger(2)
    @test to_openmath(Num(1.5)) == OMFloat(1.5)
    @test to_openmath(Num(3 // 4)) == OMS"nums1#rational"(OMInteger(3), OMInteger(4))
end

@testitem "symbolics: arithmetic maps onto arith1" tags = [:unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x y

    head(e) = to_openmath(e).applicant
    @test head(x + y) == OMS"arith1#plus"
    @test head(x * y) == OMS"arith1#times"
    @test head(x^2) == OMS"arith1#power"
    @test head(x / y) == OMS"arith1#divide"
    @test head(sqrt(x)) == OMS"arith1#root"
    @test to_openmath(sqrt(x)) == OMS"arith1#root"(OMVariable("x"), OMInteger(2))

    # Symbolics normalises before we ever see the expression, so what comes out
    # is the encoding of the *normal form*, not of what was typed. `-x` is stored
    # as `(-1) * x` and comes out as `arith1#times`, never `arith1#unary_minus`;
    # `x - y` likewise never produces `arith1#minus`. Both symbols exist in the
    # writer, for expressions that do reach it in that shape.
    @test head(-x) == OMS"arith1#times"
    @test to_openmath(-x) == OMS"arith1#times"(OMInteger(-1), OMVariable("x"))
    @test to_openmath(x + 1) == OMS"arith1#plus"(OMInteger(1), OMVariable("x"))
end

@testitem "symbolics: transcendental functions map onto transc1" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x

    for (f, name) in ((sin, "sin"), (cos, "cos"), (tan, "tan"),
        (sinh, "sinh"), (cosh, "cosh"), (tanh, "tanh"),
        (asin, "arcsin"), (acos, "arccos"), (atan, "arctan"),
        (exp, "exp"))
        @test to_openmath(f(x)) == OMSymbol("transc1", name)(OMVariable("x"))
    end
    @test to_openmath(log(x)) == OMS"transc1#ln"(OMVariable("x"))
    @test to_openmath(abs(x)) == OMS"arith1#abs"(OMVariable("x"))
end

@testitem "symbolics: reading back gives a Symbolics expression (REQ-PHR-002)" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    p = OpenMath.symbolics_phrasebook()

    v = interpret(p, OMVariable("x"))
    @test v isa Num
    @test string(v) == "x"

    e = interpret(p, OMS"arith1#plus"(OMVariable("x"), OMInteger(1)))
    @test e isa Num
    @test isequal(e, Symbolics.variable(:x) + 1)

    e = interpret(p, OMS"transc1#sin"(OMVariable("x")))
    @test isequal(e, sin(Symbolics.variable(:x)))
end

@testitem "symbolics: the round trip is the identity on the mapped subset" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x y
    p = OpenMath.symbolics_phrasebook()

    for e in (x, x + y, x * y, x^2, x / y, -x, sqrt(x),
        sin(x), cos(x) * 2, exp(x + y), log(x), abs(x),
        x + 1, 2x + 3y, (x + y)^2, sin(x)^2 + cos(x)^2)
        back = interpret(p, to_openmath(e))
        @test isequal(back, e)
    end
end

@testitem "symbolics: equations map onto relation1#eq" tags = [:unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x y
    p = OpenMath.symbolics_phrasebook()

    eq = x ~ y + 1
    om = to_openmath(eq)
    @test om.applicant == OMS"relation1#eq"
    back = interpret(p, om)
    @test back isa Symbolics.Equation
    @test isequal(back.lhs, eq.lhs) && isequal(back.rhs, eq.rhs)
end

@testitem "symbolics: a derivative is diff of a lambda" tags = [:unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x
    p = OpenMath.symbolics_phrasebook()

    # OpenMath has no free-standing derivative operator: `calculus1#diff` applies
    # to a *function*, so the bound variable has to be carried by an `fns1#lambda`
    # binding. That is the whole of the correspondence, and it is why this cannot
    # be a one-line entry in the vocabulary table.
    d = Differential(x)(x^2)
    om = to_openmath(d)
    @test om.applicant == OMS"calculus1#diff"
    lambda = only(om.arguments)
    @test lambda isa OMBinding
    @test lambda.binder == OMS"fns1#lambda"
    @test only(lambda.variables).name == "x"

    back = interpret(p, om)
    @test isequal(Symbolics.expand_derivatives(back),
        Symbolics.expand_derivatives(d))
end

@testitem "symbolics: what cannot be mapped raises (REQ-PHR-005)" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x
    # `Symbolics` has operators with no Content Dictionary counterpart. Producing
    # an approximation of one silently is the failure this guards against.
    e = try
        to_openmath(sign(x))
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathConversionError
    @test occursin("sign", sprint(showerror, e))
end

@testitem "symbolics: interpreting is still structural (REQ-PHR-003)" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    p = OpenMath.symbolics_phrasebook()
    # A variable named after a function is a variable.
    v = interpret(p, OMVariable("sin"))
    @test v isa Num
    @test string(v) == "sin"
    @test_throws OpenMath.OpenMathConversionError interpret(p,
        OMS"nowhere#eval"(OMString("run this")))
end

@testitem "symbolics: comparisons and logic map onto relation1 and logic1" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x y

    head(e) = to_openmath(e).applicant
    # Symbolics normalises `x > 0` to `0 < x`, so the *symbol* is `lt` and the
    # arguments are swapped. Encoding the normal form is the whole policy here.
    @test head(x > 0) == OMS"relation1#lt"
    @test to_openmath(x > 0) == OMS"relation1#lt"(OMInteger(0), OMVariable("x"))
    @test head(x < y) == OMS"relation1#lt"
    @test head(x <= y) == OMS"relation1#leq"
    @test head((x < y) & (y < 1)) == OMS"logic1#and"
    @test head((x < y) | (y < 1)) == OMS"logic1#or"
end

@testitem "symbolics: ifelse is piece1#piecewise" tags = [:unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x
    p = OpenMath.symbolics_phrasebook()

    # `piece1` builds a piecewise value out of (value, condition) pieces and a
    # final `otherwise`. Julia's `ifelse` is the two-branch case of exactly that.
    om = to_openmath(ifelse(x > 0, x, -x))
    @test om.applicant == OMS"piece1#piecewise"
    @test length(om.arguments) == 2
    @test om.arguments[1].applicant == OMS"piece1#piece"
    @test om.arguments[2].applicant == OMS"piece1#otherwise"

    back = interpret(p, om)
    @test isequal(back, ifelse(x > 0, x, -x))
end

@testitem "symbolics: a piecewise with several pieces reads back" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    Symbolics.@variables x
    p = OpenMath.symbolics_phrasebook()

    # Three branches, which `ifelse` can only express by nesting. Reading is the
    # direction that has to cope, since OpenMath writes them flat.
    om = OMS"piece1#piecewise"(
        OMS"piece1#piece"(OMInteger(1), OMS"relation1#lt"(OMVariable("x"), OMInteger(0))),
        OMS"piece1#piece"(OMInteger(2), OMS"relation1#lt"(OMVariable("x"), OMInteger(5))),
        OMS"piece1#otherwise"(OMInteger(3)))
    back = interpret(p, om)
    @test back isa Num
    # The structure is what this bridge is responsible for; *evaluating* it is
    # Symbolics' job and an explicit non-goal here (REQ-PHR-006). So the
    # assertion is on the shape: ifelse(x < 0, 1, ifelse(x < 5, 2, 3)).
    u = Symbolics.unwrap(back)
    @test Symbolics.operation(u) === ifelse
    outer = Symbolics.arguments(u)
    # A literal inside an expression is a symbolic constant node, so it needs
    # `value` to come back to a Julia number — the same wrinkle the writer has.
    @test Symbolics.value(outer[2]) == 1
    @test Symbolics.operation(outer[3]) === ifelse
    inner = Symbolics.arguments(outer[3])
    @test Symbolics.value(inner[2]) == 2
    @test Symbolics.value(inner[3]) == 3
end

@testitem "symbolics: an equality as a condition has no counterpart" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    p = OpenMath.symbolics_phrasebook()
    # `relation1#eq` becomes a Symbolics `Equation`, which is right for an
    # equation and wrong for a condition: `ifelse` takes a truth value, and
    # Symbolics has no symbolic equality predicate — `==` on symbolic values is
    # eager and returns a `Bool`. A genuine gap between the two languages, and
    # one the bridge names rather than papers over (REQ-PHR-005).
    om = OMS"piece1#piecewise"(
        OMS"piece1#piece"(OMInteger(1),
            OMS"relation1#eq"(OMVariable("x"), OMInteger(0))),
        OMS"piece1#otherwise"(OMInteger(2)))
    e = try
        interpret(p, om)
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathConversionError
    @test occursin("equality", sprint(showerror, e))
end

@testitem "symbolics: a piecewise without an otherwise is refused" tags = [
    :unit, :symbolics] begin
    using OpenMath, Symbolics
    p = OpenMath.symbolics_phrasebook()
    # `ifelse` is total; a piecewise with no `otherwise` is not. Inventing a
    # default would be the silent lie REQ-PHR-005 exists to prevent.
    om = OMS"piece1#piecewise"(
        OMS"piece1#piece"(OMInteger(1), OMS"logic1#true"))
    @test_throws OpenMath.OpenMathConversionError interpret(p, om)
end

@testitem "symbolics: a logarithm keeps its base" tags = [:unit, :symbolics] begin
    using OpenMath, Symbolics
    @variables x
    p = OpenMath.symbolics_phrasebook()

    # `transc1#log` takes the base and the argument. Interpreting it with
    # `Base.log` gives `log(x)/log(10)`, which is the same number and a
    # different expression — the same trap as writing `arith1#root(a, 2)` as
    # `a^(1//2)` instead of `sqrt(a)`, and it stops the round trip being exact.
    # Found by the MathML.jl oracle: MathML.jl reads `<log/>` as `log10`.
    @test isequal(interpret(p, OMS"transc1#log"(OMInteger(10), OMVariable("x"))),
        log10(x))
    @test isequal(interpret(p, OMS"transc1#log"(OMInteger(2), OMVariable("x"))),
        log2(x))
    # Base 10 and base 2 are the bases Symbolics keeps whole. Any other base has
    # no such form, so it stays `log(b, x)` — which Symbolics expands into a
    # quotient of natural logarithms. That still round-trips, as the loop below
    # checks; it just comes back as `arith1#divide` rather than `transc1#log`.
    @test isequal(interpret(p, OMS"transc1#log"(OMInteger(3), OMVariable("x"))),
        log(3, x))
    @test isequal(interpret(p, OMS"transc1#ln"(OMVariable("x"))), log(x))

    # And back, which is what "exact" means here.
    @test to_openmath(log10(x)) == OMS"transc1#log"(OMInteger(10), OMVariable("x"))
    @test to_openmath(log2(x)) == OMS"transc1#log"(OMInteger(2), OMVariable("x"))
    @test to_openmath(log(x)) == OMS"transc1#ln"(OMVariable("x"))

    for e in (log10(x), log2(x), log(x), log(3, x))
        @test isequal(interpret(p, to_openmath(e)), e)
    end
end
