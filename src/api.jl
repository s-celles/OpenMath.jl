# SPDX-License-Identifier: MIT
#
# The public entry points (REQ-API-001, REQ-API-002).

"""
    OpenMath.parse(src; format = :auto, mode = :strict) -> OMObject

Decode an OpenMath document.

`format` is `:auto`, `:xml`, `:mathml`, `:json` or `:binary`. `:auto` determines the
encoding from the leading bytes. `mode` is `:strict`, `:lenient` or `:recover`;
see [`read_xml`](@ref).

`strict` applies only to MathML. The default refuses anything outside Strict
Content MathML; `strict = false` applies the transformation of MathML 4
Appendix F, which is defined normatively — so it is a rule rather than a guess.
See [`read_mathml`](@ref).

# Examples
```jldoctest
julia> using OpenMath

julia> o = OpenMath.parse(\"\"\"
           <OMOBJ xmlns="http://www.openmath.org/OpenMath">
             <OMA><OMS cd="arith1" name="plus"/><OMI>1</OMI><OMV name="x"/></OMA>
           </OMOBJ>\"\"\");

julia> o.object
OMA(OMS(arith1#plus), OMI(1), OMV(x))
```
"""
function parse(src::AbstractString; format::Symbol = :auto, mode::Symbol = :strict,
        strict::Bool = true)
    # Recovery has to cover the *choice* of reader, not only the reading.
    # `sniff_format` raises on an empty input and the readers never see it, so
    # `:recover` raised on the emptiest document there is. An `ArgumentError`
    # from a bad `format` is a caller's mistake rather than a document's and
    # `with_recovery` passes it through, which is the right side of that line.
    return with_recovery(mode) do
        _parse(src, format, mode, strict)
    end
end

function _parse(src::AbstractString, format::Symbol, mode::Symbol, strict::Bool)
    fmt = format === :auto ? sniff_format(src) : format
    fmt === :mathml && return read_mathml(src; mode = mode, strict = strict)
    # Both XML encodings start with '<', so sniffing cannot separate them; the
    # document element does. `<math>` is Strict Content MathML, `<OMOBJ>` is the
    # innate XML encoding.
    fmt === :xml && return _looks_like_mathml(src) ?
           read_mathml(src; mode = mode, strict = strict) :
           read_xml(src; mode = mode)
    fmt === :json && return read_json(src; mode = mode)
    fmt === :binary && return read_binary(src; mode = mode)
    throw(ArgumentError(
        "format must be :auto, :xml, :mathml, :json or :binary, got $(repr(format))"))
end

"""
    OpenMath.parse(bytes::AbstractVector{UInt8}; format = :auto, mode = :strict)

Decode an OpenMath document held as bytes. The binary encoding (§3.2) is not
text, so it has this entry point as well as the string one.
"""
function parse(src::AbstractVector{UInt8}; format::Symbol = :auto,
        mode::Symbol = :strict)
    return with_recovery(mode) do
        fmt = format === :auto ? sniff_format(src) : format
        fmt === :binary ? read_binary(src; mode = mode) :
        parse(String(copy(Vector{UInt8}(src))); format = fmt, mode = mode)
    end
end

"""
    OpenMath.parsefile(path; format = :auto, mode = :strict) -> OMObject

Decode the OpenMath document in `path`.
"""
function parsefile(path::AbstractString; format::Symbol = :auto, mode::Symbol = :strict)
    size = try
        filesize(path)
    catch
        0
    end
    check_limit(:max_bytes, size, limits().max_bytes)
    return parse(read(path, String); format = format, mode = mode)
end

# The first element, ignoring an XML declaration and any comment.
function _looks_like_mathml(src::AbstractString)
    # The whole of this is a guess about which reader to call, so *nothing* here
    # may raise: the reader it chooses is where a malformed document gets its
    # error, with the right message and, in `:recover`, no error at all. The
    # tokenizer's construction is inside the `try` because it rejects invalid
    # UTF-8, and that rejection escaping from a sniff would bypass `:recover`
    # entirely — which is exactly what it did.
    try
        p = XMLPullParser(String(src))
        ev = next_event!(p)
        while !(ev isa XMLDocumentEnd)
            ev isa XMLStartElement && return localname(ev.name) == "math"
            ev = next_event!(p)
        end
    catch err
        err isa OpenMathError || rethrow()
    end
    return false
end

"""
    OpenMath.sniff_format(src) -> Symbol

Determine the encoding of `src` from its leading bytes: `:xml`, `:json` or
`:binary`.
"""
function sniff_format(src::AbstractString)
    i = 1
    n = ncodeunits(src)
    while i <= n
        b = codeunit(src, i)
        (b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d) || break
        i += 1
    end
    i > n && throw(OpenMathParseError("the input is empty"; offset = 1))
    return _sniff(codeunit(src, i))
end

"""
    OpenMath.sniff_format(bytes::AbstractVector{UInt8}) -> Symbol

The same, for bytes. A binary document begins with the object tag, [24] or
[24+64], which is neither `<` nor `{`.
"""
function sniff_format(src::AbstractVector{UInt8})
    for b in src
        (b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d) && continue
        return _sniff(b)
    end
    throw(OpenMathParseError("the input is empty"; offset = 1))
end

function _sniff(b::UInt8)
    b == UInt8('<') && return :xml
    b == UInt8('{') && return :json
    return :binary
end

# --- literals -----------------------------------------------------------------

# Decoding happens at macro-expansion time, so a typo in an embedded document is
# a compile error rather than a runtime surprise. The object is then rebuilt at
# run time from the same source, which keeps the macro a one-liner and avoids
# having to splice an arbitrary object graph into the syntax tree.
function _literal(src::AbstractString, format::Symbol)
    parse(src; format = format)          # validate now; fail here if it is wrong
    return :(OpenMath.parse($(String(src)); format = $(QuoteNode(format))))
end

"""
    om"…"

An OpenMath document literal, in whichever encoding the content declares. The
document is decoded at macro-expansion time, so a malformed literal is a compile
error.

# Examples
```jldoctest
julia> using OpenMath

julia> om\"\"\"{"kind":"OMOBJ","object":{"kind":"OMI","integer":1}}\"\"\"
OMOBJ(OMI(1))
```
"""
macro om_str(src)
    return _literal(src, :auto)
end

"""
    omxml"…"

An OpenMath XML document literal, decoded at macro-expansion time.
"""
macro omxml_str(src)
    return _literal(src, :xml)
end

"""
    omjson"…"

An OpenMath JSON document literal, decoded at macro-expansion time.
"""
macro omjson_str(src)
    return _literal(src, :json)
end
