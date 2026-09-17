# The four encodings

The standard endorses four encodings of one object model, and OpenMath.jl
implements all four. They are interchangeable: reading any of them and writing
any other is lossless up to the normalisations [`canonicalize`](@ref) performs.

| Encoding | Standard | Media type | Read | Write |
|:---|:---|:---|:---|:---|
| XML | omstd20 §3.1 | `application/openmath+xml` | [`read_xml`](@ref) | [`OpenMath.xml`](@ref) |
| Binary | omstd20 §3.2 | `application/openmath+binary` | [`read_binary`](@ref) | [`OpenMath.binary`](@ref) |
| JSON | omstd20 §3.3 | `application/openmath+json` | [`read_json`](@ref) | [`OpenMath.json`](@ref) |
| Strict Content MathML | MathML 4 §4.1.3 | `application/mathml+xml` | [`read_mathml`](@ref) | [`OpenMath.mathml`](@ref) |

[`OpenMath.parse`](@ref) picks one from the leading bytes: `<` is XML (or MathML,
decided by the document element), `{` is JSON, anything else is binary.

```jldoctest
julia> using OpenMath

julia> e = OMObject(OMS"arith1#plus"(OMInteger(1), OMVariable("x")));

julia> all(f -> OpenMath.parse(f(e)) == e,
           (OpenMath.xml, OpenMath.json, OpenMath.mathml, OpenMath.binary))
true
```

## The binary encoding

Designed "to be more compact than the XML encodings, so that it can be more
efficient if large amounts of data are involved" (§3.2). It is the encoding
SCSCP uses on the wire.

```jldoctest
julia> using OpenMath

julia> bytes2hex(OpenMath.binary(OMObject(OMInteger(16))))
"18011019"
```

That is the object tag `[24]`, the small-integer tag `[1]` with its value byte,
and the end object tag `[25]` — four bytes for an integer that takes 78 in the
XML encoding.

### Reading a stream

Given an `IO`, [`read_binary`](@ref) consumes exactly one object and leaves the
rest of the stream alone, which is what a socket carrying a sequence of objects
needs:

```jldoctest
julia> using OpenMath

julia> io = IOBuffer(vcat(OpenMath.binary(OMObject(OMInteger(1))),
                          OpenMath.binary(OMObject(OMInteger(2)))));

julia> (read_binary(io).object, read_binary(io).object)
(OMI(1), OMI(2))
```

Given a byte vector the whole vector must be one document, since there is no
second reader to hand the remainder to.

### Choices the encoding forces

The standard leaves several things to the writer. What this package picks, and
why:

- **Integers** take the smallest of the four formats that fits, and the general
  form uses base 16. Base 256 is denser, and is the one GAP mis-decodes whenever
  a digit byte falls below `0x10` — silently returning a smaller number — so it is
  read but never written. All three bases are read.
- **Strings** have no UTF-8 token — §3.2.2 offers ISO-8859-1 (`[6]`) and UTF-16
  (`[7]`) and nothing else — so a string is written narrow when every character
  fits in a byte and as UTF-16 otherwise.
- **`cdbase`** is not an attribute anywhere in this encoding; it is token `[9]`,
  which scopes over exactly one following object. A document-level `cdbase`
  becomes a scope around the root, unless the root carries its own, in which case
  the outer one would affect nothing and is dropped.
- **The document tag** is `[24]`, which §3.2.6 keeps valid in OpenMath 2 and
  which is what the only other shipping implementation emits. `[24+64]` is used
  where it buys something: structure sharing, or a version other than `2.0`,
  which is the only thing its two version bytes can carry.
- **Sharing** is written only for objects some `OMR` actually points at, and
  always in the OpenMath 2 form. The OpenMath 1 per-kind tables of §3.2.4.1 are
  read and never written.
- **Streaming packets** are read and never written: splitting a basic object
  across packets is a producer's choice, and a reader that chokes on them is not
  a reader of this encoding.

### What does not round-trip

Two things, both mandated by the encoding rather than chosen here:

- **`id` strings.** §3.2.4.2 references shared objects by ordinal and has no
  field for an identifier, and the standard says plainly that "in the conversion
  from the XML to the binary encoding the identifiers on the objects are not
  preserved". The reader mints `t0`, `t1`, … for the objects that were flagged,
  so the *structure* survives exactly; only the names change.
- **A forward reference** — an `OMR` textually before the `id` it names — is
  legal XML and inexpressible here, because §3.2.5 forbids forward references.
  The writer raises `OpenMathConversionError` naming [`expand_references`](@ref)
  rather than inlining the target silently.

An `OMFOREIGN` whose `encoding` is the empty string comes back with `encoding =
nothing`: a length of zero is the only thing the token has to say it with.

The standard's own §3.2 is not self-consistent about the sharing flag, and the
reading this package follows is argued in [Decision D7](design/binary-backend.md).

## Strict Content MathML

The normative correspondence is with *Strict* Content MathML — the subset of
MathML 4 §4.1.3 that maps onto OpenMath element for element. The full Content
MathML language has constructs with no OpenMath counterpart, and guessing at them
is the usual way this bridge goes wrong, so non-strict input is refused:

```jldoctest
julia> using OpenMath

julia> OpenMath.parse("""<math xmlns="http://www.w3.org/1998/Math/MathML">
                           <apply><plus/><cn>1</cn></apply></math>""")
ERROR: OpenMathParseError: <plus> is not Strict Content MathML; the strict subset has no operator elements or presentation markup (MathML 4 §4.1.3) at byte 58 at /math/apply/plus
```

Reading the *non-strict* dialect is what [MathML.jl](https://github.com/SciML/MathML.jl)
does, and the two packages are complementary rather than alternatives.
