# SPDX-License-Identifier: MIT
#
# REQ-VAL-002/003/004/005, refined: these constraints are discharged by the type
# signatures rather than by `validate`. Making an illegal state unrepresentable is
# strictly stronger than detecting it afterwards; the readers reject the
# corresponding malformed documents at the parse boundary instead.
#
# These tests pin the guarantee so that a later refactor cannot quietly widen a
# field type and reopen the hole.

@testitem "an OMError head can only be a symbol (REQ-VAL-003)" tags = [:unit, :model] begin
    using OpenMath
    @test fieldtype(OMError, :head) === OMSymbol
    @test_throws MethodError OMError(OMInteger(1), OMOrForeign[])
end

@testitem "bound variables can only be variables (REQ-VAL-005)" tags = [:unit, :model] begin
    using OpenMath
    @test fieldtype(OMBinding, :variables) === Vector{OMBoundVariable}
    @test_throws MethodError OMBinding(OMSymbol("fns1", "lambda"),
        [OMInteger(1)], OMInteger(1))
    # An attributed bound variable is the legal decorated form.
    bv = OMBoundVariable("x", [OMAttributePair(OMSymbol("ecc", "type"), OMString("R"))])
    @test OMBinding(OMSymbol("fns1", "lambda"), [bv], OMVariable("x")) isa OMBinding
end

@testitem "foreign content only fits grammar-legal positions (REQ-VAL-004)" tags = [
    :unit, :model] begin
    using OpenMath
    f = OMForeign("text/plain", "raw")
    # Legal: an attribute value and an OMError argument.
    @test OMAttributePair(OMSymbol("ecc", "k"), f) isa OMAttributePair
    @test OMError(OMSymbol("error1", "unhandled_symbol"), OMOrForeign[f]) isa OMError
    # Illegal: an ordinary argument position is typed `OMNode`, which excludes it.
    @test !(OMForeign <: OMNode)
    @test_throws MethodError OMApplication(OMSymbol("a", "b"), [f])
end

@testitem "an application always has an applicant (REQ-VAL-002)" tags = [:unit, :model] begin
    using OpenMath
    @test fieldtype(OMApplication, :applicant) === OMNode
    # There is no constructor producing a childless OMA; the readers raise
    # OpenMathParseError on `<OMA/>` instead.
    @test_throws MethodError OMApplication()
end
