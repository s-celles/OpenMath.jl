# SPDX-License-Identifier: MIT
#
# REQ-XML-001, REQ-XML-008, REQ-XML-009, REQ-SEC-001, REQ-API-007 — the pull
# tokenizer for the OpenMath XML subset (standard §3.1). See decision D1 in
# docs/src/design/xml-backend.md for why this is purpose-built.

@testitem "tokenizer: elements and attributes" tags = [:unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!, XMLStartElement, XMLEndElement,
                    XMLCharacters, XMLDocumentEnd
    p = XMLPullParser("""<OMOBJ version="2.0" id='a'><OMI>42</OMI></OMOBJ>""")

    e = next_event!(p)
    @test e isa XMLStartElement
    @test e.name == "OMOBJ"
    @test [a.name for a in e.attributes] == ["version", "id"]
    @test [a.value for a in e.attributes] == ["2.0", "a"]
    @test !e.selfclosed

    @test next_event!(p) isa XMLStartElement
    t = next_event!(p)
    @test t isa XMLCharacters
    @test t.text == "42"
    @test next_event!(p) isa XMLEndElement
    @test next_event!(p) isa XMLEndElement
    @test next_event!(p) isa XMLDocumentEnd
end

@testitem "tokenizer: self-closing elements" tags = [:unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!, XMLStartElement, XMLDocumentEnd
    p = XMLPullParser("""<OMS cd="arith1" name="plus"/>""")
    e = next_event!(p)
    @test e.selfclosed
    @test e.name == "OMS"
    @test next_event!(p) isa XMLDocumentEnd
end

@testitem "tokenizer: XML declaration, comments and PIs are skipped" tags = [:unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!, XMLStartElement, XMLDocumentEnd
    p = XMLPullParser("""<?xml version="1.0"?><!-- a comment --><?target data?><OMI>1</OMI>""")
    e = next_event!(p)
    @test e isa XMLStartElement
    @test e.name == "OMI"
end

@testitem "tokenizer: predefined and numeric entities" tags = [:unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!, XMLCharacters
    p = XMLPullParser("<OMSTR>&lt;&gt;&amp;&quot;&apos;&#65;&#x41;</OMSTR>")
    next_event!(p)
    @test next_event!(p).text == "<>&\"'AA"
end

@testitem "tokenizer: entities are expanded inside attribute values" tags = [:unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!
    p = XMLPullParser("""<OMV name="a&amp;b"/>""")
    @test next_event!(p).attributes[1].value == "a&b"
end

@testitem "tokenizer: CDATA sections" tags = [:unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!
    p = XMLPullParser("<OMSTR><![CDATA[ raw < & > text ]]></OMSTR>")
    next_event!(p)
    @test next_event!(p).text == " raw < & > text "
end

@testitem "tokenizer: whitespace in character data is preserved" tags = [:unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!
    p = XMLPullParser("<OMSTR>  two  spaces\n</OMSTR>")
    next_event!(p)
    @test next_event!(p).text == "  two  spaces\n"
end

@testitem "tokenizer: adjacent text, CDATA and entities merge into one event" tags = [
    :unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!, XMLCharacters, XMLEndElement
    p = XMLPullParser("<OMSTR>a<![CDATA[b]]>&amp;c</OMSTR>")
    next_event!(p)
    e = next_event!(p)
    @test e isa XMLCharacters
    @test e.text == "ab&c"
    @test next_event!(p) isa XMLEndElement
end

@testitem "tokenizer: a DTD is rejected (REQ-XML-009)" tags = [:unit, :xml] begin
    using OpenMath
    using OpenMath: XMLPullParser, next_event!
    for src in ("""<!DOCTYPE OMOBJ SYSTEM "om.dtd"><OMOBJ/>""",
        """<!DOCTYPE x [<!ENTITY e "boom">]><OMOBJ/>""")
        p = XMLPullParser(src)
        e = try
            next_event!(p)
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathParseError
        @test occursin("DOCTYPE", e.message) || occursin("entity", e.message)
        @test e.offset !== nothing
    end
end

@testitem "tokenizer: an undeclared entity is rejected" tags = [:unit, :xml] begin
    using OpenMath
    using OpenMath: XMLPullParser, next_event!
    p = XMLPullParser("<OMSTR>&xxe;</OMSTR>")
    next_event!(p)
    e = try
        next_event!(p)
        nothing
    catch err
        err
    end
    @test e isa OpenMath.OpenMathParseError
    @test occursin("xxe", e.message)
end

@testitem "tokenizer: malformed input reports a byte offset (REQ-API-007)" tags = [
    :unit, :xml] begin
    using OpenMath
    using OpenMath: XMLPullParser, next_event!, XMLDocumentEnd
    for src in ("<OMI>1", "<OMI", "<OMS cd=arith1/>", "<OMI></OMF>", "<>", "<OMI>1</OMI")
        p = XMLPullParser(src)
        e = try
            while !(next_event!(p) isa XMLDocumentEnd)
            end
            nothing
        catch err
            err
        end
        @test e isa OpenMath.OpenMathParseError
        @test e.offset isa Int
    end
end

@testitem "tokenizer: never throws anything but OpenMathError (REQ-SEC-001)" tags = [
    :unit, :xml] begin
    using OpenMath
    using OpenMath: XMLPullParser, next_event!, XMLDocumentEnd
    srcs = ["", "<", "</", "<!", "<!-", "<![CDATA[", "&", "&#", "&#x", "&#xZZ;",
        "<a b", "<a b=", "<a b=\"", "<a/", "<a></b>", "\xff\xfe", "<?", "<?x",
        "<a>\0</a>", "<a " * "x"^100, "]]>", "<a>&#999999999999;</a>"]
    for src in srcs
        r = try
            p = XMLPullParser(src)
            while !(next_event!(p) isa XMLDocumentEnd)
            end
            :ok
        catch err
            err isa OpenMath.OpenMathError ? :openmath_error : err
        end
        @test r === :ok || r === :openmath_error
    end
end

@testitem "tokenizer: namespace prefixes are separated from local names" tags = [
    :unit, :xml] begin
    using OpenMath: XMLPullParser, next_event!, localname, prefix
    p = XMLPullParser("""<om:OMOBJ xmlns:om="http://www.openmath.org/OpenMath"/>""")
    e = next_event!(p)
    @test e.name == "om:OMOBJ"
    @test localname(e.name) == "OMOBJ"
    @test prefix(e.name) == "om"
    @test localname("OMOBJ") == "OMOBJ"
    @test prefix("OMOBJ") == ""
end
