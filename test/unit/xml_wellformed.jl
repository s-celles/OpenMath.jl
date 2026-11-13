# SPDX-License-Identifier: MIT
#
# XML 1.0 well-formedness, now decided by `XML.jl` at `wellformed = :strict`
# (decision D1). Every document below is ill-formed and was *accepted* by the
# hand-written tokenizer this package used to carry — found by probing it on
# 2026-11-12, just before it was replaced. Each must now be refused, and refused
# with an `OpenMathParseError` rather than whatever `XML.jl` raises (REQ-SEC-001).

@testitem "XML: ill-formed documents the old tokenizer accepted are refused" tags = [
    :unit, :xml] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    cases = [
        # §2.5: "--" must not occur within a comment.
        "-- in a comment" => "<OMOBJ$(ns)><!-- a -- b --><OMI>1</OMI></OMOBJ>",
        # §3.1: attributes are separated by white space.
        "attributes not separated" => "<OMOBJ$(ns)><OMS cd=\"a\"name=\"b\"/></OMOBJ>",
        # §4.1: a hexadecimal character reference is written `&#x`, lower case.
        "&#X character reference" => "<OMOBJ$(ns)><OMSTR>&#X41;</OMSTR></OMOBJ>",
        # §2.2 and WFC Legal Character: U+0000 is not a character of XML.
        "&#0; character reference" => "<OMOBJ$(ns)><OMSTR>&#0;</OMSTR></OMOBJ>",
        # §2.2: nor is a raw C0 control other than tab, newline and CR.
        "raw U+0001" => "<OMOBJ$(ns)><OMSTR>\x01</OMSTR></OMOBJ>",
        # §2.6: targets matching [Xx][Mm][Ll] are reserved.
        "reserved PI target" => "<OMOBJ$(ns)><?XmL y?><OMI>1</OMI></OMOBJ>",
        # §2.8: this is XML 1.0; `version="2.0"` is not a version of it.
        "XML declaration version 2.0" => "<?xml version=\"2.0\"?><OMOBJ$(ns)><OMI>1</OMI></OMOBJ>"
    ]
    for (label, src) in cases
        outcome = try
            read_xml(src)
            "accepted"
        catch err
            err isa OpenMath.OpenMathParseError ? "refused" : "raised $(typeof(err))"
        end
        @test "$(label): $(outcome)" == "$(label): refused"
    end
end

@testitem "XML: well-formedness errors still recover" tags = [:unit, :xml, :recover] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath\""""
    obj = read_xml("<OMOBJ$(ns)><!-- a -- b --><OMI>1</OMI></OMOBJ>"; mode = :recover)
    @test obj isa OMObject
    @test obj.object isa OMError
    @test length(obj.warnings) == 1
end

@testitem "XML: a DTD is refused before its declarations are read" tags = [
    :unit, :xml, :security] begin
    using OpenMath
    # Entities whose expansion is about 4 MiB: under `XML.jl`'s own bounds
    # (8 MiB and 100× the document), so it would expand them. With
    # `doctype = :refuse` the document is refused before any declaration is
    # read, so refusing it costs nothing like the expansion (REQ-XML-009).
    decls = "<!ENTITY e0 \"" * "a"^64 * "\">" *
            join("<!ENTITY e$(i) \"" * "&e$(i - 1);"^4 * "\">" for i in 1:8)
    src = "<!DOCTYPE OMOBJ [" * decls * "]><OMOBJ><OMSTR>&e8;</OMSTR></OMOBJ>"
    refuse() =
        try
            read_xml(src)
            nothing
        catch err
            err
        end
    e = refuse()
    @test e isa OpenMath.OpenMathParseError
    @test occursin("DOCTYPE", e.message)
    refuse()                                   # compiled
    @test @allocated(refuse()) < 1 << 20       # far below the 4 MiB expansion
end
