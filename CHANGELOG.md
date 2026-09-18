# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Non-strict Content MathML**, via `OpenMath.parse(src; format = :mathml,
  strict = false)`. The transformation is **MathML 4 Appendix F**, which defines
  it normatively, so nothing here is guessed: the token, operator, constant and
  container rules (F.4.3, F.4.4, F.7.1, F.8, F.8.1, F.9.1) are implemented, and
  the qualifier machinery (F.2, F.3, F.5, F.6) is refused with the section that
  governs it rather than approximated. `docs/src/design/mathml-appendix-f.md`
  tabulates both halves. Default behaviour is unchanged — `read_mathml` still
  reads the strict subset only.
- `OpenMath.appendix_f_operators()` exposes the §F.8 element-to-symbol table.
- Appendix F transforms the **container elements** `<set>`, `<list>`, `<vector>`,
  `<matrix>` and `<matrixrow>` (F.4). They were in the §F.8 table and reachable
  only in applicant position, so `<set>1 2</set>` fell through to "unhandled
  element". `type="multiset"` selects `multiset1#multiset`, and an attribute with
  no OpenMath counterpart — `<list order="lexicographic">` — is refused rather
  than dropped.
- `multiset1#multiset` in the base vocabulary, as a `Vector`: a multiset keeps
  its repeats, which is the whole difference from `set1#set`.
- Six symbols the `nums1` and `set1` Content Dictionaries define and the base
  vocabulary lacked: `based_integer`, `based_float`, `bigfloat`, `complex_polar`,
  `gamma` (Euler's constant, not the function) and `emptyset`. Appendix F builds
  applications of all six out of `<cn>`, so a document could transform correctly
  and then be refused by the phrasebook.

### Fixed

- `arith1#root` applied to one argument. `<root/>` with no `<degree>` qualifier
  is the square root, and the missing `2` was not being supplied — so the
  Symbolics phrasebook raised `MethodError`. Found by the MathML.jl oracle, and
  only by its shared-document path: the hand-written pairs supply the OpenMath
  side themselves, so they asserted a `root(x, 2)` nothing produced.
- `transc1#log` applied to one argument, the same defect a section later.
  `<log/>` with no `<logbase>` is base 10 (MathML 4 §4.3) and `transc1#log` takes
  the base first — the `transc1` CD's own FMP reads `log(a, c) = b` when
  `a^b = c`.
- The Symbolics phrasebook read `transc1#log(10, x)` as `log(x)/log(10)`: the
  same number, a different expression, and enough to stop the round trip being
  the identity. Base 10 and base 2 now map onto `log10` and `log2`, which
  Symbolics keeps whole — as `arith1#root(a, 2)` already mapped onto `sqrt` —
  and `to_openmath` writes all three back.
- Refusals of real Content MathML — `<logbase>`, `<interval>` — claimed it was
  "not Content MathML at all". The refusal was right and the reason was false,
  which is worse than a generic message: it tells a reader to stop looking for a
  rule that exists. Every refusal now names its Appendix F section.

### Security

- The gate enforcing that parsed content never reaches `eval` walked `src/` and
  not `ext/`. The `Symbolics` extension is the one place in this package that
  turns an OpenMath symbol into a call, and it sat outside the gate. It was
  clean; it was clean unwatched.
- `SECURITY.md` said "names are `String`, never `Symbol`" without its exception.
  Decoding a document interns nothing, which is what the object model is for, but
  `from_openmath` interns — and a service that decodes untrusted OpenMath and
  converts it will intern every distinct variable name it is sent, unreclaimably.
  The claim now says *by a parser*; the exception has a remedy
  (`define_variable!(p, identity)`), a test, and a paragraph of its own.
- `.gitattributes` exempts `test/corpus/` from line-ending translation. The
  corpus is byte-exact test vectors and an `OMSTR`'s content is significant
  whitespace, so a fixture git rewrites tests something different — which is what
  the first Windows CI run decoded.

### Fixed

- `read_json` raised a `MethodError` instead of an `OpenMathParseError` for a
  foreign document object — a call site left behind when the reader's error paths
  became a linked list. It breaks the one thing REQ-SEC-001 promises, and JET
  found it on Julia 1.10 after passing on 1.13.
- `Pkg` and `Random` were used by the test suite and declared by nothing, so a
  clean checkout failed on every Julia version while a grown local manifest hid
  it. A quality gate now checks statically that every module a test file `using`s
  is a declared dependency.

### Added

- `docs/src/round-trip.md` — what survives a round trip and what does not, in one
  place. The three text encodings lose nothing; the binary encoding loses exactly
  four things, each a consequence of what §3.2 has no field for: an `OMFOREIGN`
  whose `encoding` is `""` (a zero length is the only way to say both "absent"
  and "empty"), an `id` nothing references, the *names* of shared objects — the
  structure is exact — and a forward reference, which is refused rather than
  silently expanded. The table is asserted in `test/unit/cross_encoding.jl`, so a
  new loss fails and so does a loss quietly fixed without the page being updated.

- Reading JSON is twice as fast and allocates 41 % less: 38 → 22.3 allocations
  per node and 2.40 → 1.20 ms on a 1601-node document, which is parity with the
  XML reader. Two defects, both found by following the benchmark table rather
  than a hunch — an `IOBuffer` allocated for every string including the majority
  with no escape, and error paths built eagerly at every node whether or not
  anything went wrong.
- **The JSON reader builds on an explicit stack.** It was the last recursive
  traversal in the package, overflowed at about 20 000 levels, and Julia's message
  on the way out was "program state may be corrupted" — the outcome REQ-SEC-002
  exists to prevent. Unreachable at the default limits, reachable by raising
  `max_depth`, which is the documented way to accept a deep document. A
  200 000-level JSON document now parses, as it always did in the other three
  encodings. `docs/src/security.md` has claimed "every traversal uses an explicit
  stack" since Phase 1; the claim is true again.
- `test/unit/cross_encoding.jl` — properties every encoding must share, in one
  place, parametrised over all four. Two defects survived this session because
  the conformance driver checks the encodings agree about *objects* and never
  that they share implementation properties, and both readers agreed about
  objects right up to where one stopped producing any.

- **Time to first parse falls from 4.1 s to 0.32 s** (roadmap Phase 8). A
  `PrecompileTools` workload in `src/precompile.jl` caches what was pure
  first-call compilation. The measurement decomposed it first: bare Julia
  0.121 s, `using OpenMath` 0.147 s, and the first `parse` 4.132 s — loading the
  package was never the problem, and cost 26 ms.
- `PrecompileTools` is consequently this package's first runtime dependency. It
  is pure Julia with no binary artifact, so REQ-PRJ-002 holds, and the quality
  gate that enforced it was rewritten to check the requirement rather than its
  proxy: it now walks the resolved dependency graph and fails on any `_jll`,
  which also catches transitive ones that counting direct dependencies never
  could.
- `just bench` — throughput, allocations per node and time to first parse;
  `just bench --save` records `test/harness/baseline.toml`, which is what "no
  regression" is measured against. The binary encoding measures 2.7× smaller
  than XML and reads five times faster with a third of the allocations; reading
  JSON is the slow path at 38 allocations per node.
- `docs/src/performance.md` carries the numbers.

- `define_leaf!`: what a phrasebook makes of a *literal*. Without it a phrasebook
  whose symbols map onto ordinary Julia functions **evaluates** — `transc1#sin`
  applied to `OMI(-8)` returned −0.9893… where `sin(-8)` went in, and evaluation
  is an explicit non-goal (REQ-PHR-006). Found by the generated property, not by
  any hand-written case.
- Property **P9** over generated Symbolics expressions. It asserts *idempotence*
  rather than identity, which is a fact about Symbolics rather than a weakening:
  it keeps several representations of one object and `isequal` is structural, so
  the first round trip may land on a different representative and every one after
  is a fixed point. It also found a unary `arith1#times` — a Symbolics
  representation artefact — reaching the output, now collapsed by the writer.

- `piece1#piecewise` ↔ `ifelse`, plus `relation1` comparisons and `logic1`
  connectives. A piecewise with no `otherwise` is refused, and so is an equality
  used as a condition: `relation1#eq` becomes a Symbolics `Equation`, which
  `ifelse` cannot take, and Symbolics has no symbolic equality predicate.
- `just oracle-mathml` — a differential test of the phrasebook against MathML.jl
  on 21 hand-written pairs, each the same object written in both dialects.
  **19/21 agree.** The two that do not are `rounding1#floor` and
  `rounding1#ceiling`, where MathML.jl deliberately returns a smooth Fourier
  approximation because its expressions end up in differential equation solvers.
  Both implementations are right for their purpose; the divergence is documented
  rather than reconciled.

- **A `Symbolics.jl` bridge** (roadmap Phase 6, REQ-PHR-002), as the package
  extension `OpenMathSymbolicsExt`. `to_openmath` on a `Num`, an `Equation` or a
  `Differential`; `OpenMath.symbolics_phrasebook()` for the way back.
  `calculus1#diff` applies to an `fns1#lambda` binding, because OpenMath has no
  free-standing derivative operator.
- **Decision D5**: an extension, not a companion package. The survey found the
  pinning churn that motivated the companion option is MathML.jl's, not
  Symbolics', and a weak dependency inherits no pin.
- `define_variable!` lets a phrasebook say what a *variable* becomes — a `Symbol`
  by default, a Symbolics variable for the bridge. Making that a method on
  `interpret` would have been global, and two phrasebooks in one session could
  then not disagree.
- Symbolics normalises before we see an expression, so the encoding is of the
  normal form: `-x` comes out as `arith1#times(-1, x)`, never
  `arith1#unary_minus`. The tests assert the normalised result rather than the
  intuitive one, and the docs say so before a reader discovers it.

- **Phrasebooks as values** (roadmap Phase 6): `Phrasebook`, `define!`,
  `interpret`, `express`, `symbols`, `base_vocabulary`, `with_phrasebook` and
  `current_phrasebook`. Two callers in one session may legitimately disagree
  about what `nums1#rational` denotes, and a method table cannot hold both
  readings; a value can (REQ-PHR-001).
- The built-in vocabulary is 87 symbols across `arith1`, `transc1`, `relation1`,
  `logic1`, `nums1`, `fns1`, `integer1`, `rounding1`, `minmax1`, `complex1`,
  `linalg2`, `list1`, `set1` and `s_data1` — **76 of MathML.jl's 85 element
  names, which is all of them that denote a symbol**. The correspondence is
  asserted element by element rather than described.
- `from_openmath` now routes symbols and applications through the phrasebook in
  force, so the vocabulary is replaceable without a keyword argument threaded
  through every caller. Everything it interpreted before, it still interprets.
- Interpretation is structural and never evaluates (REQ-PHR-003): a symbol name
  is a key in a dictionary, so `OMV("exit")` is the Julia symbol `:exit`, not
  `Base.exit`. A symbol with no entry raises and names itself rather than being
  dropped (REQ-PHR-005).

- **A differential oracle for the binary encoding** (roadmap Phase 4b):
  `just oracle-gap-setup` installs GAP 4.15.1 and its `openmath` package into
  gitignored `refs/`, and `just oracle-gap` runs the comparison in both
  directions. Same licence boundary as the Rust oracle — GPL run as a
  subprocess, never linked, no source read. GAP names the values itself, because
  it is a computer algebra system: handed `arith1#plus(1, x)` it tries to
  *evaluate* it, so a corpus-through-GAP oracle would measure its phrasebook
  rather than its codec.

  ```
  we write → GAP reads   34/34 agree
  GAP writes → we read   26/30 agree, 4 blocked by an upstream defect
  ```

- `just gap-vectors` downloads the binary streams GAP's package ships in `tst/`.
  `read_binary` decoded all ten of them first try, which is also the streaming
  requirement proved on a real file: ten objects only come out of one stream if
  the reader stops at each end tag.

- **Binary encoding** (standard §3.2, roadmap Phase 4): `read_binary`,
  `write_binary`, `OpenMath.binary` and
  `show(io, MIME"application/openmath+binary", …)`. This completes the four
  encodings the standard endorses. `OpenMath.parse` now accepts bytes as well as
  text, and sniffs binary from the object tag.
- Reading an `IO` consumes exactly one object and leaves the rest of the stream
  alone, so a socket carrying a sequence of objects can be read one at a time —
  which is how SCSCP uses this encoding. Reading a byte vector still requires the
  whole vector to be one document.
- Structure sharing on both sides: the writer flags exactly the objects some `OMR`
  points at and numbers them in completion order; the reader mints `id`s so an
  `OMR` comes back as an `OMR` rather than as an inlined copy. A forward
  reference — legal in XML, inexpressible here — raises
  `OpenMathConversionError` naming `expand_references` instead of being silently
  inlined.
- The deprecated OpenMath 1 sharing form of §3.2.4.1 and the streamed packets of
  §3.2.2 are read and never written.
- Every length field is checked against the byte budget before it is acted on, so
  a stream claiming four gigabytes raises `OpenMathLimitError` rather than
  allocating (REQ-BIN-006).
- **Decision D8**: the document tag is `[24]` unless `[24+64]` buys something —
  structure sharing, or a version other than 2.0. §3.2.6 keeps `[24]` valid in
  OpenMath 2, and GAP *rejects* `[24+64]` outright, so the earlier default was
  unreadable by the only other implementation.
- **Decision D9**: big integers are written in base 16, not base 256. GAP renders
  each base-256 digit byte as hexadecimal without padding it to two characters, so
  any byte below `0x10` drops a zero and the value arrives smaller than it left.
  The standard's own worked example happens to have no such byte, which is how the
  defect survived since 2016.
- **Decision D7** (`docs/src/design/binary-backend.md`): §3.2 contradicts itself
  about whether a tag carrying the sharing flag also carries an identifier
  string. Figure 3.3 says it does, Figures 3.5 and 3.6, §3.2.4.2 and §3.2.5 say
  it does not, and the grammar disagrees with itself within one production. This
  package follows the figures. The four defects are written up in
  `upstream-bugs.md`.
- `test/corpus/binary-vectors.toml` transcribes every byte sequence the standard
  prints in §3.2, including the two that are wrong, with the repaired form beside
  each. It was written before the codec, because the oracle we had — the Rust
  reference crate — lists "binary format" under TODO. GAP's `openmath` package
  does implement this encoding and is an oracle we have not used yet; see
  roadmap Phase 4b.
- Property **P4** (binary round-trip, cross-encoding agreement, write stability)
  and **P4b** (the reader is total over noise, truncations and single-byte flips)
  join the blocking property layer. P4 found three `cdbase` defects no example
  test reached.
- Invalid binary documents can now live in the corpus: `check_invalid` tries every
  encoding an item carries rather than XML alone.
- `docs/src/encodings.md` documents all four encodings side by side, including
  what the binary encoding does not round-trip and why.

- **Strict Content MathML** (MathML 4 §4.1.3, roadmap Phase 7): `read_mathml`,
  `write_mathml`, `OpenMath.mathml` and `show(io, MIME"application/mathml+xml", …)`.
  This is the fourth encoding the OpenMath standard endorses, and it needs no
  dependency — it is XML, and the tokenizer is already here. Enabling it in the
  conformance driver took the suite from 6070 assertions to 6462 with no new
  corpus files.
- `cn` carries the mandatory `type` the strict subset requires, and `hexdouble`
  carries `NaN` and the infinities, which MathML has no literal for either — the
  same answer as XML's `hex=` and JSON's `hexadecimal`, reached by the same
  round-trip test.
- Non-strict Content MathML is rejected rather than guessed at: operator
  elements, untyped `<cn>`, non-strict `cn` types and presentation markup all
  produce an error naming why (REQ-MML-004).

- **Content Dictionaries** (roadmap Phase 5): `parse_cd` and `parse_sts` read the
  `.ocd` and `.sts` formats using this package's own XML tokenizer, handing the
  embedded `<OMOBJ>` documents to `read_xml` so they get the same limits and the
  same errors as any other document. `CDRegistry` resolves `(cdbase, cd)` pairs,
  and `lookup`, `describe`, `signature`, `arity` and `validate_against_cds` work
  from it.
- Arity comes from the Small Type System: a signature reads
  `mapsto(T₁, …, Tₙ, Result)`, so the arity is one less than the argument count,
  and a parameter wrapped in `sts#nassoc` makes the symbol n-ary.
- `validate_against_cds` is deliberately separate from `validate`. A document
  using a private dictionary is well formed; it is simply not resolvable here, and
  conflating the two would make every private extension look broken.

- **JSON encoding** (standard §3.3, roadmap Phase 3): `read_json`, `write_json`,
  `OpenMath.json` and `show(io, MIME"application/openmath+json", …)`, plus JSON
  sniffing in `format = :auto`. All three spellings of `OMI` and `OMF` are read —
  `integer`/`float`, `decimal` and `hexadecimal` — and the writer picks the one
  that does not lose the value: a `decimal` string past 2⁵³, and `hexadecimal` for
  `NaN` and the infinities, which JSON has no literal for.
- Decision **D3** recorded in `docs/src/design/json-backend.md`: the JSON backend
  is purpose-built and the package still has **no dependencies at all**. A general
  JSON parser hands back a `Float64` for a 200-bit `"integer"`, destroying the
  value before our code sees it.
- Enabling JSON in the conformance driver gave all 39 existing corpus items JSON
  coverage **without a single new file**, which is what §6.2's derivation promise
  was for. 14 JSON-only items from the standard's §3.3 examples exercise the
  reverse direction.
- Property **P3**: XML and JSON agree on arbitrary generated objects.

- **Differential oracle** against the reference `openmath` Rust crate (harness
  spec §4.7), as an **opt-in command rather than a CI job**: `just oracle-setup`
  downloads the pinned reference crate and builds a small GPL-3 wrapper under
  `refs/` — outside the MIT package, gitignored, never distributed — and
  `just oracle` runs the corpus through both implementations, comparing canonical
  forms rather than text, since the two legally differ on attribute order and on
  where they choose to write `cdbase`. `just oracle-clean` removes both again.
  CI never invokes any of it, so the pipeline stays hermetic and free of GPL-3
  artefacts. The comparison runs in two directions, so that our *writer* is
  checked against an independent implementation and not only our reader.
- Five upstream limitations recorded in `upstream-bugs.md`, each triaged against
  Python's expat first so that "the oracle rejected it" never silently means "we
  produced something malformed".
- **Property-based layer** on `Supposition.jl` (harness spec §6.4): generators for
  arbitrary OpenMath objects — all eleven kinds, with the `Int64` boundaries, the
  floats that have no decimal spelling, the signed zeros, empty strings and byte
  arrays and non-ASCII names deliberately over-represented — and eight properties:
  canonical-form idempotence, XML round-trip in both compact and pretty form,
  byte-level writer stability, `minimize_cdbase`/`resolve_cdbase` stability and
  meaning-preservation, the base64 bijection, totality of `validate`, and that
  parsing stays inside `OpenMathError` for arbitrary Unicode and for every
  truncation of a well-formed document.
- Shrunk counterexamples are persisted automatically: when a property is
  falsified, the minimal object Supposition arrives at is written into
  `test/corpus/regression/` as an ordinary corpus item. It is then checked by the
  conformance driver in every encoding, including ones that did not exist when it
  was found, and is covered by the corpus manifest so it cannot be quietly
  removed. This is the mechanism by which the harness compounds: the property
  layer explores, the corpus remembers.
- A vacuity check on the generators: a property that holds because the generator
  only ever built `OMI(0)` holds vacuously, so the layer asserts a floor on the
  diversity of what was actually generated.
- `just corpus-fetch` downloads conformance vectors from the official Content
  Dictionaries, and `just conformance-full` runs the suite against them: 342 items
  taking it from 945 assertions to 6070. They are **not** committed — they land in
  gitignored `refs/` — because extracted dictionary content is a derived work
  whose licence asks more of it than a test fixture should carry.
- **Conformance corpus and driver** (harness spec §6.2/§6.3): 60 items — 39 valid,
  21 invalid — under `test/corpus/`, each a directory with the encodings it
  carries, an optional expected value and a `meta.toml` recording provenance. The
  driver checks agreement between encodings, the recorded expectation, the round
  trip, byte-level idempotence, cross-encoding agreement and validation. It
  derives the encodings an item does not carry from the ones it does, so a
  fixture added as XML today starts exercising JSON and binary the day those
  writers land, with no edit to the item.
- `just corpus-check` is now load-bearing: `corpus/MANIFEST.sha256` pins all 158
  files, additions are free, and modifying or deleting an existing item fails the
  gate unless the commit carries a `Corpus-Change:` trailer.
- The verifier's `conformance` gate runs the corpus instead of reporting
  `not_run`.
- **XML writer** (standard §3.1, roadmap Phase 2, cards 002/003/004):
  `OpenMath.xml`, `write_xml` and `show(io, MIME"application/openmath+xml", …)`.
  `cdbase` is emitted only where the effective base changes; `OMF` takes `hex=`
  exactly when the decimal form would lose the value, which is implemented as the
  round-trip check the requirement describes rather than as a list of special
  cases; `pretty` mode never alters character data. Emission runs on an explicit
  work stack, so a 200 000-deep object writes without touching the native stack.
- **XML reader** (standard §3.1, roadmap Phase 2, cards 001/004/005 and the
  reader halves of 003 and 006): `OpenMath.parse`, `OpenMath.parsefile`,
  `OpenMath.sniff_format` and `read_xml`, covering all fifteen element names,
  `cdbase` scoping, `id`/`href`, namespace prefixes, and the three strictness
  modes.
- Purpose-built XML pull tokenizer (`src/xml/tokenizer.jl`): elements,
  attributes, character data, CDATA, comments, processing instructions, the five
  predefined entities and numeric character references. Document type
  declarations, entity declarations and any other entity reference are refused —
  the billion-laughs class of attack is absent rather than mitigated.
- `OMI` accepts signed decimal and `x`-prefixed hexadecimal; `OMF` accepts `dec`
  and `hex`, so `NaN`, the infinities, the signed zeros and subnormals survive
  decoding bit-exactly.
- Base64 codec for `OMB` (`src/base64.jl`), skipping insignificant whitespace and
  reporting a byte offset on every rejection.
- `OMFOREIGN` content is captured verbatim, including embedded markup.
- `OMObject` gained a `warnings` field recording what a `:lenient` parse accepted.
- Decision **D1** recorded in `docs/src/design/xml-backend.md`: the XML backend is
  purpose-built, because REQ-PRJ-002 excludes a compiled binary artifact from the
  core and REQ-SEC-001/REQ-API-007 are cheaper to satisfy by owning the tokenizer
  than by wrapping one.

### Changed

- Decision **D1** re-examined against `XML.jl` v0.4.6 with measurements, and the
  reasoning corrected. Two of the three original arguments do not survive: the
  binary-artifact objection applies to `EzXML.jl`, not to pure-Julia `XML.jl`, and
  `XML.jl` *can* capture verbatim source through `sourcetext`, which I had assumed
  it could not. One argument decides it: `XML.jl` passes an undeclared entity
  reference through as literal text, so `<OMSTR>&xxe;</OMSTR>` would silently
  become the string `"&xxe;"` and write back out as `"&amp;xxe;"` — a document
  that changed meaning with nothing reported. That cannot be detected afterwards,
  because once the text is decoded an expanded `&lt;` and a literal `<` are the
  same character. The cost is recorded too: we are 5.7× slower than `XML.jl`.

- `canonicalize` now resolves `cdbase` **before** collapsing attributions. The
  order is load-bearing: `collapse_attributions` may only merge an `OMATTR` that
  carries no `cdbase` of its own, so collapsing first made the normal form depend
  on *where* the base happened to be written — `OMATTR(OMATTR(x, a), b)` flattened
  when the inner node had no base and did not when an equivalent document put one
  there. Found by the property layer within minutes of its existing; it had
  falsified the XML round trip and both `minimize_cdbase` properties.
- `OMForeign.value` is the **verbatim source** of the foreign content rather than
  decoded text. The standard allows arbitrary XML there, so decoding entity
  references made embedded markup indistinguishable from text that merely looks
  like markup and broke the lossless round trip (REQ-OM-003). The writer refuses
  foreign content that is not a well-formed fragment instead of escaping it,
  because escaping would change the value.

### Fixed

- The binary writer emitted `[24+64]` for every document and base-256 digits for
  every big integer. Both were legal and neither was interoperable: GAP rejects
  the first outright and misreads the second. Found by the oracle above, on its
  first run.

- An `OMR` whose `href` is not a bare fragment is an **external** reference —
  it names an object in another document (standard §3.1.2, and the binary
  encoding gives internal and external references separate tokens, 30 and 31).
  `validate` reported one as a dangling reference and `expand_references` threw on
  it, which made every document citing another one unusable. They are now left
  alone by the passes, and only a fragment-only reference with no matching `id`
  is dangling. `isinternal` and `reference_target` name the distinction.
  Found by the official `scscp1` dictionary, which does exactly this.

- `OpenMath.xml` and `OpenMath.json` accepted `OMOrForeign`, promising in their
  signature that they could serialise foreign content as a document root — but
  `OMObject` takes an `OMNode`, because foreign content is not an OpenMath object.
  `OpenMath.xml(OMForeign(…))` therefore raised a bare `MethodError`, outside the
  `OpenMathError` family the API promises. The signatures now say `OMNode`.
  **Found by JET**, and by nothing else: the corpus, the property layer and the
  differential oracle all only ever place foreign content *inside* a document.

- Two quadratic behaviours in the XML reader, both on the attacker-controlled
  depth dimension and therefore denial-of-service rather than merely slow paths:
  - error-path construction materialised `/OMOBJ/OMA/OMA/…` at every level, which
    exhausted memory on a deeply nested document. The path is now walked only
    when an error is raised.
  - namespace resolution searched a stack of partial scopes from the top. Each
    frame now holds the fully resolved mapping and shares its parent's dictionary
    by reference unless the element declares an `xmlns`. A 200 000-deep document
    went from 8 min 30 s to 2.8 s.
- `SubString` over byte ranges in the tokenizer threw `StringIndexError` on any
  multi-byte character — an `OMV` named `λ` was enough — and that is outside the
  `OpenMathError` family the API promises (REQ-SEC-001). Slicing now goes through
  the code units, which is also correct for malformed UTF-8.
- Warnings recorded by a `:lenient` parse grew without bound on hostile input:
  the missing-namespace warning was emitted per element rather than once, and
  nothing capped the list. Document-wide warnings are now reported once and the
  list is capped, with a trailing count of what was suppressed.

## [0.0.1] - 2026-09-17

Phase 0 (scaffolding and harness) and Phase 1 (object model) of `ROADMAP.md`.

### Added

- **JSON encoding** (standard §3.3, roadmap Phase 3): `read_json`, `write_json`,
  `OpenMath.json` and `show(io, MIME"application/openmath+json", …)`, plus JSON
  sniffing in `format = :auto`. All three spellings of `OMI` and `OMF` are read —
  `integer`/`float`, `decimal` and `hexadecimal` — and the writer picks the one
  that does not lose the value: a `decimal` string past 2⁵³, and `hexadecimal` for
  `NaN` and the infinities, which JSON has no literal for.
- Decision **D3** recorded in `docs/src/design/json-backend.md`: the JSON backend
  is purpose-built and the package still has **no dependencies at all**. A general
  JSON parser hands back a `Float64` for a 200-bit `"integer"`, destroying the
  value before our code sees it.
- Enabling JSON in the conformance driver gave all 39 existing corpus items JSON
  coverage **without a single new file**, which is what §6.2's derivation promise
  was for. 14 JSON-only items from the standard's §3.3 examples exercise the
  reverse direction.
- Property **P3**: XML and JSON agree on arbitrary generated objects.

- Requirements baseline in EARS syntax with MoSCoW priorities
  (`specs/requirements.md`), design specification (`spec.md`), delivery plan
  (`ROADMAP.md`) and agentic harness specification (`specs/harness/`).
- Complete OpenMath 2.0 object model: `OMInteger`, `OMFloat`, `OMString`,
  `OMBytes`, `OMVariable`, `OMSymbol`, `OMApplication`, `OMBinding`, `OMError`,
  `OMAttribution`, `OMForeign`, `OMReference`, plus `OMObject`,
  `OMAttributePair` and `OMBoundVariable`.
- `Name` production validation (standard §2.3) and `cdbase` URI syntax checking.
- Structural equality and hashing that disregard `id`, plus `isequal_with_ids`
  for byte-fidelity comparison.
- Traversal: `kind`, `children`, `walk`, `collect_nodes`, `count_nodes`,
  `depth`, `map_openmath` — all using an explicit stack.
- Validation of the object graph: reference cycles, dangling references,
  duplicate ids, `cdbase` syntax, depth and node-count budgets.
- Normalisation passes: `resolve_cdbase`, `minimize_cdbase`,
  `collapse_attributions`, `expand_references`, `strip_ids`, `canonicalize`.
- Configurable, scoped resource limits (`OMLimits`, `limits`, `with_limits`)
  raising a catchable `OpenMathLimitError` instead of `StackOverflowError`.
- Conversion interface `to_openmath` / `from_openmath` with built-in mappings for
  integers, floats, strings, symbols, booleans, byte vectors, rationals,
  complexes, vectors and matrices.
- Callable `OMSymbol` and the `OMS"cd#name"` string macro, validated at
  macro-expansion time.
- Compact functional rendering through `show`.
- Development harness: `just verify` with three latency tiers and a stable JSON
  output contract, failure records carrying a requirement back-reference and a
  hand-written hint, and run logging to `.agent/runs/`.
- `just fuzz` mutation-fuzzes the readers against the invariant that no byte
  string escapes the `OpenMathError` family, and `Fuzz.yml` runs it nightly. The
  inputs are corrupted corpus documents rather than random noise. A two-minute
  run covers about a million inputs.
- `Invalidations.yml` compares method invalidations on a pull request against the
  default branch, so latency a change costs downstream users is visible before it
  is merged.
- SciML formatting applied across the package and enforced by `just quality`;
  `just format` applies it.
- Quality gates: formatting, JET (blocking on findings in our own source), `ExplicitImports`,
  Aqua, SPDX headers, dependency hygiene, and a gate asserting
  that parsed content is never evaluated.
- Harness guardrails: `just corpus-check` (corpus integrity manifest),
  `just clean-room` (no verbatim overlap with the GPL-3 reference crate) and
  `just next` (first unblocked task card).
- Documentation built with Documenter, emitting `llms.txt` and `llms-full.txt`
  into the built site.
- Task cards for Phase 2 in `specs/tasks/`.

[Unreleased]: https://github.com/s-celles/OpenMath.jl/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/s-celles/OpenMath.jl/releases/tag/v0.0.1
