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

@testitem "share_structure: it is the inverse of expand_references" tags = [
    :unit, :passes] begin
    using OpenMath
    # The property that matters. Sharing may change how an object is written; it
    # may not change what it means, and expansion is the definition of that.
    sub = OMS"arith1#plus"(OMVariable("x"), OMInteger(1))
    obj = OMS"arith1#times"(sub, sub, OMS"arith1#power"(sub, OMInteger(2)))

    shared = share_structure(obj)
    @test expand_references(shared) == expand_references(obj)
    @test canonicalize(shared) == canonicalize(obj)

    # And it did something: three copies became one definition and two references.
    @test count_nodes(shared) < count_nodes(obj)
    references = filter(n -> n isa OMReference, collect_nodes(shared))
    @test length(references) == 2
end

@testitem "share_structure: nothing to share leaves the object alone" tags = [
    :unit, :passes] begin
    using OpenMath
    obj = OMS"arith1#plus"(OMVariable("x"), OMInteger(1))
    @test share_structure(obj) === obj

    # A leaf is never worth sharing: an `OMR` costs more than `<OMI>1</OMI>` in
    # every encoding the standard defines. The threshold is a keyword, not a
    # hard rule, so a caller who knows better can say so.
    repeated_leaf = OMS"arith1#plus"(OMInteger(7), OMInteger(7), OMInteger(7))
    @test share_structure(repeated_leaf) === repeated_leaf
    @test count(n -> n isa OMReference,
        collect_nodes(share_structure(repeated_leaf; min_nodes = 1))) == 2
end

@testitem "share_structure: no reference precedes its definition (§3.2.5)" tags = [
    :unit, :passes] begin
    using OpenMath
    # The binary encoding forbids forward references outright, so a sharing pass
    # that emitted one would produce objects this package cannot write. Keeping
    # the *first* occurrence as the definition is what makes that impossible —
    # asserted here rather than left as a property of the traversal order.
    inner = OMS"arith1#plus"(OMVariable("x"), OMInteger(1))
    outer = OMS"arith1#times"(inner, OMInteger(2))
    obj = OMS"fns1#identity"(outer, inner, outer, inner)

    nodes = collect_nodes(share_structure(obj))
    ids = Dict{String, Int}()
    for (i, n) in enumerate(nodes)
        n isa OMReference && continue
        n.id === nothing || (ids[n.id] = min(get(ids, n.id, i), i))
    end
    for (i, n) in enumerate(nodes)
        n isa OMReference || continue
        target = OpenMath.reference_target(n)
        target === nothing && continue
        @test haskey(ids, target)
        @test ids[target] < i
    end
end

@testitem "share_structure: it is idempotent, and survives every encoding" tags = [
    :unit, :passes] begin
    using OpenMath
    sub = OMS"arith1#plus"(OMVariable("x"), OMS"transc1#sin"(OMVariable("y")))
    obj = OMObject(OMS"arith1#times"(sub, sub, sub))

    shared = share_structure(obj)
    @test share_structure(shared) == shared

    # Sharing is only useful if the encodings can carry it. The binary writer
    # already honours sharing that is in the object; until now nothing created
    # any, so that path was exercised by one hand-built fixture.
    for (format, write) in ((:xml, OpenMath.xml), (:json, OpenMath.json),
        (:mathml, OpenMath.mathml), (:binary, OpenMath.binary))
        back = OpenMath.parse(write(shared); format = format)
        @test canonicalize(back) == canonicalize(obj)
    end
end

@testitem "share_structure: an id something points at is never taken away" tags = [
    :unit, :passes] begin
    using OpenMath
    # If a node already carries an id that an existing OMR names, replacing that
    # node with a reference would delete the anchor and leave the other reference
    # dangling. So such a node may serve as a definition and may not be replaced.
    sub = OMS"arith1#plus"(OMVariable("x"), OMInteger(1))
    second = OMApplication(OMS"arith1#plus",
        [OMVariable("x"), OMInteger(1)]; id = "keep")
    obj = OMS"fns1#identity"(sub, second, OMReference("#keep"))

    shared = share_structure(obj)
    kept = filter(n -> !(n isa OMReference) && n.id == "keep", collect_nodes(shared))
    @test length(kept) == 1
    @test expand_references(shared) == expand_references(obj)

    # A minted id never collides with one already in the document.
    minted = OMApplication(OMS"arith1#times", [sub, sub]; id = "s1")
    ids = [n.id
           for n in collect_nodes(share_structure(minted))
           if !(n isa OMReference) && n.id !== nothing]
    @test length(ids) == length(unique(ids))
end
