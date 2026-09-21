# Decision D1 — the XML backend

**Status**: **re-opened 2026-09-21.** Settled 2026-09-17 on an argument that is
no longer true. **Outcome for now**: the purpose-built pull tokenizer in
`src/xml/tokenizer.jl` stays, on cost rather than on capability — see
[What changed](#What-changed), which is the part of this page to read first.

## The candidates

| Option | Mandatory dependency |
|---|---|
| `EzXML.jl` | `XML2_jll` — a **compiled binary artifact** |
| `XML.jl` | pure Julia |
| Purpose-built tokenizer | none |

**REQ-PRJ-002** — no mandatory dependency requiring a compiled binary artifact —
removes `EzXML.jl` from the core outright. It says nothing about `XML.jl`, which
is pure Julia, and an earlier draft of this page wrongly implied otherwise. The
case against `XML.jl` has to be made on its own, which is what follows.

## Measured against `XML.jl` v0.4.6

### Entity handling — the deciding difference

`XML.jl` expands the five predefined entities and numeric character references,
exactly as we do. The difference is what happens to an entity nobody declared:

| Input | `XML.jl` | `OpenMath.jl` |
|---|---|---|
| `&lt;` `&gt;` `&amp;` `&quot;` `&apos;` | expands | expands |
| `&#65;` `&#x41;` | expands | expands |
| CDATA | handled | handled |
| **`&xxe;`** | **passes it through as the literal text `"&xxe;"`** | rejects, naming the entity |
| `<!DOCTYPE …>` | accepted | rejected |
| `<!ENTITY e "…">` then `&e;` | accepted, `&e;` stays literal | rejected |
| billion laughs | accepted; safe, because nothing is expanded | rejected |

`XML.jl` is not *unsafe* here — it never expands a declared entity, so the
amplification attack has nothing to amplify. It is **silently lenient**, and for
this format that is worse than either expanding or refusing:

```
<OMOBJ xmlns="…"><OMSTR>&xxe;</OMSTR></OMOBJ>

OpenMath.jl  → OpenMathParseError: undeclared entity reference &xxe;
XML.jl       → accepted; the OMSTR would hold the literal "&xxe;",
               which written back out becomes "&amp;xxe;"
```

The document has changed meaning and nothing reported it. A round trip that
silently alters content is the one failure this package is built to prevent
(REQ-OM-003), and it would be invisible to our own conformance suite, because our
reader and writer would agree with each other on the wrong value.

Detecting this on top of `XML.jl` is not possible after the fact: once the text is
decoded, an expanded `&lt;` and a literal `<` are the same character, so there is
nothing left to inspect. The check has to happen during tokenisation, which means
owning the tokeniser.

### Verbatim capture — a point in `XML.jl`'s favour

`OMFOREIGN` content must be preserved as source, not as parsed nodes (see
`OMForeign`). I assumed a general parser could not do this. **That was wrong**:
`XML.jl` exposes `sourcetext` and `sourcespan` on a `LazyNode`, which return the
original bytes. The capability is there, and this argument should not be used
against it.

What remains is a smaller, honest point: the traversal API for reaching a specific
`LazyNode` took several attempts to get right, whereas `read_raw_until_end!` is one
call. That is ergonomics, not capability.

### Performance — against us

200 KiB document, 2000 subtrees, best of 20 runs:

| | Time | Allocation |
|---|---|---|
| `XML.jl` → generic `Node` tree | **2.45 ms** | 2.6 MiB |
| `OpenMath.jl` → validated `OMObject` | 13.9 ms | 8.3 MiB |

We are about **5.7× slower** and allocate 3× more. The comparison flatters us
slightly — we also validate names, resolve `cdbase` scoping, parse bignums and
decode base64, none of which `XML.jl` does — so the honest reading is that 2.45 ms
is a *floor* on what a rewrite could reach, not a figure it would hit. But the
direction is not in doubt: owning the tokeniser costs throughput, and no earlier
version of this page said so.

## What changed

The decision rested on one argument: **an undeclared entity reference must be an
error, and that can only be decided while tokenising.** That argument is false.

`XML.jl` has three well-formedness levels, and always did. We never passed one.
Every measurement on this page was taken at the default, `:structural`, and
reported as though it were the only behaviour — including in the issue filed
upstream, which said the behaviour was "unchanged on `main`" when it is unchanged
only at the default. [`mathieu17g` corrected
it](https://github.com/JuliaData/XML.jl/issues/152#issuecomment-5764965951).

On `main` at [`1681e21`](https://github.com/JuliaData/XML.jl/commit/1681e214b23c1783cd27ba315e609eee23a6685d),
verified here:

```julia
julia> XML.parse(XML.Node, "<r>&xxe;</r>"; wellformed = :strict)
ERROR: not well-formed: reference to undeclared entity "&xxe;" (XML 1.0 §4.1)
```

Both halves of the case are answered, and by the same object:

| What we needed | Where it is |
|:--|:--|
| an undeclared entity is a fatal error | `wellformed = :strict`, on `Node` and `FlatNode` |
| `OMFOREIGN` content kept verbatim | `sourcetext` on a `FlatNode`, which returns the exact bytes |

`FlatNode` parsed at `:strict` gives both at once. The second was already
conceded on this page as "mine to lose"; the first was the whole decision.

**The revisit condition below has fired.** It says: *"`XML.jl` grows a strict
mode that rejects undeclared entities and DTDs — then the deciding argument
disappears and the balance tips."* It did. Keeping the tokenizer because it is
already written would be exactly the bias that condition was set down to prevent,
so this page no longer claims the decision is forced.

## What still argues for our own tokenizer

Two things, and they are weaker than what they replace.

**Limits are enforced during the parse.** `max_depth`, `max_nodes` and
`max_bytes` stop hostile input before the work is done (REQ-SEC-002);
`Node`/`FlatNode` materialise the tree and we would check afterwards, by which
time the attacker has the allocation. Measured: 100 000 nesting levels parse in
0.02 s with no stack overflow, so this is about bounding *work*, not about
robustness — and capping input bytes before the call would bound the tree
anyway. It is a real difference and a smaller one than it sounds.

**Three readers share the tokenizer.** XML, Strict Content MathML and the CD
parser are all pull readers built on the same `_Frame` stack. Switching is not
replacing one file; it is restructuring three readers around a materialised
tree. That is cost, not merit, and it should be named as cost.

Against both: `XML.jl` builds a generic tree **5.7× faster** than we build a
validated one, allocates 3× less, and is a tokenizer we would not maintain.

## What would settle it

Not argument — measurement, which is what the harness is for. When #139 ships,
put a prototype backed by `FlatNode` + `wellformed = :strict` behind the same
conformance driver: 84 corpus items, 7501 assertions, the property layer and the
fuzz campaign. What breaks and what it costs are then facts rather than
positions, and this page can be rewritten from them.

Until then the tokenizer stays because replacing it is a large change with no
defect driving it — which is a reason to wait, not a reason to have been right.

## Revisit if

- **Throughput becomes a complaint.** 13.9 ms for 200 KiB is fine for documents
  and poor for a firehose. The fix is to optimise our tokeniser, not to adopt a
  parser whose leniency we would then have to undo.
- ~~**`XML.jl` grows a strict mode** that rejects undeclared entities and DTDs.~~
  **This has happened** — see [What changed](#What-changed). Reported upstream as
  [JuliaData/XML.jl#152](https://github.com/JuliaData/XML.jl/issues/152), where
  it is framed as a well-formedness question — XML 1.0 §4.1 WFC *Entity
  Declared* makes an undeclared reference a fatal error — rather than as a
  request shaped around this package's needs. No remedy was proposed: #137 shows
  entity policy is being decided deliberately there, and whether this belongs
  behind a flag or in the default path is the maintainers' call.

  Re-verified 2026-09-20 against `XML.jl` v0.4.6 and `XML.jl` `main`
  (`4315db22`). Two of the three
  entity behaviours this note once cited have moved: **#130 fixed internal-subset
  inclusion**, so `<!ENTITY e "X">` then `&e;` now yields `X` on `main`, and the
  external-subset case is #137's open policy question. Only the undeclared case
  is unchanged — which is the one the decision rests on, so the decision is
  narrower than when it was made but still stands.
- **The tokeniser needs namespace prefixes beyond the OpenMath URI, or
  `OMFOREIGN` content ever needs parsing rather than capturing.** Either would
  mean we are reimplementing a general parser.

## The `EzXML` extension, dropped

An earlier version of this page promised `EzXML.jl` interop as a package
extension, so that a caller already holding an `EzXML.Document` would pay no
conversion cost. That is dropped, and the reason is the same argument the rest of
this page makes.

An `EzXML.Document` has already been parsed. Whatever its parser did with
entities, DTDs and undeclared references has already happened, and the result is
a tree of text nodes in which an expanded `&lt;` and a literal `<` are the same
character. So a reader that starts from one **cannot make the guarantee the
deciding argument above rests on** — that an undeclared entity reference is an
error — and could not tell a caller so.

The extension would therefore have been a second entry point with quietly weaker
guarantees than `read_xml`, reachable by loading an unrelated package. The
convenience it buys is one `string(doc)` call. That is not a trade worth making,
and REQ-XML-011 is withdrawn rather than deferred.
