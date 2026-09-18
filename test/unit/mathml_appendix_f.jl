# SPDX-License-Identifier: MIT
#
# REQ-MML-006 — the non-strict → strict transformation of MathML 4 Appendix F.
#
# `read_mathml` refuses non-strict Content MathML by default, because guessing at
# constructs with no OpenMath counterpart is how this bridge usually goes wrong.
# Appendix F defines the transformation *normatively*, so with `strict = false`
# there is nothing to guess: there is a rule, and it is followed or the input is
# refused.
#
# The subset implemented is named in docs/src/design/mathml-appendix-f.md. The
# tests below quote the rule each one exercises.

@testitem "appendix F: an operator element becomes a csymbol (F.8)" tags = [
    :unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml, strict = false)

    # "Rewrite: element — For example, <plus/> is equivalent to the Strict form
    #  <csymbol cd="arith1">plus</csymbol>"
    @test read("<apply><plus/><ci>x</ci><cn type=\"integer\">1</cn></apply>").object ==
          OMS"arith1#plus"(OMVariable("x"), OMInteger(1))
    @test read("<apply><sin/><ci>x</ci></apply>").object ==
          OMS"transc1#sin"(OMVariable("x"))
    @test read("<apply><max/><ci>x</ci><ci>y</ci></apply>").object ==
          OMS"minmax1#max"(OMVariable("x"), OMVariable("y"))

    # And it is still refused without `strict = false`.
    @test_throws OpenMath.OpenMathParseError OpenMath.parse(
        "<math$(ns)><apply><plus/><ci>x</ci></apply></math>"; format = :mathml)
end

@testitem "appendix F: minus picks its symbol by arity (F.8.1)" tags = [
    :unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml,
        strict = false).object

    # "The choice of symbol for the minus operator depends on the number of the
    #  arguments, minus or unary_minus."
    @test read("<apply><minus/><ci>x</ci><ci>y</ci></apply>") ==
          OMS"arith1#minus"(OMVariable("x"), OMVariable("y"))
    @test read("<apply><minus/><ci>x</ci></apply>") ==
          OMS"arith1#unary_minus"(OMVariable("x"))
end

@testitem "appendix F: constants become csymbols (F.7.1)" tags = [:unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml,
        strict = false).object

    # "In Strict Content MathML, constants should be represented using csymbol
    #  elements. A number of important constants are defined in the nums1
    #  content dictionary."
    @test read("<pi/>") == OMS"nums1#pi"
    @test read("<exponentiale/>") == OMS"nums1#e"
    @test read("<imaginaryi/>") == OMS"nums1#i"
    @test read("<notanumber/>") == OMS"nums1#NaN"
    @test read("<infinity/>") == OMS"nums1#infinity"
    @test read("<true/>") == OMS"logic1#true"
    @test read("<false/>") == OMS"logic1#false"
    @test read("<cn type=\"constant\">&#x03C0;</cn>") == OMS"nums1#pi"
end

@testitem "appendix F: an untyped cn gets its type from its lexical form (F.9.1)" tags = [
    :unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml,
        strict = false).object

    # Strict `cn` requires a type; non-strict `cn` defaults to "real", and a
    # value written as an integer is an integer.
    @test read("<cn>42</cn>") == OMInteger(42)
    @test read("<cn>-7</cn>") == OMInteger(-7)
    @test read("<cn>1.5</cn>") == OMFloat(1.5)
    @test read("<cn>1.0e-10</cn>") == OMFloat(1.0e-10)
    @test read("<cn type=\"real\">2</cn>") == OMFloat(2.0)
end

@testitem "appendix F: cn with sep (F.7.1)" tags = [:unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml,
        strict = false).object

    # "<cn type="rational">n<sep/>d</cn> is rewritten to
    #  <apply><csymbol cd="nums1">rational</csymbol>
    #         <cn type="integer">n</cn><cn type="integer">d</cn></apply>"
    @test read("<cn type=\"rational\">3<sep/>4</cn>") ==
          OMS"nums1#rational"(OMInteger(3), OMInteger(4))
    @test read("<cn type=\"complex-cartesian\">1<sep/>2</cn>") ==
          OMS"nums1#complex_cartesian"(OMInteger(1), OMInteger(2))
    @test read("<cn type=\"complex-polar\">1<sep/>2</cn>") ==
          OMS"nums1#complex_polar"(OMInteger(1), OMInteger(2))
end

@testitem "appendix F: a based integer (F.7.1)" tags = [:unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml,
        strict = false).object

    # "<cn type="integer" base="16">FF60</cn> →
    #  <apply><csymbol cd="nums1">based_integer</csymbol>
    #         <cn type="integer">16</cn><cs>FF60</cs></apply>"
    # "(A base attribute with value 10 is simply removed.)"
    @test read("<cn type=\"integer\" base=\"16\">FF60</cn>") ==
          OMS"nums1#based_integer"(OMInteger(16), OMString("FF60"))
    @test read("<cn type=\"integer\" base=\"10\">42</cn>") == OMInteger(42)
end

@testitem "appendix F: lambda becomes a bind (F.4.3)" tags = [:unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml,
        strict = false).object

    got = read("<lambda><bvar><ci>x</ci></bvar><apply><sin/><ci>x</ci></apply></lambda>")
    @test got == OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")],
        OMS"transc1#sin"(OMVariable("x")))
end

@testitem "appendix F: piecewise becomes piece1 (F.4.4)" tags = [:unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml,
        strict = false).object

    got = read("""<piecewise>
        <piece><ci>x</ci><apply><gt/><ci>x</ci><cn>0</cn></apply></piece>
        <otherwise><apply><minus/><ci>x</ci></apply></otherwise>
        </piecewise>""")
    @test got.applicant == OMS"piece1#piecewise"
    @test length(got.arguments) == 2
    @test got.arguments[1].applicant == OMS"piece1#piece"
    @test got.arguments[2].applicant == OMS"piece1#otherwise"
end

@testitem "appendix F: what it does not implement is refused, not guessed" tags = [
    :unit, :mathml] begin
    using OpenMath
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>"; format = :mathml, strict = false)

    # F.2, F.3, F.5 and F.6 — the qualifier and `domainofapplication` machinery —
    # are not implemented. An input needing them raises and names the section,
    # which is the whole point of `strict = false` being a *transformation* and
    # not a guess.
    for src in ("<apply><int/><bvar><ci>x</ci></bvar><ci>x</ci></apply>",
        "<apply><sum/><bvar><ci>i</ci></bvar><lowlimit><cn>1</cn></lowlimit>" *
        "<uplimit><cn>9</cn></uplimit><ci>i</ci></apply>",
        "<apply><forall/><domainofapplication><ci>S</ci></domainofapplication>" *
        "<ci>p</ci></apply>")
        e = try
            read(src)
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathParseError
        @test occursin("Appendix F", sprint(showerror, e))
    end

    # And presentation markup is still not Content MathML at all.
    @test_throws OpenMath.OpenMathParseError read("<mrow><mi>x</mi></mrow>")
end

@testitem "appendix F: the strict subset still reads unchanged" tags = [:unit, :mathml] begin
    using OpenMath
    # `strict = false` must be a superset: everything strict still parses, and to
    # the same object.
    for obj in (OMInteger(42), OMFloat(NaN), OMString("a<b"), OMVariable("λ"),
        OMS"arith1#plus"(OMInteger(1), OMVariable("x")),
        OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")], OMVariable("x")),
        OMError(OMS"error1#e", OMOrForeign[OMInteger(1)]))
        src = OpenMath.mathml(OMObject(obj))
        @test OpenMath.parse(src; format = :mathml, strict = false).object ==
              OpenMath.parse(src; format = :mathml).object
    end
end

@testitem "appendix F: a bare root is the square root (F.2.5, degenerate)" tags = [
    :unit, :mathml] begin
    using OpenMath
    # `arith1#root` takes the radicand *and* the degree; `<root/>` with no
    # `<degree>` qualifier is the square root, so the 2 has to be supplied.
    #
    # Found by the MathML.jl oracle, and only by its shared-document path: the
    # hand-written pairs give the OpenMath side themselves, so they asserted a
    # `root(x, 2)` this transformation never actually produced. A differential
    # check is only as strong as the input both sides are made to share.
    ns = """ xmlns="http://www.w3.org/1998/Math/MathML\""""
    read(s) = OpenMath.parse("<math$(ns)>$(s)</math>";
        format = :mathml, strict = false).object

    obj = read("<apply><root/><ci>x</ci></apply>")
    @test obj isa OMApplication
    @test obj.applicant == OMSymbol("arith1", "root")
    @test length(obj.arguments) == 2
    @test obj.arguments[1] == OMVariable("x")
    @test obj.arguments[2] == OMInteger(2)

    # An explicit degree is the qualifier form, which belongs to F.2 and is
    # refused rather than guessed — so the rule above can never fire on it.
    @test_throws OpenMath.OpenMathParseError read(
        "<apply><root/><degree><cn>3</cn></degree><ci>x</ci></apply>")
end

@testitem "appendix F: every symbol it can produce is one a phrasebook knows" tags = [
    :unit, :mathml] begin
    using OpenMath
    # Appendix F can transform a document perfectly and still leave something
    # nothing can read. The transformation and the vocabulary are written in
    # different files from different documents, so nothing but this gate makes
    # them agree — and when it was first written it failed on ten symbols.
    known = Set((s.cd, s.name) for s in base_vocabulary())

    # F.8's operator table.
    operators = Set(values(OpenMath.appendix_f_operators()))
    @test length(operators) > 50
    @test isempty(setdiff(operators, known))

    # The symbols F *synthesises* rather than looks up: the constants of F.7.1,
    # the `sep` types, and the ones the container rules introduce.
    synthesised = Set([
        ("arith1", "unary_minus"),                       # F.8.1
        ("nums1", "based_integer"), ("nums1", "based_float"),
        ("nums1", "rational"), ("nums1", "complex_cartesian"),
        ("nums1", "complex_polar"), ("nums1", "bigfloat"),
        ("nums1", "pi"), ("nums1", "e"), ("nums1", "i"),
        ("nums1", "NaN"), ("nums1", "infinity"), ("nums1", "gamma"),
        ("logic1", "true"), ("logic1", "false"), ("set1", "emptyset")])
    @test isempty(setdiff(synthesised, known))

    # `fns1#lambda` and the `piece1` symbols are deliberately *not* in the base
    # vocabulary: a binder and a piecewise are not applications of a function,
    # and the base phrasebook interprets them structurally rather than by
    # looking the head up. Named here so the exclusion is a decision.
    @test !(("fns1", "lambda") in known)
    @test all(n -> !(("piece1", n) in known), ("piece", "otherwise", "piecewise"))
end
