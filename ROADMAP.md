<!-- SPDX-License-Identifier: MIT -->

# OpenMath.jl — Roadmap

Companion to `spec.md`. Section references (§) point into that document.

**Principles**

1. **Harness before implementation.** Every phase starts by extending the conformance
   harness (§6) with failing tests, then makes them pass. No feature ships without a
   corpus item and a property.
2. **Monotone corpus.** Corpus items are never deleted, only added. Because the driver
   derives missing encodings from whichever one is present (§6.2), a fixture added in
   Phase 2 automatically starts exercising JSON in Phase 3 and binary in Phase 4.
3. **Green trunk.** `just all` (format, quality, test, docs — docs with zero warnings)
   passes on every commit to `main`.
4. **Semantic Versioning**, `CHANGELOG.md` in Keep a Changelog format, updated in the
   same commit as the change.
5. **Supported Julia**: 1.10 (LTS) and 1.13 (current release) are both blocking CI
   targets on ubuntu / macOS / Windows; nightly and pre-release run as
   `continue-on-error`. Any dependency that cannot serve both 1.10 and 1.13 is
   disqualified or confined behind a package extension.

**Version ladder**

| Version  | Phase | Theme                                   |
|----------|-------|-----------------------------------------|
| `0.0.1`  | 0     | Scaffolding + test harness (no features)|
| `0.1.0`  | 1     | Object model                            |
| `0.2.0`  | 2     | XML encoding                            |
| `0.3.0`  | 3     | JSON encoding                           |
| `0.4.0`  | 4     | Binary encoding + structure sharing     |
| `0.5.0`  | 5     | Content Dictionaries                    |
| `0.6.0`  | 6     | Symbolics.jl phrasebook                 |
| `0.7.0`  | 7     | Strict Content MathML encoding          |
| `0.8.0`  | 8     | Performance, latency, hardening         |
| `0.9.0`  | 9     | API stabilisation + registration        |

No `1.x` milestone is planned yet. Under Semantic Versioning a `0.x` series says
the public API may still change in a minor release, which is the honest signal
while the encodings and the phrasebooks are still settling. A `1.0.0` is declared
when the API has held still across a few releases and downstream users exist —
not on a date.

---

## Phase 0 — Scaffolding and the harness `v0.0.1`

**The deliverable of this phase is the harness itself.** At the end of Phase 0 the
package exports nothing useful and every conformance test is red — by design.

### 0.1 Repository scaffolding

- [x] `BestieTemplate.jl` scaffold; `Project.toml` with `uuid`, `authors`,
      `[compat] julia = "1.10"`.
- [x] `LICENSE.md` — MIT; SPDX header (`# SPDX-License-Identifier: MIT`) on every
      source file, enforced by `just quality`.
- [x] `just clean-room` — grep gate asserting no verbatim run of ≥ 8 tokens shared with
      `refs/rust-openmath/` (§1.3 of the spec: we are MIT, the reference is GPL-3).
- [x] `SECURITY.md` with GHSA private-disclosure instructions; the threat model is
      "hostile OpenMath payload over SCSCP / HTTP" (§5.4).
- [x] `CODE_OF_CONDUCT.md` — Contributor Covenant, latest version.
- [x] `CHANGELOG.md`, `CONTRIBUTING.md`, `upstream-bugs.md` (empty, with the template
      header: package name + exact version + minimal reproducer).
- [x] `.gitignore` using the gitallow (deny-by-default, explicit allow) pattern.
- [x] `justfile` with all targets from §6.9, each a no-op stub that exits non-zero if
      unimplemented rather than silently succeeding.

### 0.2 CI and automation

- [x] `CI.yml`: matrix `julia-version: [ "1.10", "1.13" ]` (blocking) ×
      `os: [ubuntu-latest, macOS-latest, windows-latest]`, plus `["nightly", "pre"]`
      on ubuntu with `continue-on-error: true`.
- [x] `Documenter.yml` — build must fail on any warning.
- [x] Codecov upload; `Invalidations.yml`; `Dependabot`; `TagBot`; `CompatHelper`.
- [x] **No** oracle job. The differential test needs a network clone and a Rust
      toolchain and produces a GPL-3 binary, so it is an opt-in command
      (`just oracle-setup` then `just oracle`) rather than a pipeline step. CI
      stays hermetic and free of GPL-3 artefacts; see §6.5.
- [x] `Fuzz.yml` — nightly, budget-limited, uploads any new counterexample as an
      artifact. The inputs are mutations of real corpus documents rather than
      random noise: random bytes almost never get past the first character, so
      they exercise one branch of the tokenizer and nothing else, whereas a
      corrupted *valid* document reaches deep into the reader — and is also what a
      flaky peer actually produces.

### 0.3 Documentation skeleton

- [x] `Documenter.jl` + `DocumenterLandingPage.jl`; pages: Home, Getting Started,
      Object Model, Encodings, Content Dictionaries, Phrasebooks, API, Conformance.
- [x] The doc build emits `llms.txt` and `llms-full.txt` **into the built site**, not at
      the repository root.
- [ ] A "Conformance" page generated from the harness's machine-readable report
      (§6.1 `harness/report.jl`), so the published docs always show live coverage of
      the corpus per encoding.

### 0.4 Harness core

- [x] `test/harness/corpus.jl` — `CorpusItem` discovery, `meta.toml` parsing, tag
      filtering, `skip` handling.
- [x] `test/harness/Harness.jl` — the seven-step conformance driver (§6.3), with
      failure output as a unified diff of canonical forms, never a bare `false`.
- [x] `test/harness/generators.jl` — `Supposition.jl` generators (§6.4); the ones that
      do not depend on the object model (`gen_name`, `gen_integer`, `gen_float`) are
      written and self-tested now.
- [x] `test/harness/oracle.jl` + `oracle_build.jl` — subprocess plumbing, opt-in
      via `just oracle-setup` / `just oracle`, never reached from CI.
- [x] Auto-persistence of shrunk counterexamples into `corpus/regression/`.
- [x] `test/runtests.jl` using `TestItemRunner.jl` with tags
      `:unit :conformance :property :oracle :fuzz :quality :slow`.

### 0.5 Initial corpus

- [x] `just corpus-fetch` downloads every `<OMOBJ>` from the official Content
      Dictionaries into gitignored `refs/corpus-cd/`; `just conformance-full` does
      that and runs the suite against them. 342 items from the 38 official
      dictionaries, taking the conformance suite from 945 assertions to 6070.
      Nothing is committed. Items our own reader rejects are recorded as negative
      cases, with a tripwire: if more than 2 % are rejected, the harvest refuses,
      because a few bad documents among hundreds is upstream and that many is us.
- [x] Hand-transcribe the examples from omstd20 §2 and §3 into `corpus/standard/`,
      including the deliberately tricky ones: nested `cdbase` scoping, `OMF` with
      `hex=`, `OMI` in hexadecimal, attributed bound variables, `OMFOREIGN` in an
      attribute value, `OMR` back-references.
- [x] Seed `corpus/invalid/` with: `OMA` with zero children, `OME` whose head is not an
      `OMS`, cyclic `OMR`, bad `Name` production, DTD/external entity, 1e6-deep nesting.

### 0.6 Quality gates live from day one

- [x] `Aqua.jl` and `ExplicitImports.jl` in `just quality`.
- [x] `JuliaFormatter` (SciML style) applied and gated in `just quality`, with
      `.JuliaFormatter.toml` carrying the settings so the gate and `just format`
      cannot drift apart. 54 files, about 750 lines. Markdown is excluded: turning
      it on rewrote the `LICENSE` copyright line into a markdown link and reflowed
      prose wrapped on meaning rather than column count.
- [x] `JET.jl` wired.

**Exit criteria** — `just test` runs, the harness discovers ≥ 300 corpus items, every
conformance test reports *red for a known reason* (feature unimplemented, not harness
bug), `just quality` and `just docs` are green, CI is green on 1.10 and 1.13.

---

## Phase 1 — Object model `v0.1.0`

- [x] `src/types.jl` — the twelve node types, `OMObject`, `OMAttributePair`,
      `OMBoundVariable`, `OMOrForeign` (§2.1). Freeze decision **D2** (`OMATTR` as a
      first-class node) before tagging.
- [x] `src/names.jl` — the `Name` production (§2.3 of the standard), URI validation for
      `cdbase`; `OMS"cd#name"` string macro with compile-time validation.
- [x] `src/show.jl` — `MIME"text/plain"` functional form; `MIME` stubs for the encodings.
- [x] Structural `==` / `hash` ignoring `id`; `isequal_with_ids`.
- [x] `src/validate.jl` — all constraints of §2.4, returning `OMValidationIssue`s.
- [x] `src/passes.jl` — `resolve_cdbase`, `minimize_cdbase`, `collapse_attributions`,
      `expand_references`, `share_structure`, `canonicalize` (§2.5).
- [x] `src/limits.jl` — `OPENMATH_MAX_DEPTH/NODES/BYTES`; all traversals use an
      **explicit stack**, no native recursion (§5.4).
- [x] `src/interface.jl` — `to_openmath` / `from_openmath`, `OMWriter` abstract type and
      the `write_*!` verbs (§3.2), `TreeWriter`.
- [x] Callable `OMSymbol` (§5.2).
- [x] Harness: `gen_node`, `gen_object`; properties **P1**, **P4**, **P5**, **P7**.
- [x] `JET.jl` gate blocking on findings whose failure point is in our own source.
      It found a real one on the way in: see the CHANGELOG for 0.0.1.

**Exit criteria** — `corpus/*/object.jl` fixtures all construct and validate; P1/P4/P5/P7
green at 10 000 examples; `canonicalize` proven idempotent; zero JET findings;
coverage ≥ 90 % on `src/`.

---

## Phase 2 — XML encoding `v0.2.0`

- [x] Resolve decision **D1**. Settled in favour of a purpose-built pull tokenizer
      rather than either candidate; two **Must** requirements decide it before
      performance does. Recorded in `docs/src/design/xml-backend.md`.
- [x] `src/xml/reader.jl` — streaming, explicit-stack, namespace-aware, DTD and
      external entities rejected, `id`/`href` collected, `cdbase` scoping tracked.
- [x] `src/xml/writer.jl` — `cdbase` emitted only on change; `pretty` mode; `OMF`
      `dec=` vs `hex=` selection rule (§4.1); `OMI` decimal/hex; `OMSTR` whitespace
      fidelity; XML escaping including the `]]>` and control-character cases.
- [x] `src/base64.jl` — pure-Julia `OMB` codec, property **P6**.
- [x] `src/bigint.jl` — folded into the reader and writer rather than a separate file — `OMI` beyond `Int64`, hexadecimal form, negative hex.
- [x] `OpenMath.parse` / `parsefile` / `sniff_format` + `OpenMath.xml` / `write_xml`.
- [x] `om"…"` / `omxml"…"` string macros, decoded at macro-expansion time.
- [~] `ext/OpenMathEzXMLExt.jl` — **withdrawn**, not deferred. An `EzXML.Document`
      has already been parsed, so a reader starting from one cannot make the
      guarantee decision **D1** rests on — that an undeclared entity reference is
      an error. It would have been a second entry point with quietly weaker
      guarantees, reachable by loading an unrelated package, in exchange for one
      `string(doc)` call. See `docs/src/design/xml-backend.md`.
- [x] Harness: the conformance corpus and its driver — 60 items, six checks each,
      with the encodings an item lacks derived from the ones it carries.
- [x] **P8** over every corpus document and every truncation of it.
- [x] Property layer on `Supposition.jl` — **P1**, **P2**, **P5**, **P6**, **P7**,
      **P8**, plus writer stability and a generator vacuity check.
- [x] **P3** (cross-encoding agreement) — live since the JSON encoding landed.
- [x] Mutation fuzzing, live since Phase 4 rather than waiting on Phase 8: seeds
      derived from every corpus item in all four encodings, eight mutation kinds.
      Last run 1 991 402 inputs in three minutes with no escape from the
      `OpenMathError` family.
- [x] First **differential** run against the Rust oracle, XML only. 27 of 39 valid
      corpus items agree; the other 12 are five upstream limitations, filed in
      `upstream-bugs.md` against crate v0.1.7 / commit `06d2797`, each checked
      against Python's expat before being written down.
- [x] Benchmarks: measured against `XML.jl` v0.4.6 rather than `MathML.jl`, which
      is the comparison that actually bore on decision D1. 200 KiB document:
      `XML.jl` 2.45 ms to a generic tree, we take 13.9 ms to a validated object.
      Recorded in `docs/src/design/xml-backend.md`, including that it goes against
      us.
- [ ] A standing benchmark suite in CI (AirspeedVelocity), as opposed to the
      one-off measurement above.

**Exit criteria** — 100 % of non-skipped corpus items round-trip through XML; oracle
disagreements = 0 (or each documented); nightly fuzz finds no crash/hang in 30 min;
coverage ≥ 95 % on `src/xml/`.

**Status 2026-09-17** — the corpus round-trips (820 conformance assertions, 60
items), the property layer holds (22 properties), and the differential oracle
agrees on every document the reference implementation can read. Outstanding: the
benchmark suite and the `om"…"` macro. (The `EzXML` extension was later
withdrawn; see Phase 2.)

---

## Phase 3 — JSON encoding `v0.3.0`

- [x] Resolve decision **D3**. Settled in favour of a purpose-built scanner and
      **no dependency at all**: `integer` is a JSON number and OpenMath integers
      are unbounded, so a general parser destroys the value before we see it.
      Recorded in `docs/src/design/json-backend.md`.
- [x] `src/json/scanner.jl` — numbers keep their source text until the reader
      knows which field they belong to.
- [x] `src/json/reader.jl` — all shapes of §4.2, tolerant of field order, `"bytes"` and
      `"base64"` for `OMB`, `"integer"` and `"decimal"` for `OMI`.
- [x] `src/json/writer.jl` — explicit work stack, no intermediate `Dict`; the
      `integer`/`decimal` precision rule and the `hexadecimal` spelling of NaN and
      the infinities are blocking conformance cases.
- [x] `OpenMath.json`, `write_json`, `MIME"application/openmath+json"` `show`.
- [x] `omjson"…"` string macro, decoded at macro-expansion time.
- [x] `format=:auto` sniffing (§3.3).
- [x] Harness: JSON enabled in the conformance driver; **all 39 XML items gained
      JSON coverage with no new files**, which is the derivation promise of §6.2
      paying off, and 14 JSON-only items from the standard exercise the reverse
      direction. **P3** now cross-checks XML ↔ JSON on generated objects.
- [x] Cross-checked byte for byte against the reference implementation on seven
      items covering every composite kind — a confirmation, not a dependency.

**Exit criteria** — full three-way agreement XML ↔ JSON ↔ expected on the whole corpus;
oracle byte-identical after canonicalization; coverage ≥ 95 % on `src/json/`.

**Status 2026-09-17** — met, apart from the `omjson"…"` macro (a **Could**).

---

## Phase 4 — Binary encoding and structure sharing `v0.4.0`

This is the phase where `OpenMath.jl` overtakes the Rust reference implementation —
both items are declared TODO upstream.

> **This is the one phase where the harness cannot tell us we are right.**
>
> XML had Python's expat as an independent parser and the reference crate as an
> oracle. JSON had the standard's own worked examples and a byte-identical
> cross-check against the reference. Binary has neither *in place*: the reference
> crate lists "binary format" under TODO.
>
> **Correction, after the fact:** an earlier draft of this warning said no second
> implementation existed anywhere. That was wrong. GAP's `openmath` package writes
> and reads this encoding (`OpenMathBinaryWriter`, `OMGetObject` with
> autodetection, `OMTestBinary`), and it is what SCSCP deployments talk to. It is
> an oracle we have not yet used — see Phase 4b.
>
> Round-trip, idempotence and cross-encoding agreement are all satisfied
> *trivially* by a writer and reader that share the same misunderstanding. We
> could ship a codec that interoperates with nobody and every gate would report
> green — the exact failure mode the harness exists to prevent.
>
> The mitigation, before a byte of codec is written:
>
> 1. Work from the standard's own text in `refs/omstd20/`, not from a summary.
>    The web fetcher cannot reproduce §3.2 verbatim, and the section is too
>    intricate to paraphrase — note that the standard's *own* worked float
>    example was wrong and was corrected by errata.
> 2. Transcribe every explicit byte sequence the standard gives into
>    `test/corpus/binary-vectors.toml` **first**. There are about eight, they are
>    independent ground truth, and they were the only external check available
>    at the time this was written.
> 3. Only then write the reader and the writer, against those vectors.

- [x] `src/binary/tokens.jl` — the OM2 token table (§3.2.2), kind bits plus long-form,
      shared and attributed flags.
- [x] `src/binary/reader.jl` — streaming over `IO`, no full buffering; OM2 references
      (§3.2.4); the deprecated OM1 sharing form accepted on **read only**; streamed
      packets read and never written.
- [x] `src/binary/writer.jl` — variable-length `OMI`, length-prefixed strings/bytes.
- [x] `OpenMath.binary`, `format=:binary`, binary sniffing in `:auto`, and
      `OpenMath.parse` over bytes as well as text.
- [x] Harness: binary enabled; the corpus's XML/JSON/MathML items gained `.bin`
      coverage with no edit (principle 2), taking the suite from 6462 assertions to
      6942. Property **P4** is blocking, and **P4b** — the reader is total over
      arbitrary bytes, truncations and single-byte flips — with it.
- [x] Fuzzing gained a binary campaign: binary seeds derived from every corpus item,
      a `[16]` nesting bomb and a long-flag length mutation. 1 991 402 inputs in
      3 minutes, no escapes.
- [x] Decision **D7** — the standard contradicts itself about the sharing flag;
      `docs/src/design/binary-backend.md` records which reading we follow and why,
      and `upstream-bugs.md` records the four defects found in §3.2 itself.
- [ ] `share_structure` — the inverse of `expand_references`, finding repeated
      subtrees and introducing `id`/`OMR`. The binary writer honours sharing that is
      already in the object; nothing yet *creates* it.

**Exit criteria** — met, except `share_structure`: four encodings agree on 100 % of
the corpus; `standard/omr-sharing` survives a round-trip through binary and back, and
the shared form is byte-identical to the standard's Figure 3.6 with its one defect
corrected; binary fuzz clean.

> **What the harness actually caught, recorded because this is the phase the
> warning was about.** The standard's byte vectors, transcribed first, found the
> two broken figures before any code existed. Unit tests found six defects. The
> property layer found **three** more — all `cdbase`, all needing a base on the
> document *and* on the root object to appear, none reachable by an example test
> anyone would think to write. Fuzzing found none. The differential oracle was
> unavailable, exactly as predicted.

---

## Phase 4b — the binary oracle we did not know we had

Found while checking a claim rather than while writing code: **GAP's `openmath`
package implements this encoding**, and is maintained. That makes D7 — which
reading of the contradictory §3.2 is right — an experiment rather than an
argument.

- [x] `just gap-vectors` — download the binary streams GAP's package ships in its
      `tst/` directory. Data, not source: no GPL code is read or linked, and it
      lands in gitignored `refs/`. **`read_binary` decoded all ten documents of
      `test3.bin` first try**, and each round-trips and agrees with XML and JSON.
- [x] Learned from those bytes: **GAP writes `[24]`, never `[24+64]`.** So no
      shipping implementation exercises the §3.2.4.2 mechanism D7 is about — and
      our own output, which is always `[24+64]`, may not be readable by GAP.
- [x] **Decision D8** — the document tag is `[24]` unless `[24+64]` buys something
      (structure sharing, or a version other than 2.0). Not a preference in the
      end: GAP *rejects* `[24+64]` outright, so our previous output was
      unreadable by the only other implementation.
- [x] `just oracle-gap-setup` — GAP 4.15.1 and `openmath` 11.5.5 into gitignored
      `refs/`, via conda rather than a system package so that
      `just oracle-gap-clean` really removes it. GPL run as a subprocess, never
      linked, no source read.
- [x] **Decision D9** — big integers are written base 16, not base 256. GAP
      mis-decodes base 256 whenever a digit byte falls below 0x10, returning a
      silently smaller number.
- [x] `just oracle-gap` — both directions, over values GAP itself names. Letting
      GAP choose them is the point: it is a CAS, so handed `arith1#plus(1, x)` it
      tries to *evaluate* it and fails on the unbound variable, and a naive
      corpus-through-GAP oracle would measure its phrasebook rather than its
      codec.

      ```
      we write → GAP reads   34/34 agree
      GAP writes → we read   26/30 agree, 4 blocked by an upstream defect
      ```
- [x] Settle D7 against what GAP emits — **it cannot be settled that way**. GAP
      neither writes nor reads `[24+64]`, so the disputed layout is exercised by
      nothing in the field. That is itself the answer to how the contradictions in
      §3.2 survived twenty years: the part that disagrees with itself is the part
      nobody runs.
- [x] Three upstream defects recorded in `upstream-bugs.md`; two filed as
      gap-packages/openmath [#31](https://github.com/gap-packages/openmath/issues/31)
      and [#32](https://github.com/gap-packages/openmath/issues/32). The third,
      `[24+64]` rejected, was deliberately not filed: a missing feature nothing in
      the field uses, and filing it would have diluted two reports that have
      reproducers and probable one-line fixes.
- [x] Outcome recorded in `docs/src/design/binary-backend.md` (D8, D9, and what
      the oracle reports). The \§3.2 defects went upstream as
      [OpenMath/OMSTD#72](https://github.com/OpenMath/OMSTD/issues/72), including
      one item the audit turned up late: the standard's only base-256 worked
      example has no digit byte below 0x10, so it cannot fail for the
      implementation error GAP actually has.
- [x] **E2** written up in `specs/harness/experiments.md`. E1 recorded the oracle
      layer at zero defects and hedged it as "a property of *this* oracle"; E2
      shows the hedge was the whole story. An oracle's yield tracks coverage
      overlap, and the Rust crate's blind spots were listed in its own README all
      along. New harness step **H2.5**: before implementing an encoding, enumerate
      who else implements it.

**Why this is its own phase.** The E1 audit measured the differential oracle as
finding *zero* defects in the XML and JSON phases, and the conclusion drawn was
that its blind spots were the problem. This is a different failure: an oracle that
existed and was never looked for. Worth a phase so the lesson is not filed under
"binary encoding".

---

## Phase 5 — Content Dictionaries `v0.5.0`

- [x] `src/cd/parser.jl` — the CD XML format and the STS signature format, both
      built on our own tokenizer, with the embedded `<OMOBJ>` documents handed to
      `read_xml` so they get the same limits and the same errors as any other.
- [x] `src/cd/registry.jl` — `CDRegistry`, `(cdbase, cd)` resolution, `lookup`,
      `describe`, `signature`, `arity` and `validate_against_cds`. No offline
      bundle and no fetch-with-cache: decision **D4** below settled that the
      dictionaries are downloaded on demand by `just corpus-fetch` into gitignored
      `refs/`, so the registry starts empty and says so rather than reaching the
      network on its own.
- [x] Resolve decision **D4** — **neither**. The dictionaries are downloaded on
      demand into gitignored `refs/`, not shipped. Size was never the deciding
      factor: the whole official set is 564 kB. The licence is. It permits
      redistributing a dictionary verbatim, but extracted or reorganised content
      is a derived work, and the derived-work clause asks for a prominent
      reference to the original and a prominent statement that it is not the
      original — more than a bundled asset or a test fixture should carry.
      Downloading is not redistribution, so nothing is lost.
- [x] `lookup`, `signature`, `describe`, `arity`, `validate_against_cds`.
- [ ] Official error CDs (`error1`) wired into `:recover` mode (§5.3) — another
      upstream TODO closed.
- [ ] Harness: a CD-driven test item asserting every bundled CD parses, every symbol
      resolves, and every embedded example validates against its own signature.

**Exit criteria** — all official CDs parse; `validate_against_cds` is clean on the
entire `corpus/cd/`; arity/signature violations are detected on hand-built negatives.

---

## Phase 6 — Symbolics.jl phrasebook `v0.6.0`

- [x] **H2.5 first**: the oracle survey, in `docs/src/design/phrasebook.md`,
      written before any code. It ranked MathML.jl primary (same target language,
      same vocabulary), GAP secondary (base types only), and ruled out four
      others with reasons. It also paid for itself immediately: MathML.jl pins
      `Symbolics = "7.39.2"` *exactly*, so it goes behind an opt-in target under
      `refs/` rather than into `test/Project.toml`, and the `Symbolics` support
      ships as an extension — half of decision **D5**, settled by the survey.
- [x] `src/phrasebook/core.jl` — `Phrasebook`, forward/backward maps keyed on
      `(cdbase, cd, name)`, `with_phrasebook` scoped default, `interpret` and
      `express`. `from_openmath` now routes symbols and applications through the
      phrasebook in force, so the vocabulary is replaceable without a keyword
      argument threaded through every caller.
- [x] `src/phrasebook/base.jl` — 87 symbols across `arith1`, `transc1`,
      `relation1`, `logic1`, `nums1`, `fns1`, `integer1`, `rounding1`, `minmax1`,
      `complex1`, `linalg2`, `list1`, `set1` and `s_data1`.
- [x] `ext/OpenMathSymbolicsExt.jl` — `Num ↔ OMNode`, `Equation ↔ relation1#eq`,
      `Differential ↔ calculus1#diff` over an `fns1#lambda`. Built **structurally**;
      no `eval`, no `include_string`, on parsed content (§5.4).
- [x] Decision **D5** — an extension, not a companion package. The survey found
      that the pinning churn is `MathML.jl`'s, not `Symbolics`', and a weak
      dependency inherits no pin.
- [x] `piece1#piecewise` ↔ `ifelse`, with `piece1#piece` and `piece1#otherwise`.
      A piecewise with no `otherwise` is refused, because `ifelse` is total and
      inventing a default would be a silent change of meaning. An equality used
      as a *condition* is also refused: `relation1#eq` becomes a Symbolics
      `Equation`, which `ifelse` cannot take, and Symbolics has no symbolic
      equality predicate — a genuine gap between the two languages, named rather
      than papered over.
- [x] `just oracle-mathml` — 21 hand-written pairs, the same object as non-strict
      Content MathML for MathML.jl and as OpenMath for us, compared as Symbolics
      expressions. **19/21 agree**; see **E4**.
- [x] Harness: **P9**, over generated symbolic expressions. It found two defects
      the sixteen hand-written cases did not: `transc1#sin` applied to `OMI(-8)`
      was being *evaluated* to −0.9893…, fixed by `define_leaf!`; and a unary
      `arith1#times` — a Symbolics representation artefact — was reaching the
      output, now collapsed by the writer.

      The property is **idempotence, not identity**, and that is a fact about
      Symbolics rather than a weakening: it keeps several representations of one
      object and `isequal` is structural, so the first round trip may land on a
      different representative and every one after is a fixed point.

**Exit criteria** — the coverage of `MathML.jl`'s `applymap` is matched or exceeded,
symbol by symbol, with a table in the docs showing the correspondence.

**Status**: **76 of its 85 element names covered, which is all that denote a
symbol.** The other nine are structure — `apply`, `bvar`, `ci`, `cn` and `math`
are MathML syntax, and `degree`, `diff`, `lambda` and `piecewise` need the
symbolic layer. The correspondence is asserted element by element in
`test/unit/phrasebook.jl`, transcribed rather than computed, so it fails if the
vocabulary shrinks. An exit criterion that is not executable is a wish.

---

## Phase 7 — Strict Content MathML `v0.7.0`

Corrected scope, 2026-09-17. The standard endorses **four** encodings, not three:
"two encodings in XML (an innate one described here, and one in Strict Content
MathML), a binary format and a JSON encoding". Strict Content MathML is therefore
an *encoding*, on the same footing as the other three — not a phrasebook, which is
where an earlier draft of this roadmap put it.

Two consequences. It needs **no dependency**: it is XML, and we own an XML
tokenizer. And the conformance driver derives it like any other encoding, so every
corpus item covers it the day it lands, exactly as happened when JSON arrived.

- [x] `src/mathml/reader.jl` and `writer.jl` — the §4.5 mapping table, reusing the
      existing tokenizer and writer machinery, with no new dependency.
- [x] `application/mathml+xml` MIME rendering.
- [x] Reject non-strict Content MathML rather than guess (REQ-MML-004): operator
      elements, untyped `<cn>`, non-strict `cn` types and presentation markup are
      all refused with a message naming why.
- [ ] Normalise non-strict Content MathML into the strict subset, following
      **MathML 4 Appendix F**, which defines the transformation normatively. An
      earlier draft delegated this to `MathML.jl`; checking that package showed it
      contains no `csymbol`, `semantics`, `cbytes` or `cerror` and targets
      `Symbolics` expressions, so it reads the dialect we reject rather than
      offering a route into the one we read. The two are complementary.
- [ ] `ext/OpenMathMathMLExt.jl` — an optional bridge between `MathML.jl`'s
      `Symbolics` output and OpenMath, for callers who already hold non-strict
      Content MathML from SBML or the SciML stack. That is the `Symbolics`
      phrasebook wearing a MathML hat, so it waits on Phase 6.
- [ ] Documented, explicit list of what does **not** round-trip; silent loss is
      worse than an error.

**Status 2026-09-17** — done, apart from the `MathML.jl` normalisation extension.
Enabling it in the conformance driver took the suite from 6070 assertions to 6462
with no new corpus files, the second time §6.2's derivation promise has paid off.

**Exit criteria** — every corpus item round-trips through Strict Content MathML
alongside XML and JSON; the non-round-trippable list is exhaustive and each entry
has a test proving the error is raised rather than data lost.

---

## Phase 7b — Popcorn notation `v0.7.x`, a **Could**

Popcorn is a compact linear syntax for OpenMath — `arith1.plus(1, $x)` where the
XML takes five elements. It appears **nowhere in the standard**: it is an external
convention, which is why every requirement in `REQ-POP-*` is a Could and why it is
explicitly *not* an interchange format (REQ-POP-004 is a Won't).

Its value is ergonomic, and it is large: it would replace
`OMA(OMS(arith1#plus), OMI(1), OMV(x))` as the `text/plain` rendering, which is
what anyone in the REPL actually reads. A printer alone is most of the benefit and
is cheap; the parser is the optional half.

- [ ] `src/popcorn/printer.jl` — precedence and bracketing for the common CDs.
- [ ] `src/popcorn/parser.jl` — the reverse, with the same explicit-stack and
      error-offset discipline as the other readers.
- [ ] Switch `show(io, ::MIME"text/plain", ::OMNode)` over once the printer exists.

---

## Presentation MathML — explicitly not an encoding

Rendering an OpenMath object as Presentation MathML stays a **non-goal** (spec
§1.5), and the standard's own position supports that: Presentation MathML appears
in omstd20 only as an *example of foreign content* attached to an object —

> "…representation in Presentation MathML is: `<OMATTR><OMATP>`…"

— that is, the standard's model is that you **attach** a presentation form as an
`OMFOREIGN` annotation, not that a library generates one. That mechanism already
works here: `OMATTR` with an `OMFOREIGN` value round-trips losslessly in both
encodings, and `corpus/standard/omattr-foreign-value` covers it.

Generating notation is a different discipline: it needs per-symbol precedence,
bracketing and infix/prefix rules — the OMDoc *notation definition* problem — and
it is unbounded, because every Content Dictionary needs its own. A minimal
renderer for the handful of common CDs, good enough for a Pluto or IJulia
notebook, would be a defensible **Could** later; a general one is a separate
project.

---

## Phase 8 — Performance, latency, hardening `v0.8.0`

- [x] **Measure first.** `just bench` records throughput, allocations per node and
      time to first parse; `just bench --save` writes `test/harness/baseline.toml`.
      Phase 8's exit criterion says "no regression ≥ 10 % vs. the Phase 4
      baseline" and there was no baseline — the number lived in this file and
      nowhere else.
- [x] `PrecompileTools.jl` workload in `src/precompile.jl`. The measurement is
      what justified the dependency, and it decomposed the problem: bare Julia
      0.121 s, `using OpenMath` 0.147 s — loading cost 26 ms — and the first
      `parse` **4.132 s**. All of it first-call compilation, paid by every
      process. Now **0.32 s**, on all four encodings.
- [x] **E6** — `just verify-lts` and `just verify-all`. "The single source of
      truth" covered Julia 1.13 and not the 1.10 LTS that `REQ-PRJ-001` names
      equally, and the first CI run found three defects that every local run had
      passed. Julia 1.10 was installed on this machine the whole time.
- [ ] `SnoopCompile` invalidation audit; `Invalidations.yml` gate.
- [x] Allocation-per-node benchmark, and the two defects it found in the JSON
      reader. `_scan_string!` allocated an `IOBuffer` for every string including
      the majority with no escape (−22 %); and error paths were built eagerly,
      `path * "/applicant"` at every node, 4.6 MB of the 4.7 MB a 1601-node
      document spent (−24 % more). Reading JSON went from twice XML's cost to
      parity: 38 → 22.3 allocations per node, 2.40 → 1.20 ms.

      The second is the same defect the XML reader had in Phase 2, where it
      caused an out-of-memory at 200 000 levels. **Neither the fix nor the test
      was propagated**, which is why it survived two more phases.
- [x] **`_build_json` runs on an explicit stack.** It was the last recursive
      traversal in the package and overflowed at about 20 000 levels; a
      200 000-level JSON document now parses, as it always did in XML, MathML and
      binary. The stop-gap `json_builder_depth` ceiling is removed, since keeping
      it would limit JSON below the other three for no reason. `docs/src/security.md`
      claimed "every traversal uses an explicit stack" throughout — the claim is
      true again rather than aspirational.
- [ ] Zero-copy path: `SubString{String}` over memory-mapped input, the Julia analogue
      of the Rust crate's `Cow::Borrowed`.
- [ ] `AirspeedVelocity.jl` regression comments on PRs; a documented performance budget.
- [ ] Extended fuzz campaign (24 h) across all three encodings before the freeze.
- [x] **E5** — `test/unit/cross_encoding.jl`, a home for properties every encoding
      must share. Two defects survived this session in the same blind spot: the
      conformance driver checks the encodings *agree about objects*, never that
      they share *implementation* properties, and both readers produce the same
      object right up to where one stops producing anything.
- [ ] Security review pass against `SECURITY.md`'s threat model; document the default
      limits and how to tune them.

**Exit criteria** — no performance regression ≥ 10 % vs. the Phase 4 baseline; TTFX
under budget on 1.10 and 1.13; 24 h fuzz clean.

---

## Phase 9 — API stabilisation `v0.9.0`

- [ ] Public API settled; everything not exported is explicitly documented as
      internal. Not a freeze — `0.x` reserves the right to change a minor.
- [ ] `docs/src/compat.md` stating the versioning contract: what may change in a
      patch and in a minor while the series is `0.x`, and what would have to be
      true before a `1.0.0` is worth declaring.
- [ ] Doctests on every exported symbol; `checkdocs = :exports` blocking.
- [ ] `CHANGELOG.md` complete from `0.0.1`.
- [ ] Registration in the General registry under MIT (decision **D6**).
- [ ] Announce on JuliaLang Discourse; notify the OpenMath Society and the `openmath`
      crate author — a Julia implementation with binary + `OMR` support is worth
      cross-linking from openmath.org's implementation list.

**Exit criteria** — registered, docs published with the live conformance report, CI
green on Julia 1.10 and 1.13 across all three operating systems. A `1.0.0` is
considered only once the API has held still across several releases.

---

## A note on binary transports

The standard defines exactly one binary encoding (§3.2), and it is nothing like a
modern schema format. The tag byte packs a five-bit token identifier, a streaming
status bit, a sharing flag and a long flag; integers carry a sign/base byte
selecting base 10, 16 or **256**; strings and names are length-prefixed on one or
four bytes depending on the long flag; and a basic object may be split across
packets that each repeat a variant of its identifier. It is closer to ASN.1 BER
than to Protocol Buffers or Cap'n Proto — a self-describing token stream with no
schema, designed in an era when streaming a bignum in 255-byte chunks was a
requirement.

**Protocol Buffers or Cap'n Proto are not alternatives to §3.2**, because
substituting one would produce a format no other OpenMath implementation can
read, and interoperability is the entire point of the standard. §3.2 therefore
stays a **Must** (REQ-BIN-001/002).

They are, however, a good answer to a *different* question, and that question is
**RPC**. [SCSCP](https://openmath.org/documents/scscp/) — the Symbolic
Computation Software Composability Protocol — wraps OpenMath objects in a
request/response envelope: procedure names, call identifiers, an error channel,
interrupt and status messages. That envelope is fixed-field, schema-shaped data,
which is exactly what Cap'n Proto is good at and exactly what a self-describing
token stream is bad at. The clean layering is:

| Layer | Format | Why |
|---|---|---|
| Mathematical payload | OpenMath XML / JSON / §3.2 binary | Interoperability with every other OpenMath implementation |
| RPC envelope and framing | Cap'n Proto | Schema-shaped, and its RPC layer gives promise pipelining, which matters when a client chains CAS operations |
| Large `OMB` bytearrays | Cap'n Proto zero-copy | The one place in the object model where zero-copy genuinely pays |

Cap'n Proto's headline win applies only weakly to an OpenMath *object*: the model
is a recursive tree of unbounded integers and arbitrary-length strings, which is
variable-length data either way, and it must be validated before use, so nothing
is saved by not copying it. The envelope is where the win is real.

[`Capnp.jl`](https://github.com/s-celles/Capnp.jl) is the natural building block
for that work. It belongs in a downstream `SCSCP.jl` rather than here:
`OpenMath.jl` is that package's layer 0, and adding an RPC transport to a
serialisation library would make every user of the object model pay for a
dependency they do not need.

---

## Deferred / out of scope for the 0.x series

| Item | Why deferred | Where it would go |
|---|---|---|
| SCSCP protocol | Separate concern, needs sockets and a session model | `SCSCP.jl`, depends on `OpenMath.jl`; see the note above on Cap'n Proto as its transport |
| OMDoc / MMT documents | Document-level, not object-level | `OMDoc.jl` |
| LaTeX / Presentation MathML rendering | Presentation, not semantics | extension, post-1.0 |
| OpenMath 1.x write support | Deprecated by the standard | never |
| CAS evaluation of OpenMath objects | Explicit non-goal (§1.5) | downstream |

---

## Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Inadvertent copying from the GPL-3 reference crate into our MIT codebase | **High** | Clean-room discipline is a hard rule (§1.3); `refs/rust-openmath/` is consulted for architecture only; `just clean-room` greps for shared verbatim runs; the oracle is a subprocess, never a dependency |
| `XML.jl` performance below `EzXML` | Medium | Decision **D1** deferred to Phase 2 and settled on benchmark data; the backend is isolated behind `src/xml/` |
| A JSON dependency drops the 1.10 LTS | Medium | Dependency confined to one file; `JSON3.jl` is the drop-in fallback (D3) |
| `Symbolics.jl` compat churn breaks CI | Medium | Extension, not a hard dep; escape hatch is the companion package (D5) |
| Binary encoding under-specified in practice (few implementations to compare against) | Medium | Standard §3.2 is normative and complete; property-based round-trip is the primary oracle, since no external oracle exists |
| Rust oracle unavailable / breaking changes | Low | Oracle is CI-only and non-blocking for local development; pin the crate version in `oracle/Cargo.lock` |
