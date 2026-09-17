# SPDX-License-Identifier: MIT
#
# REQ-CD-001..007, REQ-VAL-009 — Content Dictionaries and the symbol registry.
#
# The dictionaries are not shipped with this package (see REQ-CD-003 and decision
# D4): extracted dictionary content is a derived work whose licence asks more of
# it than a bundled asset should carry. So these tests use dictionaries written
# here, and the ones that need the real thing are tagged `:cd_data` and skipped
# unless `just corpus-fetch` has put them in place.

@testitem "cd: parse a dictionary" tags = [:unit, :cd] begin
    using OpenMath
    src = """
    <CD xmlns="http://www.openmath.org/OpenMathCD">
    <CDComment>licence text goes here</CDComment>
    <CDName>mycd</CDName>
    <CDBase>http://example.org/cd</CDBase>
    <CDReviewDate>2030-01-01</CDReviewDate>
    <CDStatus>experimental</CDStatus>
    <CDVersion>3</CDVersion>
    <CDRevision>7</CDRevision>
    <Description>A dictionary for testing.</Description>
    <CDDefinition>
      <Name>widget</Name>
      <Role>application</Role>
      <Description>The widget function.</Description>
      <CMP>widget(a) = a</CMP>
      <FMP>
        <OMOBJ xmlns="http://www.openmath.org/OpenMath">
          <OMA><OMS cd="relation1" name="eq"/><OMV name="a"/><OMV name="a"/></OMA>
        </OMOBJ>
      </FMP>
      <Example>
        <OMOBJ xmlns="http://www.openmath.org/OpenMath"><OMI>1</OMI></OMOBJ>
      </Example>
    </CDDefinition>
    <CDDefinition>
      <Name>gadget</Name>
      <Role>constant</Role>
      <Description>The gadget constant.</Description>
    </CDDefinition>
    </CD>
    """
    cd = OpenMath.parse_cd(src)

    @test cd.name == "mycd"
    @test cd.cdbase == "http://example.org/cd"
    @test cd.status == "experimental"
    @test cd.version == "3"
    @test cd.revision == "7"
    @test occursin("testing", cd.description)
    @test sort(collect(keys(cd.definitions))) == ["gadget", "widget"]

    w = cd.definitions["widget"]
    @test w.role == "application"
    @test occursin("widget function", w.description)
    # An FMP or Example is a complete OpenMath document, so our own reader does it.
    @test length(w.properties) == 1
    @test w.properties[1] isa OMObject
    @test length(w.examples) == 1
    @test w.examples[1].object == OMInteger(1)

    g = cd.definitions["gadget"]
    @test g.role == "constant"
    @test isempty(g.properties)
end

@testitem "cd: a dictionary with no CDBase falls back to the official base" tags = [
    :unit, :cd] begin
    using OpenMath
    cd = OpenMath.parse_cd("""
    <CD xmlns="http://www.openmath.org/OpenMathCD">
    <CDName>bare</CDName><CDStatus>official</CDStatus>
    <CDDefinition><Name>s</Name><Role>constant</Role></CDDefinition>
    </CD>
    """)
    @test cd.cdbase == OpenMath.CD_BASE
end

@testitem "cd: malformed dictionaries are rejected, not guessed at" tags = [:unit, :cd] begin
    using OpenMath
    for bad in ("<CD><CDDefinition><Name>x</Name></CDDefinition></CD>",   # no CDName
        "<CD><CDName>a</CDName><CDDefinition><Role>r</Role></CDDefinition></CD>",
        "<NotACD><CDName>a</CDName></NotACD>",
        "<CD><CDName>a</CDName>")                                  # truncated
        e = try
            OpenMath.parse_cd(bad)
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathError
    end
end

@testitem "cd: registry resolution is keyed on (cdbase, cd)" tags = [:unit, :cd] begin
    using OpenMath
    cd = OpenMath.parse_cd("""
    <CD xmlns="http://www.openmath.org/OpenMathCD">
    <CDName>mycd</CDName><CDBase>http://example.org/cd</CDBase>
    <CDStatus>experimental</CDStatus>
    <CDDefinition><Name>widget</Name><Role>application</Role>
      <Description>Does a thing.</Description></CDDefinition>
    </CD>
    """)
    reg = OpenMath.CDRegistry()
    OpenMath.register!(reg, cd)

    @test lookup(reg, OMSymbol("mycd", "widget"; cdbase = "http://example.org/cd")) !==
          nothing
    @test lookup(reg, OMSymbol("mycd", "widget"; cdbase = "http://example.org/cd")).role ==
          "application"
    # An unresolved symbol is `nothing`, not an error: a symbol from a dictionary
    # this registry has never seen is an ordinary occurrence.
    @test lookup(reg, OMSymbol("mycd", "nope"; cdbase = "http://example.org/cd")) ===
          nothing
    # The same cd name under a different base is a different dictionary (§2.1.4).
    @test lookup(reg, OMSymbol("mycd", "widget"; cdbase = "http://other.example/cd")) ===
          nothing
    @test describe(reg, OMSymbol("mycd", "widget"; cdbase = "http://example.org/cd")) ==
          "Does a thing."
end

@testitem "cd: a bare symbol resolves against the default base" tags = [:unit, :cd] begin
    using OpenMath
    cd = OpenMath.parse_cd("""
    <CD xmlns="http://www.openmath.org/OpenMathCD">
    <CDName>arith9</CDName><CDStatus>official</CDStatus>
    <CDDefinition><Name>plus</Name><Role>application</Role></CDDefinition>
    </CD>
    """)
    reg = OpenMath.CDRegistry()
    OpenMath.register!(reg, cd)
    bare = OMSymbol("arith9", "plus")
    @test bare.cdbase === nothing
    # The registry must agree with `resolve_cdbase` rather than have its own idea.
    @test lookup(reg, bare) !== nothing
    @test lookup(reg, resolve_cdbase(bare)) !== nothing
end

@testitem "cd: STS signatures give arities" tags = [:unit, :cd] begin
    using OpenMath
    sts = """
    <CDSignatures xmlns="http://www.openmath.org/OpenMathCDS" type="sts" cd="mycd">
    <Signature name="neg">
      <OMOBJ xmlns="http://www.openmath.org/OpenMath">
        <OMA><OMS name="mapsto" cd="sts"/><OMV name="G"/><OMV name="G"/></OMA>
      </OMOBJ>
    </Signature>
    <Signature name="div">
      <OMOBJ xmlns="http://www.openmath.org/OpenMath">
        <OMA><OMS name="mapsto" cd="sts"/><OMV name="G"/><OMV name="G"/><OMV name="G"/></OMA>
      </OMOBJ>
    </Signature>
    <Signature name="sum">
      <OMOBJ xmlns="http://www.openmath.org/OpenMath">
        <OMA><OMS name="mapsto" cd="sts"/>
          <OMA><OMS name="nassoc" cd="sts"/><OMV name="G"/></OMA>
          <OMV name="G"/></OMA>
      </OMOBJ>
    </Signature>
    </CDSignatures>
    """
    sigs = OpenMath.parse_sts(sts)
    @test sigs.cd == "mycd"
    @test sort(collect(keys(sigs.signatures))) == ["div", "neg", "sum"]

    # mapsto(T₁, …, Tₙ, Result): the last argument is the result type, so the
    # arity is one less than the number of arguments.
    @test OpenMath.sts_arity(sigs.signatures["neg"]) == 1
    @test OpenMath.sts_arity(sigs.signatures["div"]) == 2
    # …unless a parameter is wrapped in sts#nassoc, which makes it n-ary.
    @test OpenMath.sts_arity(sigs.signatures["sum"]) === nothing
end

@testitem "cd: validate_against_cds checks symbols and arity (REQ-VAL-009)" tags = [
    :unit, :cd] begin
    using OpenMath
    cd = OpenMath.parse_cd("""
    <CD xmlns="http://www.openmath.org/OpenMathCD">
    <CDName>mycd</CDName><CDStatus>official</CDStatus>
    <CDDefinition><Name>neg</Name><Role>application</Role></CDDefinition>
    <CDDefinition><Name>sum</Name><Role>application</Role></CDDefinition>
    </CD>
    """)
    sts = OpenMath.parse_sts("""
    <CDSignatures xmlns="http://www.openmath.org/OpenMathCDS" type="sts" cd="mycd">
    <Signature name="neg"><OMOBJ xmlns="http://www.openmath.org/OpenMath">
      <OMA><OMS name="mapsto" cd="sts"/><OMV name="G"/><OMV name="G"/></OMA>
    </OMOBJ></Signature>
    </CDSignatures>
    """)
    reg = OpenMath.CDRegistry()
    OpenMath.register!(reg, cd)
    OpenMath.register!(reg, sts, OpenMath.CD_BASE)

    @test isempty(validate_against_cds(OMS"mycd#neg"(OMInteger(1)), reg))
    @test isempty(validate_against_cds(OMS"mycd#sum"(OMInteger(1), OMInteger(2)), reg))

    unknown = validate_against_cds(OMS"mycd#nope"(OMInteger(1)), reg)
    @test any(i -> i.code === :unknown_symbol, unknown)
    @test any(i -> occursin("nope", i.message), unknown)

    wrong = validate_against_cds(OMS"mycd#neg"(OMInteger(1), OMInteger(2)), reg)
    @test any(i -> i.code === :wrong_arity, wrong)

    # An unknown dictionary is reported once, not once per symbol in it.
    foreign = OMSymbol("other", "f"; cdbase = "http://elsewhere.example/cd")(
        OMSymbol("other", "g"; cdbase = "http://elsewhere.example/cd"))
    @test count(i -> i.code === :unknown_cd, validate_against_cds(foreign, reg)) == 1
end

@testitem "cd: CD validation is separate from well-formedness" tags = [:unit, :cd] begin
    using OpenMath
    reg = OpenMath.CDRegistry()
    private = OMSymbol("mycd", "f"; cdbase = "http://example.org/cd")(OMInteger(1))
    # A document using a dictionary we have never heard of is well formed; it is
    # simply not resolvable here. `validate` must not conflate the two.
    @test isempty(validate(private))
    @test !isempty(validate_against_cds(private, reg))

    for obj in (OMInteger(0), OMVariable("x"), OMS"arith1#plus",
        OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")], OMVariable("x")))
        @test validate_against_cds(obj, reg) isa Vector{OpenMath.OMValidationIssue}
    end
end

@testitem "cd: an absent dictionary set is reported, not fetched (REQ-CD-007)" tags = [
    :unit, :cd] begin
    using OpenMath
    reg = OpenMath.CDRegistry()
    @test isempty(reg.dictionaries)
    @test OpenMath.isempty_registry(reg)
    # Resolution against an empty registry answers `nothing`; it must not reach
    # the network, and must not pretend the symbol is unknown-because-invalid.
    @test lookup(reg, OMS"arith1#plus") === nothing
    msg = sprint(show, reg)
    @test occursin("empty", lowercase(msg))
    @test occursin("corpus-fetch", msg) || occursin("load_cd_directory", msg)
end

@testitem "cd: the downloaded official dictionaries all parse" tags = [:unit, :cd, :cd_data] begin
    using OpenMath
    dir = joinpath(pkgdir(OpenMath), "refs", "cd", "cd", "Official")
    if !isdir(dir)
        @test_skip "run `just corpus-fetch` to download the dictionaries"
    else
        reg = OpenMath.load_cd_directory(dir)
        @test length(reg.dictionaries) == 38
        @test lookup(reg, OMS"arith1#plus") !== nothing
        d = describe(reg, OMS"arith1#plus")
        @test occursin("n-ary", d) && occursin("plus", d)

        sdir = joinpath(pkgdir(OpenMath), "refs", "cd", "sts")
        isdir(sdir) && OpenMath.load_sts_directory!(reg, sdir)
        @test arity(reg, OMS"arith1#unary_minus") == 1
        @test arity(reg, OMS"arith1#divide") == 2
        @test arity(reg, OMS"arith1#plus") === nothing

        # Every symbol every dictionary defines must resolve in the registry.
        missing_syms = String[]
        for (_, cd) in reg.dictionaries, (name, _) in cd.definitions

            lookup(reg, OMSymbol(cd.name, name; cdbase = cd.cdbase)) === nothing &&
                push!(missing_syms, "$(cd.name)#$(name)")
        end
        @test isempty(missing_syms)
    end
end
