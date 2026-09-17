# SPDX-License-Identifier: MIT
#
# REQ-VAL-001, 006, 007, 008 — validation of what the type system cannot express.
#
# Note on scope: constraints that CAN be expressed in types are enforced at
# construction instead, which is strictly stronger than detecting them later.
# `OMError` takes an `OMSymbol` head, `OMBinding` takes `OMBoundVariable`s, and
# `OMForeign` only fits in `OMOrForeign` positions, so REQ-VAL-003/004/005 are
# discharged by the type signatures — see `test/unit/unrepresentable.jl`.

@testitem "validate accepts a well-formed object" tags = [:unit, :validate] begin
    using OpenMath
    obj = OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1), OMVariable("x")])
    @test isempty(validate(obj))
    @test isvalid_openmath(obj)
end

@testitem "validate reports a reference cycle" tags = [:unit, :validate] begin
    using OpenMath
    cyclic = OMApplication(OMSymbol("arith1", "plus"), [OMReference("#a")]; id = "a")
    issues = validate(cyclic)
    @test !isempty(issues)
    @test any(i -> i.code === :reference_cycle, issues)
    @test !isvalid_openmath(cyclic)
end

@testitem "validate reports a dangling reference" tags = [:unit, :validate] begin
    using OpenMath
    obj = OMApplication(OMSymbol("arith1", "plus"), [OMReference("#nowhere")])
    @test any(i -> i.code === :dangling_reference, validate(obj))
end

@testitem "validate reports a duplicate id" tags = [:unit, :validate] begin
    using OpenMath
    obj = OMApplication(OMSymbol("arith1", "plus"),
        [OMInteger(1; id = "x"), OMInteger(2; id = "x")])
    @test any(i -> i.code === :duplicate_id, validate(obj))
end

@testitem "validate reports a malformed cdbase" tags = [:unit, :validate] begin
    using OpenMath
    obj = OMSymbol("arith1", "plus"; cdbase = "not a uri", validate_cdbase = false)
    @test any(i -> i.code === :invalid_cdbase, validate(obj))
end

@testitem "validate reports excessive depth" tags = [:unit, :validate] begin
    using OpenMath
    # Built in a function: at test-module top level a `for`-loop assignment would
    # create a new soft-scope local instead of updating the binding.
    nest(n) = foldl((acc, _) -> OMApplication(OMSymbol("arith1", "plus"), [acc]),
        1:n; init = OMInteger(0))
    issues = with_limits(OMLimits(; max_depth = 50)) do
        validate(nest(200))
    end
    @test any(i -> i.code === :max_depth_exceeded, issues)
end

@testitem "validate issues carry a path and a spec citation" tags = [:unit, :validate] begin
    using OpenMath
    obj = OMApplication(OMSymbol("arith1", "plus"), [OMReference("#nowhere")])
    i = only(filter(x -> x.code === :dangling_reference, validate(obj)))
    @test i.path == "/arguments[1]"
    @test !isempty(i.spec)
    @test occursin("nowhere", i.message)
end

@testitem "validate terminates on every input (REQ-VAL-008)" tags = [:unit, :validate] begin
    using OpenMath
    for obj in (OMInteger(0), OMForeign(nothing, ""), OMReference("#x"),
        OMApplication(OMSymbol("a", "b"), OMNode[]),
        OMBinding(OMSymbol("fns1", "lambda"), OMBoundVariable[], OMInteger(1)))
        @test validate(obj) isa Vector{OpenMath.OMValidationIssue}
    end
end
