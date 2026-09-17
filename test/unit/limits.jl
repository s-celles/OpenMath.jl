# SPDX-License-Identifier: MIT
#
# REQ-SEC-002, REQ-SEC-003, REQ-SEC-004, REQ-CAN-008.

@testitem "limits are configurable and scoped" tags = [:unit, :limits] begin
    using OpenMath
    @test limits().max_depth == 10_000
    with_limits(OMLimits(; max_depth = 7)) do
        @test limits().max_depth == 7
    end
    @test limits().max_depth == 10_000
end

@testitem "with_limits restores on error" tags = [:unit, :limits] begin
    using OpenMath
    try
        with_limits(OMLimits(; max_depth = 3)) do
            error("boom")
        end
    catch
    end
    @test limits().max_depth == 10_000
end

@testitem "OpenMathLimitError names the limit it hit" tags = [:unit, :limits] begin
    using OpenMath
    # Built in a function: at test-module top level a `for`-loop assignment would
    # create a new soft-scope local instead of updating the binding.
    nest(n) = foldl((acc, _) -> OMApplication(OMSymbol("arith1", "plus"), [acc]),
        1:n; init = OMInteger(0))
    e = try
        with_limits(OMLimits(; max_depth = 10)) do
            canonicalize(nest(50))
        end
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathLimitError
    @test e.limit === :max_depth
    @test e.maximum == 10
    @test occursin("max_depth", sprint(showerror, e))
end

@testitem "deep structures do not overflow the native stack" tags = [:unit, :limits] begin
    using OpenMath
    # REQ-SEC-003: every traversal uses an explicit stack. 500_000 levels is far
    # past what native recursion survives.
    # Built in a function: at test-module top level a `for`-loop assignment would
    # create a new soft-scope local instead of updating the binding.
    nest(n) = foldl((acc, _) -> OMApplication(OMSymbol("arith1", "plus"), [acc]),
        1:n; init = OMInteger(0))
    deep = nest(500_000)
    @test depth(deep) == 500_001
    n = Ref(0)
    walk(_ -> (n[] += 1), deep)
    @test n[] == 1_000_001
end

@testitem "node counting respects the budget" tags = [:unit, :limits] begin
    using OpenMath
    obj = OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1), OMInteger(2)])
    @test count_nodes(obj) == 4
end
