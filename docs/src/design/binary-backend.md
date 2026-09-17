# Decision D7 — reading §3.2 where the standard is unclear

**Status**: **undetermined by the standard**, 2026-09-17, and untestable against
any implementation — GAP, the only other one, rejects the `[24+64]` form
outright, so nothing in the field exercises the disputed layout in either
direction. **Outcome, as a tie-break rather than a deduction**: the sharing flag
is a boolean and carries no identifier, and shared objects are numbered as they
*complete*.

The binary encoding is the one encoding here with no oracle *in place*. XML had
expat and the reference crate to disagree with us, JSON had the standard's worked
documents, Strict Content MathML had the MathML 4 element table. The reference
crate leaves §3.2 unimplemented — its README lists "binary format" under TODO —
and round-trip, idempotence and cross-encoding agreement are all satisfied
*trivially* by a reader and a writer that share the same misunderstanding.

So the standard's own worked byte sequences were transcribed into
`test/corpus/binary-vectors.toml` before a line of codec was written. Doing that
first is what surfaced the problem below: two of the standard's three worked
examples do not agree with its grammar, and one does not agree with itself.

!!! note "There is a second implementation, and we have not used it yet"
    An earlier draft of this page said no second implementation existed. That was
    wrong, and the correction matters: it turns D7 from a judgement call into a
    question with an experiment attached.

    GAP's [`openmath` package](https://github.com/gap-packages/openmath) writes
    and reads the binary encoding — `OpenMathBinaryWriter`, `OMGetObject` with
    format autodetection, `OMTestBinary` for round-trips, and
    `SwitchSCSCPmodeToBinary` in the companion SCSCP package. It is maintained,
    and it is what SCSCP deployments actually talk to.

    Older ones exist for the OpenMath **1** encoding only: the INRIA C library of
    Dalmas, Gaëtano and Watt (ISSAC 1997) had `OM_ENCOD_BIN`, and the ESPRIT
    final report records that the Java library supported "both the XML and binary
    encodings". OpenMath 1 predates the `[24+64]` mechanism of §3.2.4.2 entirely,
    so those cannot settle D7 — though they may explain how Figure 3.5 came to be
    written: its body is coherent OpenMath 1, and OpenMath 2 deliberately "leaves
    the tokens with sharing flag 0 unchanged to ensure OpenMath 1 compatibility",
    so the figure reads like an OpenMath 1 example whose header was updated and
    whose body was not.

    GAP is now installed and wired up as `just oracle-gap`; what it settled, and
    what it turned out not to be able to settle, is below.

## What GAP's own bytes say

GAP's package ships `tst/test3.bin`, 243 bytes it wrote itself: ten OpenMath
documents concatenated in one file. `just gap-vectors` downloads it into
gitignored `refs/` — data, not source, so no GPL code is read or linked — and the
conformance suite picks it up when it is there.

**`read_binary` decoded all ten, first attempt, no change to the codec**, and
every one round-trips through our writer and agrees with the XML and JSON
readers. That is the first evidence that our §3.2 is anyone else's, and it is
also the streaming requirement proved on a real file rather than a fixture: the
reader has to stop at each end tag to get ten objects out of one stream.

```
 1  OMI(912873912381273891)
 2  OMS(nums1#i)
 3  OMS(logic1#true)
 …
 8  OMA(OMS(permut1#permutation), OMI(2), OMI(3), OMI(1))
10  OMATTR(OMA(OMS(permut1#permutation), OMI(2), OMI(3), OMI(1)), OMS(logic1#true)=OMI(1))
```

**But every document starts `[24]`, never `[24+64]`.** GAP writes the OpenMath 1
document tag throughout, which the standard explicitly keeps valid: "the binary
encoding tags without the shared flag can still be used as more compact
representations of the objects (which are not shared, and do not have an
identifier)".

Two consequences, and the second is uncomfortable:

1. **GAP's output cannot settle D7.** Under `[24]` the sharing flag has the
   OpenMath 1 meaning, so GAP never emits the `[24+64]` tags whose layout is in
   dispute. The ambiguity is untested by the only shipping implementation, which
   is itself informative: nothing on the wire today uses §3.2.4.2.
2. **Our output has to meet GAP where it is.** We used to write `[24+64]`
   always. Whether GAP's reader accepts that cannot be read off its bytes; it
   needs GAP running, which is `just oracle-gap`. But the question is worth
   sidestepping regardless, which is decision **D8** below.

## D8 — the document tag is `[24]` unless `[24+64]` buys something

§3.2.6 keeps `[24]` valid in OpenMath 2: "the binary encoding tags without the
shared flag can still be used as more compact representations of the objects
(which are not shared, and do not have an identifier)". It is also what the only
other shipping implementation emits, for everything.

`[24+64]` buys exactly two things — the sharing mechanism of §3.2.4.2, and the two
version bytes — so it is written for exactly those two, and `[24]` otherwise:

```julia
OpenMath.binary(OMObject(OMInteger(16)))                  # 18 01 10 19
OpenMath.binary(OMObject(OMInteger(16); version = "1.1")) # 58 01 01 01 10 19
```

An `OMR` in the object forces `[24+64]`; an `id` that nothing refers to does not,
since it buys nothing either way. The cost is two bytes of version information on
documents that are not version 2.0, which is the case this chooses to spend
`[24+64]` on. The gain is that the common case is the form every reader of this
encoding has accepted since 1997 — and four bytes shorter.

## Who else implements §3.2

The survey that should have preceded this phase, done afterwards (harness step
**H2.5**). Two living codebases, and one of them is the ancestor of four more.

| Implementation | Language | Binary? | Form | Status |
|:--|:--|:--|:--|:--|
| GAP [`openmath`](https://github.com/gap-packages/openmath) | GAP | **yes** | `[24]`, base 10 | v11.5.5, 2026-08; codec frozen since 2016 |
| **`libom`**, the INRIA/ESPRIT C library | C | **yes** (`OM_ENCOD_BIN`) | OpenMath 1 | 1997; source not found on GitHub |
| ├ [REDUCE](https://github.com/reduce-algebra/reduce-algebra) | C++ | via `libom` | — | `csl/cslbase/openmath.cpp`, behind `#ifdef OPENMATH` |
| ├ [FriCAS](https://github.com/fricas/fricas) | SPAD | via `libom` | — | `src/algebra/omdev.spad`, `OMencodingBinary() == 1` |
| ├ Axiom, OpenAxiom | SPAD | via `libom` | — | same lineage |
| └ INRIA Java library | Java | reported | — | ESPRIT final report: "both the XML and binary encodings"; source not found |
| [`py-openmath`](https://github.com/OpenMath/py-openmath) | Python | no | — | "XML de-serialization" only |
| [`py-scscp`](https://github.com/OpenMath/py-scscp) | Python | no | — | built on `py-openmath` |
| the Rust reference crate | Rust | no | — | README lists "binary format" under TODO |

Three things follow.

**Everything in the field is the OpenMath 1 form.** GAP writes `[24]`; `libom`
predates OpenMath 2 entirely. That is independent support for **D8**, arrived at
from a different direction than the GAP experiment — and it closes **D7** for
good: no implementation anywhere exercises `[24+64]`, so the layout the standard
contradicts itself about has never been run by anyone.

**The binary encoding *was* `libom`.** §3.2 documents a codec that existed first,
in C, at INRIA, and the standard's prose was written around it. That is the most
likely explanation of Figure 3.5, whose body is coherent OpenMath 1 under an
OpenMath 2 header: an example transcribed from a working `libom` stream, with the
header modernised and the body left alone.

**`libom` is not reachable.** It is the codec four computer algebra systems bind
to, and it is not on GitHub; the openmath.org links to it are from the ESPRIT
era. So a second, independent oracle exists in principle and not in practice —
which is worth stating plainly rather than leaving as an unexamined "GAP is the
only one".

## Does GAP derive from this standard?

Partly, and the seam is where its defect lives. The check is a diff of OpenMath
1.1 §4.2 against OpenMath 2 §3.2, against what GAP observably does.

| Feature | OM 1.1 §4.2 | OM 2 §3.2 | GAP's behaviour |
|:--|:--|:--|:--|
| Document tag | `[24] object [25]` | adds `[24+64] [m] [n]` | writes `[24]`, **rejects `[24+64]`** |
| Identifier width | first **6** bits | first **5** bits, bit 6 = streaming | — |
| Sharing | `+64` = back-reference, payload one index byte | `+64` = "referenced later", refs `[30]`/`[31]` | OM 1 form only |
| Integer bases | 10 and 16, digits **"as characters"** | adds **base 256**, digits "as bytes" | implements it, **incorrectly** |
| `cdbase` scope, token 9 | absent | added | reads it (changelog, 2016) |
| Foreign objects, token 12 | absent | added | — |
| Streamed packets, bit 6 | absent | added | — |

So GAP is **not** a pure OpenMath 1 implementation. It is an OpenMath 1 core with
some OpenMath 2 features added — base-256 integers and `cdbase` scopes — and the
one OpenMath 2 feature it does not have is the sharing mechanism of §3.2.4.2.

That explains the shape of its integer defect. OM 1 says the digits of a big
integer are "the strings of digits (**as characters**) in their natural order";
OM 2 adds "and **as bytes** for base 256". GAP's observable behaviour is what you
get when the new byte case is funnelled into the old character path: each byte is
rendered as hexadecimal and handed to the base-16 parser, without being padded to
two digits. The defect is not a wrong radix. It is the seam between an OpenMath 1
code path and an OpenMath 2 feature fitted to it.

### And the same seam explains the standard's own contradictions

OpenMath 2's Figure 3.3 reads like an edit of OpenMath 1's Figure 4.3, made where
the meaning of `+64` changed. In OM 1 a `+64` row was a *back-reference*, and its
whole payload was one index byte:

```
OM 1.1, Figure 4.3
  variable → [5] [n] varname:n | [5+128] {n} varname:n | [5+64] [n]
  symbol   → [8] [n] [m] cdname:n symbname:m | … | [8+64] [n]
  string   → [6] [n] chars:n | [6+128] {n} chars:n
           | [7] [n] chars:2n | [7+128] {n} chars:2n | [7+64] [n]
```

In OM 2 those rows had to become "the object itself, plus whatever marks it as
shared". Re-read the two defective productions with that in mind:

- `[6+64] [n] bytes:n` — the OM 1 row shape with the ordinary payload restored
  and no identifier. Note also that OM 1's grammar has **no `[6+64]` row at all**,
  although §3.2.4.1 says 8-bit and 16-bit strings share separately, so the row was
  missing before it was wrong.
- `[7+64] [n] [m] bytes:n id:m` — an identifier added, but `bytes:n` where token 7
  needs `bytes:2n`. OM 1's `[7+64] [n]` had no payload at all, so there was nothing
  to copy from except the token-6 row.

This is an account, not a finding: nobody has said this is what happened. But it
is consistent with every defect in §3.2 being in a `+64` row or in a figure that
predates the OM 2 sharing mechanism, and with none being anywhere else.

## The conflict

Figure 3.3, the grammar, gives every shared production an explicit identifier:

```
application → [16] object objects [17]
            | [16+64] [m] id:m object objects [17]
```

§3.2.2 says the same for symbols — "followed by the length in bytes … of the
Content Dictionary name, the symbol name, and the id (if the shared bit was
set)".

Figure 3.6 says otherwise. Its byte 8 is `0x50` = `[16+64]`, a shared
application, and its byte 9 is `0x05`, a variable tag. No length, no identifier.
§3.2.4.2 agrees with the figure — the flag "indicates whether an object will be
referenced later … corresponds to the information, **whether** an `id` attribute
is set" — and so does §3.2.5, which describes the reader's array purely
positionally. So does the note that "in the conversion from the XML to the binary
encoding the identifiers on the objects are not preserved", which is false if
the grammar is right.

The two readings produce incompatible byte streams. A decoder written to the
grammar cannot read Figure 3.6, and a decoder written to Figure 3.6 cannot read
a stream that follows the grammar.

## Which reading is right — undetermined, and we chose

An earlier draft of this page said the grammar "contradicts itself, so it cannot
be the authority". That was overstated, and an audit of every shared production
in Figure 3.3 is what showed it:

**33 alternatives carry the `+64` flag. 31 carry an `id:` field. One does not.**

```
[6+64]      [n]     bytes:n            ← the only shareable row with no id
[6+64+128]  {n} {m} bytes:n  id:m
```

`start → [24+64] [m] [n] object [25]` is the thirty-third and correctly has no
id, since §3.2.4.2 says the flag means something else there. So the grammar is
near-uniform, and `[6+64]` reads as a dropped `[m] id:m` — a typo, not a
statement. It is still a defect, and it is still worth reporting, but it is not
evidence about the design.

That leaves a genuine conflict with nothing to break the tie:

| For an identifier | Against |
|:--|:--|
| Figure 3.3, 31 of 32 shareable rows | Figure 3.6, which shows `[16+64]` followed directly by the applicant |
| §3.2.2, describing the symbol id explicitly and at length | §3.2.4.2: the flag "corresponds to the information, **whether** an `id` attribute is set" |
| | §3.2.4.2: "the identifiers on the objects are not preserved" |
| | §3.2.5, which describes the reader's array purely positionally |

Figure 3.6 is the only *executable* statement in that column — but it is already
known to be wrong in another byte (its byte 27), so "the figure also omits the
id bytes" is a live possibility rather than an absurdity. And §3.2.2's prose is
the only thing in the left column that is not the grammar.

**The document does not determine the answer.** This package follows Figure 3.6,
for one reason that is not a deduction: it is the only reading under which a byte
sequence the standard prints can be decoded at all. That is a tie-break, not a
proof, and the cost of being wrong is currently zero — no implementation
exercises `[24+64]` in either direction, so there is nothing to interoperate with
and nothing to break. The question is the substance of the upstream report.

## Completion order, not start order

§3.2.4.2 says a reference names "the n+1th shared sub-object … counted in the
order they are generated in the encoding", which can be read two ways. Figure 3.6
settles it: its byte 24 references shared object 0 from *inside* the application
that opened first, so under start order an object would dominate itself, which
§3.1.3.1 forbids. Under completion order the figure decodes, and the decoding is
the object of Figure 3.1. §3.2.5 describes the same order — "it is read **and**
a pointer to the generated data structure is stored at the next position".

## What this costs

`id` strings do not survive a binary round trip; the reader mints `t0`, `t1`, …
for the objects that were flagged. The standard says as much, and the
consequence is visible and tested rather than silent:

```julia
back = read_binary(binary(obj))
expand_references(back) == expand_references(obj)   # true
```

A reference that points *forward* — legal in XML, where `id` may follow its
`OMR` — cannot be expressed at all, since §3.2.5 forbids forward references.
The writer raises `OpenMathConversionError` naming `expand_references` rather
than quietly inlining the target, which would change the size of the output by
orders of magnitude without saying so.

## What the harness actually caught

Worth recording, because it is the measurement this project keeps:

| Layer | Defects found in the binary codec |
|---|---|
| The standard's byte vectors | the two figure defects above, before any code |
| Unit tests | 6, all in the first run |
| **Property layer (P4)** | **3**, none of which any example test reached |
| Fuzzing | 0 so far |
| **Differential oracle (GAP)** | **1 interoperability defect of ours, 3 of theirs** |

The oracle's one finding against us is the integer base — see D9 below. Its three
findings against GAP are in `upstream-bugs.md`, and one of them, base-256 integers
mis-decoded whenever a digit byte falls below 0x10, is a silent wrong answer.

The three the property layer found were all `cdbase`: an outer scope silently
overwriting an inner one, a document-level base with nowhere to go on read, and
a vacuous scope that made writing non-idempotent. Every one of them needs a
`cdbase` on the document *and* on the root object to show up, which is not a
combination anyone writes by hand.

## D9 — big integers are written in base 16, not base 256

§3.2.2 allows three bases for the digits of a big integer. Base 256 is the
densest and was the original choice here. The oracle's first run said no:

```
2^100, base 256   →  GAP reads 4503599627370496  =  2^52
2^100, base 16    →  GAP reads 1267650600228229401496703205376
2^100, base 10    →  GAP reads 1267650600228229401496703205376
```

GAP renders each base-256 digit byte as hexadecimal without padding it to two
characters, so any byte below `0x10` contributes one hex digit instead of two and
everything to its right shifts by a nibble. Silent, and smaller than the number
sent, so it does not even look anomalous.

**The standard's own worked example is one of the cases that happens to work**:
`0x02 0x04 0xab 0xFF 0xFF 0xFF 0xF1` has no digit byte below `0x10`, so nothing
is dropped. That is how the defect reached 2026 — and it is also why the first
diagnosis written here was wrong, which is recorded in `upstream-bugs.md` rather
than quietly corrected.

Base 16 is what the standard's own example uses and what GAP reads correctly. The
cost is about 2× the digit bytes against base 256; the alternative was handing
the only other implementation a smaller number than the one we meant.

## What the oracle reports now

```
we write → GAP reads   34/34 agree
GAP writes → we read   26/30 agree, 4 blocked by an upstream defect
```

The four are floats, which GAP's binary writer cannot emit at all. Those same
four floats are tested in the other direction, where they agree — so every value
in the set is checked in the direction that decides whether this package is
usable on an SCSCP wire.

## Revisit if

- **`just oracle-gap` disagrees with us.** If GAP writes the grammar form,
  interoperability is worth more than being right, and `read_binary` should learn
  both behind an explicit switch rather than a guess. This is the one open
  question on this page, and it is an experiment, not an opinion.
- **The OpenMath Society rules on it.** The conflict is recorded in
  `upstream-bugs.md`; an erratum settles it either way.
