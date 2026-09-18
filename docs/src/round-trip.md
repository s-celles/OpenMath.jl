# What survives a round trip

`REQ-OM-003` says the system shall preserve, across a parse-then-serialise cycle,
every field of every node that the source encoding carried. That is true, and the
qualification — *that the source encoding carried* — is where the whole of this
page lives.

The three text encodings lose nothing. **The binary encoding loses four things**,
all of them consequences of what §3.2 does and does not have a place for, and all
of them tested rather than asserted.

The point of collecting them here is that silent loss is the one failure this
package exists to prevent. A loss that is written down is a documented property; a
loss that is scattered across six design notes is a surprise waiting for someone.

## Measured

Each row is a round trip through that encoding, compared with
[`isequal_with_ids`](@ref) — structural equality *including* `id` attributes,
which ordinary `==` ignores.

| | XML | JSON | MathML | binary |
|:--|:--|:--|:--|:--|
| `OMFOREIGN` with `encoding = ""` | identical | identical | identical | **`encoding` becomes `nothing`** |
| a node whose `id` nothing references | identical | identical | identical | **`id` dropped** |
| `OMR` structure sharing | identical | identical | identical | **`id`s renamed `t0`, `t1`, …** |
| document `cdbase`, root carrying its own | identical | identical | identical | identical |
| a `cdbase` scope around a leaf | identical | identical | identical | identical |

## The four, and why

**An `OMFOREIGN` whose `encoding` is the empty string comes back as `nothing`.**
§3.2.2 encodes the encoding attribute as a length and that many bytes, so zero
length is the only way to say "absent" *and* the only way to say "empty". The two
are the same eleven bytes on the wire. Nothing can distinguish them, here or
anywhere else.

**An `id` that nothing refers to is dropped.** §3.2.4.2 has no field for an
identifier — the sharing flag says *whether* an object is referenced later and
nothing more — so an identifier only survives as the *position* of a shared
object. An unreferenced one has no position to be.

**Shared objects come back with different names.** For the same reason: a
reference is an ordinal, so the reader mints `t0`, `t1`, … in completion order.
The *structure* is exact — `expand_references` gives the same object either way —
and only the names change. The standard says so itself: "in the conversion from
the XML to the binary encoding the identifiers on the objects are not preserved".

**A forward reference cannot be written at all.** An `OMR` that appears before
the `id` it names is legal XML and inexpressible in binary, because §3.2.5 says
"forward references are not allowed". [`OpenMath.binary`](@ref) raises
`OpenMathConversionError` naming [`expand_references`](@ref) rather than inlining
the target, which would change the size of the output by orders of magnitude
without saying so.

## Spelling, which is not the same thing

These are not losses. The standard offers several ways to write one value and the
writer picks one, so a document can come back spelled differently and mean
exactly the same:

```jldoctest
julia> using OpenMath

julia> OpenMath.xml(OpenMath.parse("""
           <OMOBJ xmlns="http://www.openmath.org/OpenMath"><OMI>xFF</OMI></OMOBJ>"""))
"<OMOBJ xmlns=\"http://www.openmath.org/OpenMath\" version=\"2.0\"><OMI>255</OMI></OMOBJ>"
```

The same happens to `OMF hex=` when the decimal form round-trips exactly, to an
OpenMath 1 binary document, which is read and re-written as `[24]` without its
per-kind sharing tables, and to whitespace between XML elements. In every case
the *object* is identical; `==` says so and only the bytes differ.

## The passes discard on purpose

[`canonicalize`](@ref) is not a round trip and is not meant to be one. It expands
references, resolves `cdbase`, collapses nested attributions and strips `id`s,
because its job is to make two objects comparable regardless of how they were
written. Use [`isequal_with_ids`](@ref) when byte fidelity is what you are
testing, which is what the table above does.

## Symbolics

The [phrasebook](design/phrasebook.md) is a different kind of round trip and has
its own rule: it is **idempotent, not the identity**. Symbolics keeps several
representations of one mathematical object and `isequal` is structural, so `x^4`
may arrive as `Mul(1, Pow(x, 4))` and `2//1` normalises to `2`. Neither
distinction survives OpenMath, and neither should — OpenMath encodes the object,
not the host's spelling of it.

## Interoperating with GAP

GAP's `openmath` package is the only other implementation of the binary encoding,
and `just oracle-gap` compares against it. Two things do not survive an exchange,
and neither is a loss on our side.

**A non-ASCII string changes meaning in both directions.** GAP holds text as bytes
and writes UTF-8 under the ISO-8859-1 token, where §3.2.2 asks for one byte per
character. So `café` arrives here as `cafÃ©`, and our conformant `0xE9` arrives
there as a byte GAP's UTF-8 world calls invalid. The bytes survive intact; their
*meaning* does not. GAP's own XML and binary writers disagree about the same
string for the same reason, which is the cleanest way to see it —
`upstream-bugs.md` has the demonstration.

**A float cannot be sent from GAP at all.** Its binary writer raises before
emitting one ([gap-packages/openmath#32](https://github.com/gap-packages/openmath/issues/32)).
Reading a float from us works.

Everything else agrees: 36 of 36 values in the direction that decides whether
this package is usable on an SCSCP wire.
