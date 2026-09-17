# SPDX-License-Identifier: MIT
#
# REQ-CAN-001..008 — canonical forms and normalisation passes.

@testitem "resolve_cdbase pushes inherited bases onto symbols" tags = [:unit, :passes] begin
    using OpenMath
    inner = OMSymbol("mycd", "sym")                       # no cdbase of its own
    a = OMApplication(OMSymbol("arith1", "plus"), [inner];
        cdbase = "http://example.org/cd")
    r = resolve_cdbase(a)
    @test r.applicant.cdbase == "http://example.org/cd"
    @test r.arguments[1].cdbase == "http://example.org/cd"
end

@testitem "resolve_cdbase defaults to the official CD base" tags = [:unit, :passes] begin
    using OpenMath
    r = resolve_cdbase(OMSymbol("arith1", "plus"))
    @test r.cdbase == OpenMath.CD_BASE == "http://www.openmath.org/cd"
end

@testitem "an inner cdbase overrides an outer one" tags = [:unit, :passes] begin
    using OpenMath
    inner = OMSymbol("c", "s"; cdbase = "http://inner.example/cd")
    a = OMApplication(OMSymbol("arith1", "plus"), [inner];
        cdbase = "http://outer.example/cd")
    r = resolve_cdbase(a)
    @test r.applicant.cdbase == "http://outer.example/cd"
    @test r.arguments[1].cdbase == "http://inner.example/cd"
end

@testitem "minimize_cdbase is the inverse of resolve_cdbase" tags = [:unit, :passes] begin
    using OpenMath
    a = OMApplication(OMSymbol("arith1", "plus"),
        [OMSymbol("arith1", "times"), OMInteger(1)])
    @test minimize_cdbase(resolve_cdbase(a)) == a
    # And the composite is stable: minimising twice changes nothing.
    m = minimize_cdbase(resolve_cdbase(a))
    @test minimize_cdbase(resolve_cdbase(m)) == m
end

@testitem "collapse_attributions flattens nested OMATTR" tags = [:unit, :passes] begin
    using OpenMath
    k1 = OMAttributePair(OMSymbol("ecc", "a"), OMInteger(1))
    k2 = OMAttributePair(OMSymbol("ecc", "b"), OMInteger(2))
    nested = OMAttribution([k2], OMAttribution([k1], OMVariable("x")))
    flat = collapse_attributions(nested)
    @test flat isa OMAttribution
    @test flat.object == OMVariable("x")
    # Innermost attributes apply first, so they come first in the flattened list.
    @test flat.attributes == [k1, k2]
end

@testitem "expand_references substitutes referents" tags = [:unit, :passes] begin
    using OpenMath
    shared = OMApplication(OMSymbol("arith1", "plus"),
        [OMInteger(1), OMInteger(2)]; id = "s1")
    root = OMApplication(OMSymbol("arith1", "times"),
        [shared, OMReference("#s1")])
    e = expand_references(root)
    @test e.arguments[2] == shared
    @test !any(n -> n isa OMReference, collect_nodes(e))
end

@testitem "expand_references detects cycles" tags = [:unit, :passes] begin
    using OpenMath
    # <OMA id="a"> … <OMR href="#a"/> … </OMA> — an element dominating itself.
    cyclic = OMApplication(OMSymbol("arith1", "plus"),
        [OMReference("#a")]; id = "a")
    @test_throws OpenMath.OpenMathReferenceError expand_references(cyclic)
end

@testitem "expand_references honours the node budget" tags = [:unit, :passes] begin
    using OpenMath
    shared = OMApplication(OMSymbol("arith1", "plus"),
        [OMInteger(1), OMInteger(2)]; id = "s1")
    root = OMApplication(OMSymbol("arith1", "times"),
        [shared, OMReference("#s1"), OMReference("#s1")])
    @test_throws OpenMath.OpenMathLimitError begin
        with_limits(OMLimits(; max_nodes = 4)) do
            expand_references(root)
        end
    end
end

@testitem "canonicalize is idempotent (P1)" tags = [:unit, :passes] begin
    using OpenMath
    k = OMAttributePair(OMSymbol("ecc", "a"), OMInteger(1))
    obj = OMApplication(
        OMSymbol("arith1", "plus"),
        [OMAttribution([k], OMAttribution([k], OMVariable("x"))),
            OMInteger(BigInt(2)^70)];
        cdbase = "http://example.org/cd"
    )
    c1 = canonicalize(obj)
    c2 = canonicalize(c1)
    @test c1 == c2
    @test isequal_with_ids(c1, c2)
end

@testitem "canonicalize resolves, flattens and expands" tags = [:unit, :passes] begin
    using OpenMath
    c = canonicalize(OMApplication(OMSymbol("arith1", "plus"), [OMInteger(1)]))
    @test c.applicant.cdbase == OpenMath.CD_BASE
end

@testitem "external references are not dangling references" tags = [:unit, :passes] begin
    using OpenMath
    # Standard §3.1.2: an OMR may name an object in *another* document. The binary
    # encoding gives the two cases separate tokens — 30 internal, 31 external —
    # precisely because they are not the same thing. Treating an external
    # reference as broken would make every document that cites another unusable.
    # Found by the official scscp1 Content Dictionary, which does exactly this.
    ext = OMReference("scscp://somehost.somedomain:26133/q9t4eX")
    @test !isinternal(ext)
    @test reference_target(ext) === nothing
    @test isinternal(OMReference("#s1"))
    @test reference_target(OMReference("#s1")) == "s1"

    obj = OMApplication(OMSymbol("arith1", "plus"), [ext, OMInteger(1)])
    @test isempty(validate(obj))                 # not an error
    @test expand_references(obj) == obj          # survives expansion untouched
    @test canonicalize(obj).arguments[1] == ext

    # An internal reference with no target is still an error.
    bad = OMApplication(OMSymbol("arith1", "plus"), [OMReference("#nowhere")])
    @test any(i -> i.code === :dangling_reference, validate(bad))
    @test_throws OpenMath.OpenMathReferenceError expand_references(bad)
end
