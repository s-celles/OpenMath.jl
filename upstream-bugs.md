# Upstream bugs

Defects and limitations found in dependencies or in reference implementations
while developing this package. Every entry records the **exact version** affected
so that a reader can reproduce it.

Entries here come from two places: `just oracle`, which runs the conformance
corpus through both this package and the reference implementation and compares
canonical forms; and `just corpus-fetch`, which harvests vectors from the official
Content Dictionaries and occasionally finds one that is not a valid document.
Every disagreement is triaged before it is written down: the document is first
validated with a third, independent XML parser (Python's expat), so that "the
oracle rejected it" never silently means "we produced something malformed".

## Template

```markdown
## <package> <version> — <one-line summary>

- **Found**: YYYY-MM-DD, during <phase / task>
- **Affected**: <package> v<x.y.z> (and Julia v<a.b.c> / rustc <x.y.z> where relevant)
- **Reported**: <link to the upstream issue, or "not yet">
- **Workaround**: <what this package does in the meantime, with a file reference>

### Reproducer

<the smallest input that shows it>

### Expected / actual
```

---

## Environment for every entry below

- **`openmath` crate**: v0.1.7, repository commit `06d2797`
  (<https://github.com/FlexiFormal/OpenMath>)
- **rustc**: 1.90.0 (1159e78c4 2025-09-14)
- **OpenMath.jl**: 0.0.1, Julia 1.13.0
- **Found**: 2026-09-17, roadmap Phase 2, running `just oracle` over the corpus
- **Independent check**: every document below is well-formed XML per Python 3.12
  expat, which reads the same content this package reads.
- **Reported**: no — see the note below.

The corpus is run through the oracle in two directions:

- `:read` — the corpus document → their reader → their writer → our reader.
  27 of 39 agree, 12 rejected.
- `:write` — the corpus document → our reader → **our writer** → their reader →
  their writer → our reader. 32 of 39 agree, 7 rejected. The five extra successes
  are documents our writer normalises into a form they can read: hexadecimal
  `OMI` becomes decimal, a namespace prefix becomes the default declaration, and
  `-0.0` and the subnormal are written with `dec=` rather than `hex=`.

Zero disagreements on meaning, in either direction. All 19 rejections across both
directions are the five limitations below.

---

## openmath 0.1.7 — hexadecimal `OMF` and `OMI` are not implemented

- **Corpus items**: `standard/omf-nan`, `omf-inf`, `omf-neginf`, `omf-negzero`,
  `omf-subnormal`, `omi-hexadecimal`, `omi-hexadecimal-negative`
- **Workaround**: none needed. `src/xml/reader.jl` implements both forms;
  `just oracle` records these as upstream limitations rather than failures.

### Reproducer

```xml
<OMOBJ xmlns="http://www.openmath.org/OpenMath" version="2.0"><OMF hex="7FF8000000000000"/></OMOBJ>
<OMOBJ xmlns="http://www.openmath.org/OpenMath" version="2.0"><OMI>x1F</OMI></OMOBJ>
```

### Expected / actual

Expected `NaN` and `31`. Actual: `parse error: hexadecimal not yet implemented`.

This matters more than it looks: standard §3.1.1 defines `hex=` as the *only*
way to write `NaN` and the infinities, since they have no decimal spelling. An
implementation without it cannot read a document containing them at all.

---

## openmath 0.1.7 — an empty `OMSTR` or `OMB` is rejected

- **Corpus items**: `standard/omstr-empty`, `standard/omb-empty`
- **Workaround**: none needed; `src/xml/reader.jl` accepts both.

### Reproducer

```xml
<OMOBJ xmlns="http://www.openmath.org/OpenMath" version="2.0"><OMSTR></OMSTR></OMOBJ>
<OMOBJ xmlns="http://www.openmath.org/OpenMath" version="2.0"><OMB></OMB></OMOBJ>
```

### Expected / actual

Expected the empty string and the empty byte sequence. Actual:
`parse error: text node expected in xml element`.

The reader appears to require a text node where the XML simply has none. The
standard places no lower bound on the length of either, and expat reports the
element content as absent rather than as an error.

---

## openmath 0.1.7 — namespace prefixes are not recognised

- **Corpus item**: `standard/namespace-prefixed`
- **Workaround**: none needed; `src/xml/reader.jl` resolves prefixes against the
  declarations in scope.

### Reproducer

```xml
<om:OMOBJ xmlns:om="http://www.openmath.org/OpenMath" version="2.0"><om:OMI>1</om:OMI></om:OMOBJ>
```

### Expected / actual

Expected `OMI(1)`. Actual: `parse error: unknown OpenMath element at 68`.

The element name is matched literally rather than resolved against the namespace
declarations in scope, so the prefixed spelling of a perfectly ordinary OpenMath
document is refused.

---

## openmath 0.1.7 — an entity reference inside `OMSTR` is rejected

- **Corpus item**: `standard/omstr-entities`
- **Workaround**: none needed; `src/xml/tokenizer.jl` expands the five predefined
  entities and numeric character references.

### Reproducer

```xml
<OMOBJ xmlns="http://www.openmath.org/OpenMath" version="2.0"><OMSTR>a &lt; b &amp; c</OMSTR></OMOBJ>
```

### Expected / actual

Expected `OMSTR("a < b & c")`, which is what expat reads. Actual:
`parse error: unknown OpenMath element at 69`.

Character data interrupted by an entity reference arrives as several events, and
the reader seems to treat the continuation as a new element. This is not an
exotic document: `&lt;` and `&amp;` are the only way to put `<` or `&` in a
string, so any `OMSTR` containing either is unreadable.

---

## openmath 0.1.7 — `OMR` structure sharing is not implemented

- **Corpus item**: `standard/omr-sharing`
- **Status**: **declared**, not a defect — the crate's README lists "structure
  sharing via OMR" under TODO, alongside the binary format and the official error
  Content Dictionaries.
- **Workaround**: none needed; `src/xml/reader.jl` reads `OMR`/`id` and
  `expand_references` resolves them, with cycle detection.

### Reproducer

```xml
<OMOBJ xmlns="http://www.openmath.org/OpenMath" version="2.0"><OMA><OMS cd="arith1" name="times"/><OMA id="s1"><OMS cd="arith1" name="plus"/><OMI>1</OMI><OMI>2</OMI></OMA><OMR href="#s1"/></OMA></OMOBJ>
```

### Expected / actual

Expected the reference to resolve to the element carrying `id="s1"`. Actual:
`parse error: unknown OpenMath element at 165`.

---

## OpenMath Content Dictionaries — three `scscp1` examples are not valid OpenMath

- **Found**: 2026-09-17, harvesting conformance vectors with `just corpus-fetch`
- **Affected**: <https://github.com/OpenMath/CDs>, `cd/Official/scscp1.ocd`
  (CDVersion 1, CDRevision 13, CDDate 2009-06-22). Note that despite its
  directory, this dictionary declares `<CDStatus>experimental</CDStatus>`, which
  lowers the severity considerably — see below.
- **Reported**: <https://github.com/OpenMath/CDs/issues/44> (2026-09-17)
- **Corpus items**: `invalid/cd-scscp1-error-memory-19`,
  `invalid/cd-scscp1-error-runtime-20`,
  `invalid/cd-scscp1-error-system-specific-21` — kept as negative cases, since a
  document the standard's own dictionary gets wrong is worth being able to reject.

### Reproducer

```xml
<OMOBJ xmlns="http://www.openmath.org/OpenMath">
  <OMATTR>
    <OMATP>
      The header goes here
    </OMATP>
    <OMA><OMS cd="scscp1" name="procedure_terminated"/>…</OMA>
  </OMATTR>
</OMOBJ>
```

### Expected / actual

An `OMATP` holds a sequence of (key, value) pairs — an `OMS` followed by an
object — and admits no character data. These three examples put the prose
placeholder "The header goes here" there instead, so they are well-formed XML but
not well-formed OpenMath. They are clearly meant as illustrative sketches of an
SCSCP message; the surrounding `CDComment` does not say so, and nothing marks
them as incomplete.

**Severity: low**, and an earlier draft of this entry overstated it by calling
`scscp1` an official dictionary. It sits in `cd/Official/` but declares
`<CDStatus>experimental</CDStatus>`, and placeholder text in an experimental
dictionary is a very different thing from an error in a normative one. It is
worth reporting mostly because these files are the natural source of test vectors
for any implementation: 342 objects were harvested from the 38 files in
`cd/Official/` and exactly these three are not documents.

There is a second, arguably more useful observation in the same place, reported
separately as <https://github.com/OpenMath/CDs/issues/45>. Two of the 38 files in
`cd/Official/` — `scscp1.ocd` and `scscp2.ocd` — declare themselves experimental.
Anyone treating that directory as "the official set", which its name invites,
silently picks up experimental content. Both also carry a `CDReviewDate` of
2017-12-31, now long past.

The two were filed separately on purpose: the first has a patch and a clear close
condition, the second is a governance question only the Society can answer, and
bundling them would have blocked the easy fix behind the open question.

## GAP openmath 11.5.5 — its XML and binary writers disagree about one string

- **Found**: 2026-09-18, following a question about whether to adopt GAP's
  conventions wholesale
- **Affected**: GAP `openmath` package v11.5.5, GAP 4.15.1. The binary encoding
  code is unchanged since 2016.
- **Reported**: **no — recorded and deliberately not filed** (see below)
- **Workaround**: none needed on our side, and none possible. We write what
  §3.2.2 defines; a non-ASCII string does not survive an exchange with GAP in
  either direction, and that is documented in `docs/src/round-trip.md`.

### The shortest statement

GAP writes one string in its two encodings, and they denote different objects.

```
GAP writes "caf\303\251" (café, as UTF-8 bytes, which is how GAP holds text)

  XML     <OMSTR>café</OMSTR>                     4 characters
  binary  06 05 63 61 66 c3 a9                    5 characters: c a f Ã ©
```

Read by any conforming reader, those are not the same `OMSTR`. The standard's
whole premise is that its encodings denote the same objects.

### Why

GAP strings are byte sequences with no declared encoding — `Length("caf\303\251")`
is **5**, not 4. Its binary writer is exactly faithful to that model: it emits
`Length(s)` as the count and the bytes raw.

§3.2.2 offers two string encodings and neither is UTF-8:

> In the case of LATIN-1 it is encoded as the one byte character string tags
> (token identifier 6) […] there is **the number of characters** […] followed by
> **the characters** in the string.

Token 6 is ISO-8859-1: one byte per character. Token 7 is UTF-16, and exists
precisely for what Latin-1 cannot carry; GAP never emits it. So GAP's UTF-8 bytes
under token 6 say something other than what GAP meant.

XML escapes this because a document declares its encoding and the bytes pass
through as UTF-8. The binary encoding has no declaration — the *token* is the
declaration — which is where GAP's byte model and OpenMath's Unicode character
model (§2.1.1) part company.

### Reproducer

```gap
gap> x := "caf\303\251";; Length(x);
5
gap> s := OutputTextFile("b.bin", false);; SetPrintFormattingStatus(s, false);;
gap> OMPutObject(OpenMathBinaryWriter(s), x);; CloseStream(s);
gap> OMPrint(x);
<OMOBJ xmlns="http://www.openmath.org/OpenMath" version="2.0">
	<OMSTR>café</OMSTR>
</OMOBJ>
```

```sh
$ xxd -p b.bin
180605636166c3a919          # token 6, length 5, raw UTF-8 bytes
```

Verified for `λ` too: `18 06 02 ce bb 19`, which §3.2.2 reads as `Î»`.

### Where the blame sits

Mostly upstream of GAP. §3.2 specifies UTF-8 for content dictionary names, symbol
names, variable names, `cdbase` URIs and foreign encoding attributes — and offers
no UTF-8 string token, so `OMSTR` alone must be Latin-1 or UTF-16. See item 7 of
the standard entry above. An implementation holding UTF-8 text is pushed toward
exactly what GAP did: pass the bytes through.

It remains GAP's defect in the narrow sense — it *could* transcode, and its own
two encodings disagreeing is a fact about GAP alone. But the standard made the
correct path the unnatural one, and that is the more useful thing to fix.

### Why it is recorded and not filed

**Decision, 2026-09-18.** Unlike issues #31 and #32, this is not a bug with a
one-line fix. It is a mismatch between GAP's string model and OpenMath's, and the
conformant remedy — transcode to Latin-1 where it fits and UTF-16 otherwise, both
ways — would change bytes GAP has emitted since 2016. That is a compatibility
decision for its maintainers, not a patch, and filing it would be asking them to
take it on someone else's timetable.

Nothing in this package depends on the outcome. We write what §3.2.2 defines, our
own round trip is exact, and the divergence is documented where a user who
interoperates with GAP will meet it.

### A note on how it was nearly missed

`just oracle-gap` reported **36/36 agreeing** on these very strings, and was
right to. It compares values through GAP's own equality, GAP's bytes come back to
GAP unchanged, and a disagreement about what bytes *mean* is invisible to that
comparison. Its string sample was also ASCII-only, which cannot distinguish two
encodings at all.

Both are fixed — the sample has non-ASCII entries and a second kind of probe
compares interpretations rather than values — but the general point is the
oracle's, not the defect's: **an oracle that compares through one
implementation's equality cannot see the two disagreeing about semantics.**

## OpenMath 2.0 standard §3.2 — six defects and one undecidable question

- **Found**: 2026-09-17, roadmap Phase 4, transcribing the standard's worked byte
  sequences before writing the codec
- **Affected**: *The OpenMath Standard*, version 2.0, revision 3 (2019-07-01),
  <https://openmath.org/standard/om20-2019-07-01/omstd20.html>
- **Reported**: <https://github.com/OpenMath/OMSTD/issues/72>
- **Workaround**: `docs/src/design/binary-backend.md` records which reading this
  package follows and why; `test/corpus/binary-vectors.toml` carries every
  sequence below verbatim, with the repaired form beside it.

These are not oracle findings. The reference crate leaves §3.2 unimplemented, so
the oracle this repository already builds says nothing about it. They came out of
transcribing the standard's own examples as test vectors *first* and finding that
two of the three do not decode.

GAP's `openmath` package **does** implement this encoding, and checking it
against these figures is roadmap Phase 4b. If it reproduces Figure 3.6 as
printed, the defect has propagated into a shipping implementation and this report
becomes more urgent, not less.

### 1. Figure 3.5 mixes the two sharing mechanisms

Byte 1 is `0x58` = `[24+64]`, which §3.2.4.2 says selects the OpenMath 2
interpretation of the sharing flag. Bytes 41–44 then use the OpenMath 1
interpretation of §3.2.4.1, and the figure's own Meaning column says so: it
glosses `0x48 0x01` as "reference to second symbol seen (arith1:plus)" and
`0x45 0x00` as "reference to first variable seen (x)".

Under the header the figure declares, `0x48` opens a symbol whose Content
Dictionary name is one byte long, and a decoder desynchronises at byte 42.

```
58 02 00 10 08 06 05 "arith1times" 10 08 06 04 "arith1plus"
05 01 78 05 01 79 11 10 48 01 45 00 05 01 7a 11 11 19
```

Replacing `58 02 00` with `18` makes every one of the figure's byte annotations
come out exactly right, which is the evidence that the body is what was meant and
the header is the slip.

### 2. Figure 3.6 byte 27 is `0x00` where it must be `0x01`

The Meaning column reads "to the second shared object", which is ordinal 1. As
printed, the figure decodes to `f(f(f(a,a),f(a,a)), f(a,a))` rather than to the
object of Figure 3.1 it is captioned as encoding,
`f(f(f(a,a),f(a,a)), f(f(a,a),f(a,a)))`.

The bytes are well formed, so nothing but the caption catches this. It is a wrong
answer, not a parse failure, which makes it the more dangerous of the two: an
implementer checking their decoder against the figure would "fix" a correct
decoder to reproduce it.

### 3. Whether a shared tag carries an identifier is undecidable from the text

For: Figure 3.3, in 31 of its 32 shareable rows, and §3.2.2, which describes the
symbol identifier in prose and at length. Against: Figure 3.6, whose byte 8 is
`0x50` = `[16+64]` and whose byte 9 is `0x05`, a variable tag, with no length and
no identifier between them; §3.2.4.2 twice ("corresponds to the information,
**whether** an `id` attribute is set"; "the identifiers on the objects are not
preserved"); and §3.2.5, which describes the reader's array purely positionally.

The two readings produce incompatible byte streams. A decoder written to the
grammar cannot read Figure 3.6, and vice versa, and the byte after `[16+64]` is a
length under one reading and a tag under the other, so they cannot be told apart
on the wire.

An earlier draft of this entry argued that the grammar "contradicts itself, so it
cannot be the authority". An audit of all 33 `+64` alternatives refuted that: 31
carry an identifier, `start → [24+64] [m] [n] object [25]` correctly carries
none, and exactly one shareable row — `[6+64]` — is missing it. That is a typo,
not a design statement, and it is listed separately below.

### 4. Figure 3.3, two slips in the `string` production

```
[6+64]      [n]     bytes:n           ← the only shareable row with no id field
[7+64]      [n] [m] bytes:n  id:m     ← bytes:n, but token 7 is UTF-16: bytes:2n
```

Every other token-7 alternative — `[7]`, `[7+32]`, `[7+128]`, `[7+32+128]`,
`[7+64+128]` — gives `bytes:2n`.

### 5. The only base-256 example cannot fail

§3.2.2 gives exactly one worked example of base-256 digits,
`0x02 0x04 0xab 0xFF 0xFF 0xFF 0xF1`, and every digit byte in it is `≥ 0x10`. An
implementation that renders each byte as hexadecimal without padding to two
characters — the obvious slip, since base 256 is the one base whose digits are
bytes rather than characters — passes it anyway. GAP has exactly that defect and
has shipped it since 2016 (issue #31 above). The issue proposes
`0x02 0x03 0xab 0xFF 0x01 0xFF` as a second vector.

### How they got there

Figure 3.3 reads like an edit of OpenMath 1.1's Figure 4.3, made where the meaning
of `+64` changed. In OpenMath 1 a `+64` row was a back-reference and its entire
payload was one index byte:

```
OM 1.1, Figure 4.3
  variable → [5] [n] varname:n | [5+128] {n} varname:n | [5+64] [n]
  symbol   → [8] [n] [m] cdname:n symbname:m | … | [8+64] [n]
  string   → [6] [n] chars:n | [6+128] {n} chars:n
           | [7] [n] chars:2n | [7+128] {n} chars:2n | [7+64] [n]
```

In OpenMath 2 those rows had to become "the object itself, plus whatever marks it
as shared", and the two defective productions are exactly what a partial edit
would leave: `[6+64] [n] bytes:n` is the row shape with the ordinary payload
restored and no identifier, and `[7+64] [n] [m] bytes:n id:m` gained an identifier
but kept `bytes:n`, which is the token-6 payload — OpenMath 1's `[7+64] [n]` had
no payload to copy. Note also that OpenMath 1's grammar has **no `[6+64]` row at
all**, though §3.2.4.1 says 8-bit and 16-bit strings share separately: the row was
missing before it was wrong.

Figure 3.5 fits the same account. Its body is valid OpenMath 1 and only its header
is OpenMath 2 — an example carried over and given a new first byte.

This is offered as an account, not a finding. What supports it is that every
defect in §3.2 is either in a `+64` row or in a figure that predates the OpenMath
2 sharing mechanism, and none is anywhere else.

### 7. §3.2 has no UTF-8 string, while mandating UTF-8 for everything else in it

Not a slip; a gap in the design, and the one with a live consequence.

An audit of every encoding named in §3.2.2:

| Field | Encoding the standard specifies |
|:--|:--|
| Content Dictionary name, symbol name | **UTF-8** |
| the `id` of a shared object | **UTF-8** |
| variable name | **UTF-8** |
| `cdbase` URI (token 9) | **UTF-8** |
| the `encoding` attribute of a foreign object | **UTF-8** |
| a foreign payload | "should be encoded in **UTF-8** to produce a stream of bytes" |
| **`OMSTR`** | **ISO-8859-1 (token 6) or UTF-16 (token 7)** |

So a conforming document carries a variable named `λ` as UTF-8 and a *string*
containing `λ` as UTF-16, in adjacent tokens. There is no UTF-8 string token at
all.

That matters because the other three endorsed encodings are UTF-8 native — XML
and Strict Content MathML by declaration, JSON by definition — so §3.2 is the
only place in the standard where an implementation holding UTF-8 text cannot pass
it through. The natural thing to do is non-conformant, and the conformant thing
requires transcoding a string differently from the variable name beside it.

**This is not hypothetical.** GAP's `openmath` package writes UTF-8 bytes under
token 6, which makes its own XML and binary writers disagree about the same
string — recorded below. It is fair to say the standard led it there.

The binary encoding dates from OpenMath 1, when Latin-1 and UTF-16 were the
conventional pair. OpenMath 2 revised §3.2 substantially — base-256 integers,
`cdbase` scopes, foreign objects, streaming, all of them specifying UTF-8 — and
did not revisit the string tokens.

**Suggested**: a UTF-8 string token, which the unassigned identifiers leave room
for; or, at minimum, an erratum noting the asymmetry, so that an implementer
reading "the encoding attribute is encoded in UTF-8" three paragraphs earlier is
not led to assume the same of `OMSTR`.

### Why this matters more than a typo usually would

§3.2 is the encoding SCSCP puts on the wire, and it is the one encoding with no
schema: an XML or JSON document can be validated against Relax NG or the
TypeScript definition in Appendix F, and a binary stream can only be checked
against prose and three figures. Two of those three figures do not decode, and
the grammar they are meant to illustrate is inconsistent with them and with
itself. An implementer has nothing left to check against.

Precedent exists for fixing exactly this kind of thing: revision 1 (July 2017)
corrected the base-256 integer example in the same section, where "the 0xab
(base 256/positive) byte was omitted and 0xF1 had been written 0xFI", and
replaced the float example, which "was wrong".

## GAP openmath 11.5.5 — a base-256 digit byte below 0x10 loses its leading zero

- **Found**: 2026-09-17, roadmap Phase 4b, `just oracle-gap`
- **Reported**: <https://github.com/gap-packages/openmath/issues/31>
- **Affected**: GAP `openmath` package v11.5.5 (2026-08-11), GAP 4.15.1,
  conda-forge build. The binary encoding code is unchanged since 2016, so every
  release since is affected.
- **Workaround**: `src/binary/writer.jl` emits base 16, not base 256.

**Severity: high.** A silent wrong answer, not a failure — and a smaller number
than the one sent, so it will not even look anomalous.

§3.2.2 gives three bases for the digits of a big integer, chosen by the mask bits
of the sign byte: `0x00` base 10, `0x40` base 16, `0x80` "base 256", whose digits
are "bytes … in their natural order". The reader renders each digit byte as
hexadecimal **without padding it to two characters** and parses the
concatenation, so every byte below `0x10` contributes one hex digit instead of
two and everything to its right shifts by a nibble.

### Reproducer

Digits after the `02 <n> 0xab` prefix, read back through `OMGetObject`:

| Digit bytes | Correct | GAP returns | Unpadded concatenation |
|:--|--:|--:|:--|
| `ff ff ff f1` | 4294967281 | 4294967281 | `"ff"+"ff"+"ff"+"f1"` |
| `ff 01 ff` | 16712191 | **1044991** | `"ff"+"1"+"ff"` |
| `ff 00 ff` | 16711935 | **1044735** | `"ff"+""+"ff"` |
| `01 00` | 256 | **16** | `"1"+"0"` |
| `10 00` | 4096 | **256** | `"10"+"0"` |
| `0f ff` | 4095 | 4095 | `"f"+"ff"` — a dropped zero that was leading anyway |

```gap
gap> s := InputTextFile("ff01ff.bin");; OMGetObject(s);
1044991
```

### Where it comes from

Base 256 is an **OpenMath 2 addition**. OpenMath 1.1 §4.2.2 has only two bases —
"the base mask bits that can be 0 for base 10 or 0x40 for base 16" — and says the
digits are "the strings of digits (**as characters**) in their natural order".
OpenMath 2 §3.2.2 adds the third and says "as characters for bases 10 and 16 …
and **as bytes** for base 256".

The observable behaviour is what you get when the new byte case is funnelled into
the old character path: each byte rendered as hexadecimal and handed to the
base-16 parser, without being padded to two digits. So this is not a wrong radix.
It is the seam between an OpenMath 1 code path and an OpenMath 2 feature fitted
to it — which also predicts where else to look, and matches the fact that the
sharing mechanism of §3.2.4.2, the other OpenMath 2 addition to this section, is
not implemented at all.

*(Stated as an account of the behaviour, not of the code: the code has not been
read, and the observations are all from running it.)*

### Why it has survived since 2016

**The standard's own worked example is one of the cases that happens to work.**
§3.2.2 encodes `xfffffff1` in base 256 as `0x02 0x04 0xab 0xFF 0xFF 0xFF 0xF1` —
four bytes, none below `0x10`, so no zero is dropped and the answer is right. An
implementer checking against the standard sees a pass.

It is also invisible from GAP's own tests: GAP *writes* big integers in base 10,
so its reader's base-256 path is never exercised by its own round trips.

### A correction to an earlier draft of this entry

This was first written up as "base-256 digits are accumulated with radix 16",
from four samples — 2⁴⁰, 2⁵⁶, 2⁶⁴, 2¹⁰⁰ — which fitted that rule exactly. They
also all have the same shape: one non-zero byte followed by zeros. The standard's
own example falsifies the rule at once, and it had not been tried. The oracle
reported *that* GAP disagreed; the explanation of *why* was a hypothesis, and it
was wrong until it was tested against a case chosen to break it.

## GAP openmath 11.5.5 — the binary writer cannot emit a float

- **Found**: 2026-09-17, same run
- **Reported**: <https://github.com/gap-packages/openmath/issues/32>
- **Affected**: as above
- **Workaround**: none needed on our side. `just oracle-gap` reports these four
  values as blocked upstream rather than as disagreements, and tests the same
  floats in the other direction, which works.

`OMPutObject` on a float, to a binary writer, raises before emitting anything
beyond the object tag. The XML writer is unaffected.

### Reproducer

```gap
gap> s := OutputTextFile("f.bin", false);; SetPrintFormattingStatus(s, false);;
gap> OMPutObject(OpenMathBinaryWriter(s), 1.5);
Error, Comparison of float and 0 is not supported. Please refer to the manual
section on floats for details at .../lib/float.gi:1001 called from
f > 0
  at .../openmath/gap/omputbin.gi:367
```

The file is left holding two bytes, so a reader sees a truncated stream. Reading
is fine: GAP decodes `03 3d db 7c df d9 d7 bd bb` — the standard's own worked
example for 1×10⁻¹⁰ — to `1.e-10` correctly.

---

## GAP openmath 11.5.5 — the OpenMath 2 document tag `[24+64]` is rejected

- **Found**: 2026-09-17, same run
- **Affected**: as above
- **Reported**: not yet — and this one may be a deliberate limitation rather than
  a defect, which is a question for the maintainers rather than an assertion.
- **Workaround**: decision **D8**. We write `[24]` unless the object needs
  `[24+64]`, which §3.2.6 explicitly permits and which is what GAP itself emits.

`OMGetObject` fails with "OpenMath object not retrieved" on any document whose
first byte is `0x58`, which is `[24+64]` — the form §3.2.4.2 defines, carrying
the version bytes and the structure-sharing mechanism.

### Reproducer

```
58 02 00 01 10 19       → Error, OpenMath object not retrieved
18 01 10 19             → 16
```

Both encode the integer 16; the first uses the OpenMath 2 document tag and
declares version 2.0.

### Why it is recorded

It means **no shipping implementation exercises §3.2.4.2 at all** — GAP neither
writes it nor reads it. That is the context in which the contradictions of §3.2
recorded above have survived twenty years without being noticed: the part of the
section that disagrees with itself is the part nobody runs.

## Note on reporting

**Decision, 2026-09-17: the crate limitations are recorded here and not reported
upstream.** This is deliberate, not an oversight, and this file should not be read
as carrying five pending tasks.

The §3.2 entries above are a separate question and are **still open**. Two of the three GAP defects were
filed on 2026-09-17 as issues [#31](https://github.com/gap-packages/openmath/issues/31)
and [#32](https://github.com/gap-packages/openmath/issues/32), both with the
AI-assistance disclosure the project uses and both validated by local execution
before sending.

The third — `[24+64]` rejected — was **deliberately not filed**. It is a missing
feature rather than a defect, and it is a feature nothing in the field uses;
asking for it would have diluted two reports that have reproducers and probable
one-line fixes.

The §3.2 entries — defects in a normative document, reproducible from the
document alone with no toolchain — went to
[OpenMath/OMSTD#72](https://github.com/OpenMath/OMSTD/issues/72) on the same day,
with a patch offered for the four editorial items and the undecidable one put as
a question rather than an assertion.

So of the ten things recorded in this file, three are filed and seven are not,
and each of the seven has a reason written beside it. This file is not a list of
pending tasks.

The newest — GAP's XML and binary writers disagreeing about one string — is
recorded and deliberately not filed: it is a model mismatch rather than a bug
with a patch, its conformant remedy would change bytes GAP has emitted since
2016, and nothing here depends on the outcome.

The reasoning: four of the five are straightforward gaps in a young v0.1.7 crate
rather than logic errors, and one — `OMR` structure sharing — is already listed as
a TODO in the crate's own README. Filing them would mostly tell the author things
he already knows about his own roadmap.

The entity-reference case is the one with a real argument for reporting: it is
silent, it affects ordinary documents, and `&lt;` and `&amp;` are the only way to
put `<` or `&` in an `OMSTR`, so any string containing either is unreadable to
that implementation. If the decision is ever revisited, that is the one to send.

None of this affects us. The entries below exist so that `just oracle` can
classify a disagreement as a known upstream limitation rather than a failure, and
they do that job whether or not anyone upstream has been told.

---

## OpenMath Content Dictionaries — the official set is not self-consistent

- **Found**: 2026-09-19, roadmap Phase 5, writing the CD-driven harness item
- **Affected**: the official Content Dictionary set as served by
  <https://openmath.org/cd/>, fetched by `just corpus-fetch` on 2026-09-17;
  38 Official dictionaries plus the contributed and experimental directories
- **Reported**: not yet — recorded here first
- **Workaround**: `test/unit/cd.jl` pins each class below in an explicit
  exception list, so these do not fail the gate and a **new** one does

### Reproducer

Load every dictionary and every STS signature, then run
`validate_against_cds` over every `<CMP>`, `<FMP>` and `<Example>` the
dictionaries themselves contain — 1114 embedded objects:

```julia
reg = OpenMath.CDRegistry()
for dir in readdir(joinpath("refs", "cd", "cd"); join = true)
    isdir(dir) || continue
    for (k, v) in OpenMath.load_cd_directory(dir).dictionaries
        reg.dictionaries[k] = v
    end
end
OpenMath.load_sts_directory!(reg, joinpath("refs", "cd", "sts"))
```

### Expected / actual

96 issues in 1114 objects, in four classes. The first two are **defects**; the
last two are not, and are listed so the distinction is on the record.

**1. A symbol that does not exist is named.** The dictionary cited defines a
symbol of a similar name, or none:

| Cited | The dictionary actually defines | Cited by |
|:--|:--|:--|
| `relation1#le` | `leq` | `interval1`, 6 times |
| `calculus1#defintint` | `defint` | `interval1#oriented_interval` |
| `arith1#eq` | — (`relation1#eq`) | `linalgpoly1#minimum_poly` |
| `list3#append` | — (`list1#append`) | `list4#reverse` |
| `list3#list_selector` | — | `list4#entry` |
| `interval1#ordered_interval` | `oriented_interval` | `calculus1#defint` |
| `linalg3#rowcount`, `columncount`, `size` | — | 35 times, across `linalg*` |
| `linalg5#rank` | — | `linalg4mat#constant` |
| `meta#CDGroupName` | — | `scscp2#signature` |
| `linalgspec1#banded` | — (the dictionary defines three symbols, none of them `banded`) | `linalgspec1#tridiagonal`, its own CD |
| `norm1#…` | — (no `norm1.ocd` is served at all) | `dimensions1#velocity` |

**2. An example contradicts its own STS signature.** Every one of these
signatures is binary — `mapsto(Object, Object, Boolean)` or the like, with no
`nary` — and the dictionary's own example applies the symbol to three arguments,
or to one:

| Symbol | Signature | Applied to | Where |
|:--|--:|--:|:--|
| `relation1#eq` | 2 | 3, and 1 | `monoid1`, `field1`, `transc2#arctan` |
| `logic1#implies` | 2 | 3, and 1 | `monoid1`, `field1`, `ring1#ring` |
| `set1#in` | 2 | 3, and 4 | `group1#is_normal`, `polygb2#in` |
| `arith1#minus` | 2 | 1 | `interval1`, `fns4#maps_to` |
| `list1#map` | 2 | 3, and 1 | `fns2#apply_to_list`, `permutation1#sign` |
| `fns2#apply_to_list` | 2 | 1 | 8 times |
| `poly#degree` | 1 | 2 | `linalgpoly1#minimum_poly` |
| `polyslp#prog_body` | 1 | 3, and 5 | `polyslp` |
| `relation1#geq` | 2 | 1 | `linalgpoly1#minimum_poly` |

**3. `s_data1#moment` has `sts#nary` in the return position.** Not an example
defect but a signature one, and worth separating because the reading is subtle:

```xml
<OMA><OMS cd="sts" name="mapsto"/>
  <OMS cd="sts" name="NumericalValue"/>
  <OMS cd="sts" name="NumericalValue"/>
  <OMA><OMS cd="sts" name="nary"/><OMS cd="sts" name="NumericalValue"/></OMA>
</OMA>
```

`sts#mapsto` says "the first n-1 children denote the types of the arguments, the
last denotes the return type", so as written this is a two-argument function
returning *an arbitrary number of* numerical values. The example applies it to
15. Presumably `mapsto(NumericalValue, nary(NumericalValue), NumericalValue)`
was meant.

**4. `polynomial3#quotient` has a dangling reference.** Its FMP declares
`id="pr"` and `id="q"` and then cites `#pr` and **`#r`**. No element carries the
id `r`; `q` is almost certainly what was meant. §3.1.2 requires the target to
exist, so the FMP is not a valid OpenMath document — `validate` rejects it, and
that is the only object in all 1114 it rejects.

**5. Not defects, recorded so the exception list is not mistaken for one.**

- `error#unexpected_symbol` and `error#unsupported_CD` cite `arith1#plurse` and
  the dictionary `specfun1` **on purpose**: an example of an unexpected symbol
  has to contain one. Flagging them is the check working.
- `scscp_transient_1` is a transient dictionary, defined at run time by an SCSCP
  session rather than served statically, so it is absent by design.

### What it cost us

One defect of our own, found by the same run and fixed before this entry was
written: `sts_arity` recognised `sts#nassoc` as unbounded and not `sts#nary`,
though the `sts` dictionary defines both in the same words — "an arbitrary
number of copies of the argument". So every n-ary symbol in the official set had
the arity of its own wrapper, and `list1#list` accepted exactly one element.
That defect accounted for most of the first run's noise, and was indistinguishable
from an upstream fault until the signature was read.

---

## XML.jl 0.4.6 — an undeclared entity reference is accepted as literal text

- **Found**: 2026-09-17, deciding roadmap decision D1; re-verified 2026-09-20
- **Affected**: `XML.jl` v0.4.6 (latest release) **and** `main` at tree hash
  `4315db226f6ed00c614f20a14e64103655fbec35`; Julia 1.13.0
- **Reported**: <https://github.com/JuliaData/XML.jl/issues/152>, 2026-09-20.
  **Answered 2026-09-21, and the report was partly wrong.** `XML.jl` has three
  well-formedness levels and always did; this investigation never passed one, so
  it tested the default and reported it as the whole behaviour. On `main` at
  `1681e21`, `wellformed = :strict` rejects the reference with the §4.1 fatal
  error on both `Node` and `FlatNode`. #139 brings it to the next release. What
  v0.4.6 lacks is entity handling at *any* level, which is a narrower statement
  than the one filed.
  **Answered 2026-09-21, and the report was partly wrong.** `XML.jl` has three
  well-formedness levels and always did; this investigation never passed one, so
  it tested the default and reported it as the whole behaviour. On `main` at
  `1681e21`, `wellformed = :strict` rejects the reference with the §4.1 fatal
  error on both `Node` and `FlatNode`. #139 brings it to the next release. What
  v0.4.6 lacks is entity handling at *any* level, which is a narrower statement
  than the one filed
- **Workaround**: none possible downstream. This package owns its XML tokenizer
  (`src/xml/tokenizer.jl`) for this reason; see `docs/src/design/xml-backend.md`

### Reproducer

```julia
julia> using XML

julia> XML.parse(XML.Node, "<r>&xxe;</r>")     # no DTD anywhere in the document
```

### Expected / actual

The document has no DTD, so XML 1.0 (Fifth Edition) §4.1, WFC **Entity
Declared**, requires the name in an entity reference to match a declaration.
§5.1 makes a violation of a well-formedness constraint a **fatal error**.

`XML.jl` accepts the document and the text node holds the seven literal
characters `&xxe;`.

The practical consequence is worse than the conformance one. Writing that node
back produces `&amp;xxe;`: the document has silently changed meaning, and
nothing reported it. A reader and a writer that share the behaviour agree with
each other on the wrong value, so a round-trip test cannot see it either.

### Not a duplicate

- **#130** (closed) added §4.4 inclusion for entities declared in the internal
  subset. Verified fixed on `main`: `<!DOCTYPE r [<!ENTITY e "X">]><r>&e;</r>`
  now yields `X`, where v0.4.6 yields the literal `&e;`. Different rule.
- **#137** (open) concerns entities declared in an *external* subset. Not
  including those is permitted — §4.4.3 lets a non-validating processor decline
  to read them — so that is a policy question. This is not: an undeclared entity
  has no declaration anywhere to honour.

### A smaller, related point

§4.4.3 says a processor that recognises but does not read an external entity
"must inform the application" that it did so. On `main`,
`<!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><r>&x;</r>` yields the
literal `&x;` with no signal. Declining to fetch is the right call — XXE follows
directly from any retrieval — but the silence is the same failure shape as
above. This probably belongs to #137 rather than to a report of its own.
