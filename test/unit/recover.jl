# SPDX-License-Identifier: MIT
#
# `:recover` mode (spec §5.3): never throws, unparseable subtrees become an
# OpenMath error object. For batch ingestion of a corpus nobody has vetted.

@testitem "recover: an unparseable subtree becomes an OpenMath error object" tags = [
    :unit, :recover] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath" version="2.0\""""
    src = "<OMOBJ$(ns)><OMA><OMS cd=\"arith1\" name=\"plus\"/>" *
          "<OMI>not-a-number</OMI><OMI>2</OMI></OMA></OMOBJ>"

    # Strict and lenient both refuse it.
    @test_throws OpenMath.OpenMathParseError OpenMath.parse(src; format = :xml)
    @test_throws OpenMath.OpenMathParseError OpenMath.parse(src;
        format = :xml, mode = :lenient)

    # Recover keeps the rest of the document and puts an error where the bad
    # element was — the structure around it is intact, which is the whole point.
    obj = OpenMath.parse(src; format = :xml, mode = :recover)
    app = obj.object
    @test app isa OMApplication
    @test app.applicant == OMSymbol("arith1", "plus")
    @test length(app.arguments) == 2
    @test app.arguments[2] == OMInteger(2)

    bad = app.arguments[1]
    @test bad isa OMError
    # `moreerrors#encodingError` and not `error#unexpected_symbol`: the official
    # `error` CD has three symbols and all three are about a *symbol* — one not
    # in a dictionary, one not implemented, one whose dictionary is absent. None
    # of them describes a malformed integer, and saying one did would state
    # something false in a vocabulary other implementations read.
    @test bad.head == OMSymbol("moreerrors", "encodingError")
    @test length(bad.arguments) == 1
    @test bad.arguments[1] isa OMString
    @test occursin("not-a-number", bad.arguments[1].value)
end

@testitem "recover: it never throws on any parse failure" tags = [:unit, :recover] begin
    using OpenMath
    ns = """ xmlns="http://www.openmath.org/OpenMath" version="2.0\""""
    cases = [
        "<OMOBJ$(ns)><OMFROB/></OMOBJ>",                       # unknown element
        "<OMOBJ$(ns)><OMS cd=\"arith1\"/></OMOBJ>",            # missing attribute
        "<OMOBJ$(ns)><OMV name=\"9bad\"/></OMOBJ>",            # invalid name
        "<OMOBJ$(ns)><OMA></OMA></OMOBJ>",                     # empty application
        "<OMOBJ$(ns)><OMF dec=\"zzz\"/></OMOBJ>",              # bad float
        "<OMOBJ$(ns)><OMB>!!!</OMB></OMOBJ>",                  # bad base64
        "<OMOBJ$(ns)><OMA><OMS cd=\"a\" name=\"b\"/>",         # truncated
        "not xml at all",                                      # not even a document
        "",                                                    # empty
        "<html><body>hello</body></html>"                      # a different language
    ]
    for src in cases
        obj = OpenMath.parse(src; format = :xml, mode = :recover)
        @test "$(first(src, 24)): returned an object" ==
              "$(first(src, 24)): $(obj isa OMObject ? "returned an object" : "did not")"
        # And whatever came back is a well-formed OpenMath object, not a
        # half-built one: it can be written out and read back.
        @test OpenMath.parse(OpenMath.xml(obj); format = :xml, mode = :recover) isa OMObject
    end
end

@testitem "recover: a resource limit still throws" tags = [:unit, :recover] begin
    using OpenMath
    # Deliberately *not* recovered. Limits exist to stop work on hostile input;
    # turning a depth bomb into an error node and carrying on would mean the
    # attacker still gets the work done (REQ-SEC-002). `:recover` is for
    # documents that are broken, not for documents that are attacking you.
    deep = "<OMOBJ xmlns=\"http://www.openmath.org/OpenMath\" version=\"2.0\">" *
           repeat("<OMA><OMS cd=\"a\" name=\"b\"/>", 200) *
           repeat("</OMA>", 200) * "</OMOBJ>"
    with_limits(OMLimits(; max_depth = 10)) do
        @test_throws OpenMath.OpenMathLimitError OpenMath.parse(deep;
            format = :xml, mode = :recover)
    end
end

@testitem "recover: every text encoding recovers, not just XML" tags = [:unit, :recover] begin
    using OpenMath
    # Half-present is worse than either state: a caller who passes `mode` cannot
    # be expected to know which readers honour it.
    bad = Dict(
        :xml =>
            "<OMOBJ xmlns=\"http://www.openmath.org/OpenMath\" version=\"2.0\">" *
            "<OMI>zz</OMI></OMOBJ>",
        :json => "{\"kind\":\"OMOBJ\",\"object\":{\"kind\":\"OMI\",\"integer\":\"zz\"}}",
        :mathml =>
            "<math xmlns=\"http://www.w3.org/1998/Math/MathML\">" *
            "<cn type=\"integer\">zz</cn></math>")
    for (format, src) in bad
        @test_throws OpenMath.OpenMathParseError OpenMath.parse(src; format = format)
        obj = OpenMath.parse(src; format = format, mode = :recover)
        @test "$(format): recovered" ==
              "$(format): $(obj isa OMObject ? "recovered" : "did not")"
        errors = filter(n -> n isa OMError, collect_nodes(obj))
        @test "$(format): has an error node" ==
              "$(format): $(isempty(errors) ? "has none" : "has an error node")"
        @test all(e -> e.head == OMSymbol("moreerrors", "encodingError"), errors)
    end
end

@testitem "recover: a clean document is untouched" tags = [:unit, :recover] begin
    using OpenMath
    src = "<OMOBJ xmlns=\"http://www.openmath.org/OpenMath\" version=\"2.0\">" *
          "<OMA><OMS cd=\"arith1\" name=\"plus\"/><OMI>1</OMI><OMI>2</OMI></OMA></OMOBJ>"
    @test OpenMath.parse(src; format = :xml, mode = :recover) ==
          OpenMath.parse(src; format = :xml)
end

@testitem "recover: the binary encoding recovers per document, not per subtree" tags = [
    :unit, :recover] begin
    using OpenMath
    # A byte format has nothing to resynchronise on: one wrong length and every
    # subsequent byte is misread, so there is no way to skip a bad subtree and
    # keep the rest. That argument is sound, and this reader used it to raise in
    # `:recover` too — conflating "cannot recover a subtree" with "cannot
    # recover". `:recover` promises only that it does not raise, and a
    # whole-document error object honours that without pretending otherwise.
    #
    # Found by the fuzz campaign on its first input, once `:recover` was added to
    # the modes it exercises. The mode had shipped two commits earlier and
    # nothing had ever fed it a malformed byte stream.
    truncated = hex2bytes("18091a687474703a2f2f7777772e6f70656e6d6174682e6f72672f636410080902")

    @test_throws OpenMath.OpenMathParseError OpenMath.parse(truncated; format = :binary)
    obj = OpenMath.parse(truncated; format = :binary, mode = :recover)
    @test obj isa OMObject
    @test obj.object isa OMError
    @test obj.object.head == OMSymbol("moreerrors", "encodingError")
    @test !isempty(obj.warnings)

    # A clean binary document is untouched.
    good = OpenMath.binary(OMObject(OMS"arith1#plus"(OMInteger(1), OMInteger(2))))
    @test OpenMath.parse(good; format = :binary, mode = :recover) ==
          OpenMath.parse(good; format = :binary)
end

@testitem "recover: choosing the reader is covered too" tags = [:unit, :recover] begin
    using OpenMath
    # `sniff_format` raises on an empty input, before any reader is chosen, so
    # `:recover` raised on the emptiest document there is. Recovery has to cover
    # the *choice* of reader, not only the reading. Found by the fuzz campaign.
    for src in ("", " ", "\0", "not a document at all")
        obj = OpenMath.parse(src; mode = :recover)
        @test "$(repr(first(src, 8))): recovered" ==
              "$(repr(first(src, 8))): $(obj isa OMObject ? "recovered" : "did not")"
    end
    @test OpenMath.parse(UInt8[]; mode = :recover) isa OMObject

    # A bad `format` is the caller's mistake, not the document's, and still
    # raises: recovering from it would hide a typo in the calling code.
    @test_throws ArgumentError OpenMath.parse("<OMOBJ/>"; format = :frobnicate,
        mode = :recover)
end
