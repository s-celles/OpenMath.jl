# SPDX-License-Identifier: MIT
#
# REQ-POP-001 — the Popcorn printer. Popcorn is the compact linear notation of
# Horn and Roozemond, "OpenMath in SCIEnce: SCSCP and POPCORN" (MKM 2009), whose
# reference grammar is `PopcornAST.g` in `org.symcomp.openmath`. The printer
# follows that grammar, so that what it prints reads back as the same object.
# See docs/src/design/popcorn.md for every place it departs from the reference
# renderer, and why.

@testitem "popcorn: the examples of the 2009 paper" tags = [:unit, :popcorn] begin
    using OpenMath
    p = OpenMath.popcorn
    @test p(OMS"transc1#sin"(OMInteger(3))) == "sin(3)"
    @test p(OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")],
        OMS"arith1#plus"(OMInteger(1), OMVariable("x")))) == "lambda[\$x -> 1 + \$x]"
    @test p(OMS"prog1#assign"(OMVariable("a"),
        OMS"list1#list"(OMS"nums1#rational"(OMInteger(1), OMInteger(2)),
            OMApplication(OMS"complex1#complex_cartesian", [OMInteger(2), OMInteger(8)];
                id = "x")))) == "\$a := [1//2, (2|8):x]"
    @test p(OMAttribution([OMAttributePair(OMS"aa#bb", OMString("cc"))], OMFloat(1.2))) ==
          "1.2{aa.bb -> \"cc\"}"
end

@testitem "popcorn: leaves" tags = [:unit, :popcorn] begin
    using OpenMath
    p = OpenMath.popcorn
    @test p(OMInteger(42)) == "42"
    @test p(OMInteger(big(2)^70)) == "1180591620717411303424"
    @test p(OMInteger(-3)) == "-3"
    @test p(OMFloat(0.5)) == "0.5"
    @test p(OMFloat(1.0e20)) == "1.0e20"
    @test p(OMFloat(-2.5)) == "-2.5"
    # Not decimal in Popcorn's grammar: written as the IEEE bits, like `<OMF hex>`.
    @test p(OMFloat(Inf)) == "0f7FF0000000000000"
    @test p(OMFloat(NaN)) == "0f" * uppercase(string(reinterpret(UInt64, NaN); base = 16))
    @test p(OMString("say \"hi\" \\ bye")) == "\"say \\\"hi\\\" \\\\ bye\""
    @test p(OMVariable("x")) == "\$x"
    @test p(OMVariable("x-1")) == "\$'x-1'"         # not an ID: quoted
    @test p(OMVariable("or")) == "\$'or'"           # a keyword: quoted
    @test p(OMS"arith1#plus") == "arith1.plus"
    @test p(OMS"nums1#pi") == "pi"                   # a name the grammar knows bare
    @test p(OMSymbol("my-cd", "f")) == "'my-cd'.f"
    @test p(OMReference("#a")) == "#a"
    @test p(OMReference("http://example.org/x#y")) == "##http://example.org/x#y##"
    @test p(OMBytes(UInt8[1, 2, 3])) == "%AQID%"
    @test p(OMForeign(nothing, "<b>x</b>")) == "`<b>x</b>`"
    @test p(OMObject(OMInteger(1))) == "1"
end

@testitem "popcorn: infix operators and their precedence" tags = [:unit, :popcorn] begin
    using OpenMath
    p = OpenMath.popcorn
    x, y, z = OMVariable("x"), OMVariable("y"), OMVariable("z")
    plus(a...) = OMS"arith1#plus"(a...)
    times(a...) = OMS"arith1#times"(a...)
    minus(a, b) = OMS"arith1#minus"(a, b)
    power(a, b) = OMS"arith1#power"(a, b)

    @test p(plus(x, y, z)) == "\$x + \$y + \$z"
    @test p(times(plus(x, y), z)) == "(\$x + \$y)*\$z"
    @test p(plus(times(x, y), z)) == "\$x*\$y + \$z"
    # Left-associative: a left operand at the same level needs no brackets,
    # a right one does.
    @test p(minus(minus(x, y), z)) == "\$x - \$y - \$z"
    @test p(minus(x, minus(y, z))) == "\$x - (\$y - \$z)"
    @test p(minus(plus(x, y), z)) == "\$x + \$y - \$z"
    @test p(plus(minus(x, y), z)) == "\$x - \$y + \$z"
    # `+` flattens a chain, so a nested `+` keeps its brackets.
    @test p(plus(plus(x, y), z)) == "(\$x + \$y) + \$z"
    @test p(plus(x, plus(y, z))) == "\$x + (\$y + \$z)"
    # Non-associative: `^`, `//`, `|`, the relations.
    @test p(power(power(x, y), z)) == "(\$x^\$y)^\$z"
    @test p(power(x, power(y, z))) == "\$x^(\$y^\$z)"
    @test p(OMS"relation1#eq"(plus(x, OMInteger(1)), y)) == "\$x + 1 = \$y"
    @test p(OMS"logic1#and"(OMS"relation1#lt"(x, y), OMS"relation1#leq"(y, z))) ==
          "\$x < \$y and \$y <= \$z"
    @test p(OMS"logic1#implies"(OMS"logic1#or"(x, y), z)) == "\$x or \$y ==> \$z"
    @test p(OMS"arith1#divide"(times(x, y), z)) == "\$x*\$y/\$z"
    @test p(OMS"interval1#interval"(OMInteger(1), OMInteger(5))) == "1 .. 5"
    @test p(OMS"relation2#approx"(x, y)) == "\$x ~ \$y"
    @test p(OMS"prog1#block"(OMS"prog1#assign"(x, OMInteger(1)), x)) == "\$x := 1; \$x"
end

@testitem "popcorn: signs" tags = [:unit, :popcorn] begin
    using OpenMath
    p = OpenMath.popcorn
    x, y = OMVariable("x"), OMVariable("y")
    neg(a) = OMS"arith1#unary_minus"(a)
    @test p(neg(x)) == "-\$x"
    @test p(OMS"arith1#plus"(x, neg(y))) == "\$x + -\$y"
    @test p(OMS"arith1#times"(x, neg(y))) == "\$x*(-\$y)"
    @test p(neg(OMS"arith1#times"(x, y))) == "-\$x*\$y"     # prefix `-` takes a product
    @test p(neg(OMS"arith1#plus"(x, y))) == "-(\$x + \$y)"
    @test p(OMS"arith1#power"(OMInteger(-2), OMInteger(2))) == "(-2)^2"
    @test p(OMS"arith1#minus"(x, OMInteger(-3))) == "\$x - -3"
    # `-3` reads back as the integer -3, so negating a literal is written as a call.
    @test p(neg(OMInteger(3))) == "arith1.unary_minus(3)"
    @test p(neg(OMFloat(-1.5))) == "arith1.unary_minus(-1.5)"
end

@testitem "popcorn: forms with no infix notation are calls" tags = [:unit, :popcorn] begin
    using OpenMath
    p = OpenMath.popcorn
    x, y, z = OMVariable("x"), OMVariable("y"), OMVariable("z")
    # The reference parser builds `and`/`or` two operands at a time, so three
    # operands are a call: an infix chain would read back nested.
    # And `and` is a keyword of the grammar, so after `logic1.` it is quoted:
    # `logic1.and` does not lex as a symbol, in the reference parser either.
    @test p(OMS"logic1#and"(x, y, z)) == "logic1.'and'(\$x, \$y, \$z)"
    @test p(OMS"arith1#plus"(x)) == "arith1.plus(\$x)"
    @test p(OMS"arith1#minus"(x, y, z)) == "arith1.minus(\$x, \$y, \$z)"
    # `..` reads back as `interval1#interval` only.
    @test p(OMS"interval1#integer_interval"(OMInteger(1), OMInteger(5))) ==
          "interval1.integer_interval(1, 5)"
    @test p(OMS"logic1#not"(x)) == "not(\$x)"
    @test p(OMS"list1#list"()) == "[]"
    @test p(OMS"set1#set"(OMInteger(1), OMInteger(2))) == "{1, 2}"
end

@testitem "popcorn: compound forms and ids" tags = [:unit, :popcorn] begin
    using OpenMath
    p = OpenMath.popcorn
    x = OMVariable("x")
    # The head of a call must be an atom.
    f = OMS"fns1#lambda"
    @test p(OMApplication(OMApplication(OMSymbol("cd", "f"), [x]), [x])) ==
          "(cd.f(\$x))(\$x)"
    @test p(OMError(OMS"moreerrors#encodingError", [OMString("bad")])) ==
          "moreerrors.encodingError!(\"bad\")"
    @test p(OMBinding(OMS"quant1#forall",
        [OMBoundVariable("x"),
            OMBoundVariable("y",
                [OMAttributePair(OMS"ecc#type", OMS"setname1#Z")])],
        OMS"relation1#eq"(x, x))) ==
          "forall[\$x, \$y{ecc.type -> setname1.Z} -> \$x = \$x]"
    @test p(OMAttribution([OMAttributePair(OMS"ecc#type", OMS"setname1#Z")],
        OMS"arith1#plus"(x, x))) == "(\$x + \$x){ecc.type -> setname1.Z}"
    # An id goes on an atom directly, and on anything else in brackets.
    @test p(OMVariable("x"; id = "a")) == "\$x:a"
    @test p(OMSymbol("cd", "f"; id = "s")) == "cd.f:s"
    @test p(OMApplication(OMSymbol("cd", "f"), [x]; id = "n-1")) == "(cd.f(\$x)):'n-1'"
    @test p(OMS"arith1#times"(OMVariable("x"; id = "a"), OMInteger(2))) == "\$x:a*2"
    # Popcorn has no cdbase: a symbol is written by its cd and name only.
    @test p(OMSymbol("arith1", "plus"; cdbase = "http://example.org/cd")) == "arith1.plus"
end

@testitem "popcorn: write_popcorn writes to a stream" tags = [:unit, :popcorn] begin
    using OpenMath
    io = IOBuffer()
    write_popcorn(io, OMObject(OMS"arith1#plus"(OMInteger(1), OMVariable("x"))))
    @test String(take!(io)) == "1 + \$x"
end

@testitem "popcorn: a deep tree does not overflow the stack (REQ-SEC-002)" tags = [
    :unit, :popcorn, :security] begin
    using OpenMath
    node = foldl((n, _) -> OMS"transc1#sin"(n), 1:100_000; init = OMVariable("x"))
    s = OpenMath.popcorn(node)
    @test startswith(s, "sin(sin(")
    @test endswith(s, "\$x" * ")"^100_000)
end
