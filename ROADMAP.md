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
- [x] A "Conformance" page generated from the harness's machine-readable report
      (§6.1 `harness/report.jl`), so the published docs always show live coverage of
      the corpus per encoding. **Done 2026-09-18.**

      `test/harness/report.jl` calls the *same* `Corpus.check` the conformance
      suite calls, rather than deriving a second verdict — a report that could
      disagree with the suite would be two opinions, which is none. It emits
      JSON (`just conformance-report` → gitignored `refs/conformance.json`) and
      renders `docs/src/conformance.md` from it.

      The page is committed, which means it can go stale, and a stale conformance
      page is worse than none: it states measured coverage that was not measured.
      So a gate regenerates and compares, the same shape as the `MANIFEST.sha256`
      gate — and, unlike that one, it was **proved to fire** before being trusted,
      by making the page stale on purpose. Doing so found the gate's own
      diagnostic indexing a `String` at arbitrary integers, so the first stale
      page was reported as an exception rather than a failure: the page contains
      `✅` and `—`.

      The report covers the in-repository corpus only. The 342 harvested Content
      Dictionary vectors live in gitignored `refs/`, so including them would make
      the published page depend on whether the reader had run `just
      corpus-fetch`. It reports what a clean checkout can verify, and says so.

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
- [x] A standing benchmark suite in CI (AirspeedVelocity), as opposed to the
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
- [x] `share_structure` — the inverse of `expand_references`, finding repeated
      subtrees and introducing `id`/`OMR`. **Done 2026-09-19.** Keeping the *first*
      occurrence as the definition is what makes a forward reference impossible,
      which §3.2.5 forbids outright; a leaf is never shared, because an `OMR`
      costs more than the leaf in every encoding. On an expression holding one
      subterm four times: XML 44 %, JSON 49 %, binary 53 % smaller.

      Two cases the unit tests were written for and the implementation got wrong
      first. An `id` an existing `OMR` names cannot be dropped — the definition
      adopts it instead — and where two occurrences carry *different* live
      anchors the subtree is left alone, because only one could survive.

      **P10 was vacuous before it was useful.** On `gen_node`, 30 of 400 objects
      had anything to share, so nine tenths of the budget asserted that sharing
      an object with nothing to share returns it unchanged. `gen_shared` plants
      repetition, and the non-vacuity floor is now asserted in the test rather
      than hoped for.

**Exit criteria** — met: four encodings agree on 100 % of
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
- [x] Error CDs wired into `:recover` mode (§5.3). **Done 2026-09-19.** `:recover`
      was accepted as a mode name and behaved exactly like `:strict`: it threw.
      Now it never raises — an unreadable subtree becomes an error object in its
      own position and the structure around it survives — in all three text
      readers, because honouring `mode` in one of three is worse than in none.

      **The specification named a dictionary that does not exist.** §5.3 asks for
      `error1#unexpected_symbol`; the official CD is called `error`, not `error1`,
      and its three symbols — `unhandled_symbol`, `unexpected_symbol`,
      `unsupported_CD` — are *all* about a symbol, one absent from a dictionary,
      one unimplemented, one whose dictionary is missing. None describes a
      malformed integer, and writing one there would state something false in a
      vocabulary other implementations read. `moreerrors#encodingError` says
      exactly the right thing at the cost of being experimental rather than
      official: a true statement in an experimental vocabulary beats a false one
      in an official vocabulary.

      A resource limit still raises, deliberately. `:recover` is for documents
      that are broken, not for documents that are attacking you.
- [x] Harness: a CD-driven test item asserting every bundled CD parses, every symbol
      resolves, and every embedded example validates against its own signature.
      **Done 2026-09-19**, over all 1114 embedded `<CMP>`, `<FMP>` and `<Example>`
      objects in every directory, not just Official.

      It found **our** defect first: `sts_arity` recognised `sts#nassoc` as
      unbounded and not `sts#nary`, though the `sts` dictionary defines both as
      "an arbitrary number of copies of the argument". Every n-ary symbol in the
      official set carried the arity of its own wrapper — `list1#list` accepted
      exactly one element — and no hand-written test had ever covered an `nary`
      signature, though `list1`, `set1`, `linalg2` and `s_data1` are nothing but.

      Then it found that **the official set is not self-consistent**: 96 issues
      across four classes, tabulated in `upstream-bugs.md` — symbols cited that
      no dictionary defines (`relation1#le`, `calculus1#defintint`), examples
      contradicting their own STS signature, `s_data1#moment` with `sts#nary` in
      the *return* position, and one FMP with a dangling `OMR`. Two further
      classes are not faults and are named so the exception list is not mistaken
      for one: `error#unexpected_symbol` cites a non-existent symbol *on purpose*,
      and `scscp_transient_1` is defined at run time. Pinned by class, so a new
      kind fails and a fixed dictionary shows up as an expectation that stopped
      firing.

**Exit criteria** — met. All official CDs parse; `validate_against_cds` runs over
all 1114 embedded objects with every remaining issue accounted for by class; and
arity/signature violations are detected on hand-built negatives *and* on the
dictionaries' own examples.

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
- [x] Normalise non-strict Content MathML into the strict subset, following
      **MathML 4 Appendix F**, which defines the transformation normatively. An
      earlier draft delegated this to `MathML.jl`; checking that package showed it
      contains no `csymbol`, `semantics`, `cbytes` or `cerror` and targets
      `Symbolics` expressions, so it reads the dialect we reject rather than
      offering a route into the one we read. The two are complementary.
- [x] ~~`ext/OpenMathMathMLExt.jl` — an optional bridge between `MathML.jl`'s
      `Symbolics` output and OpenMath.~~ **Withdrawn 2026-09-18**, on evidence,
      after the H2.5 survey below. It would contain no code, and the route it
      wraps is lossier than the one Appendix F now gives.
- [x] `docs/src/round-trip.md` — the explicit list of what does **not** round-trip,
      in one place rather than scattered across six design notes. The three text
      encodings lose nothing; the binary encoding loses exactly four things, each
      a consequence of what §3.2 has no field for. The table is **asserted** in
      `test/unit/cross_encoding.jl`, so a new loss fails, and so does a loss that
      is quietly fixed without the page being updated.

**Status 2026-09-17** — done, apart from the `MathML.jl` normalisation extension.
Enabling it in the conformance driver took the suite from 6070 assertions to 6462
with no new corpus files, the second time §6.2's derivation promise has paid off.

**Status 2026-09-18** — Appendix F lands as `src/mathml/appendix_f.jl`, reached by
`strict = false`. The token, operator, constant and container rules (F.4.3, F.4.4,
F.7.1, F.8, F.8.1, F.9.1) are implemented; the qualifier and `domainofapplication`
machinery (F.2, F.3, F.5, F.6) is refused **naming its section**, because a
qualifier changes the meaning of the operator it qualifies and a wrong integral is
silent. `docs/src/design/mathml-appendix-f.md` is the table of both halves.

Two things were found rather than written. The oracle was upgraded so the *same
non-strict document* goes to both implementations — MathML.jl directly, and
Appendix F → OpenMath → Symbolics for us — and that path immediately caught
`<root/>` with no `<degree>` producing a one-argument `arith1#root`. The 21
hand-written pairs did **not** catch it, because writing the pair by hand means
supplying the answer the transformation was failing to produce. A differential
check is only as strong as the input both sides are made to share, which is E3 and
E7 in a third place. And the new gate asserting that every symbol this
transformation can emit is one `base_vocabulary` knows failed on six: a document
could transform perfectly and then be refused by the phrasebook.

Surveying `MathML.jl` for the extension below then found three more of ours, all
the same shape as `root`. `<log/>` with no `<logbase>` is base 10 (MathML 4 §4.3)
and `transc1#log` takes the base first — the CD's own FMP reads `log(a, c) = b`
when `a^b = c` — so we were emitting a one-argument `transc1#log`. The five
container elements were in the §F.8 table and reachable only in *applicant*
position, so `<set>1 2</set>` fell through to "unhandled element". And several
refusals of real Content MathML said it was "not Content MathML at all", which is
worse than a generic message because it tells a reader to stop looking for
the rule.

### Why the `MathML.jl` extension was withdrawn

H2.5 again: survey before implementing. Appendix F changed the premise the
extension was planned under — we now read the non-strict dialect ourselves — so
the question is what routing through `MathML.jl` (v0.1.24) still buys.

Comparing the two element tables: `MathML.jl` reads **two** names we do not.
`prod` is not a MathML element and raises `KeyError` there anyway, so the real
delta is **one**: `<diff>`, which is F.2.1 and which `MathML.jl` implements with
its author's own `# won't work for all cases` against `bvar` and `degree`.

And the bridge needs no code from us. This already works, with nothing but what
the package ships:

```julia
to_openmath(only(MathML.parse_str(source)))   # → OMA(OMS(calculus1#diff), …)
```

because the `Symbolics` extension supplies `to_openmath(::Num)`. An extension
would add a name and no capability.

The route is also **lossier** than ours. `MathML.jl` reads every untyped `<cn>`
as a `Float64`, so `<apply><plus/><ci>x</ci><cn>2</cn></apply>` becomes
`arith1#plus(OMF(2.0), OMV(x))` — the integer and the argument order both gone —
where Appendix F gives `arith1#plus(OMV(x), OMI(2))`, F.9.1 being explicit that
an untyped `<cn>` whose lexical form is an integer *is* an integer.

So: no extension. If derivatives matter, the honest successor is **F.2.1 itself**,
which is now the only reason left to want one.

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
- [x] `SnoopCompile` invalidation audit; `Invalidations.yml` gate. **Done
      2026-09-19.** Loading OpenMath invalidates **9** method instances, and
      **none** of them is caused by a method this package inserts: the single
      tree is `Dates` superseding `Base.TOML.Printer.is_valid_toml_value(::Any)`,
      reached by `OpenMath → PrecompileTools → Preferences → TOML → Dates`.

      The audit reports *whose*, not just how many, because a count alone is not
      actionable — an invalidation from a method we insert is a signature too
      wide or a piracy and is ours to narrow, one from two stdlibs meeting is
      not, and reporting them together would make the gate noise. Recorded in
      `test/harness/baseline.toml`, so a rise fails; opt-in via
      `just invalidations-setup`, like the oracles, because `SnoopCompile` is a
      large dependency and this package has one on purpose.

      `Invalidations.yml` existed and **printed two numbers**, leaving the
      comparing to whoever read the log — which is the same as not comparing
      them, since nobody reads a green job. It now fails on a rise. That is the
      fifth gate in this project found green because it was asleep.

      It also completes a measurement already in the documentation: time to
      first parse justified adding `PrecompileTools` by what it bought, 4.132 s
      to 0.32 s. This is what it cost — nine invalidations, from the `TOML`/`Dates`
      pair it drags in. Both numbers now exist.
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
- [x] ~~Zero-copy path: `SubString{String}` over memory-mapped input, the Julia
      analogue of the Rust crate's `Cow::Borrowed`.~~ **Withdrawn as specified,
      2026-09-19, and redirected — on measurement.**

      Both halves were measured before being built, and neither survives.

      *`SubString` in the object model.* In the case built to favour it most —
      200 strings of 200 characters — the copied payload is **9 %** of what the
      reader allocates; on a structure-heavy document, **0 %**. The price is a
      viral type parameter through every node type, or an abstract field that
      boxes on every access. Recovering at most a twelfth in the best case is not
      worth either.

      *Memory-mapped input.* `read(path, String)` is **1.0 %** of read-plus-parse
      on a 2.9 MB document, and avoiding it needs a byte-oriented tokenizer or a
      second dependency. There is nothing there.

      **What the measurement pointed at instead.** An allocation profile put the
      top site at `_slice` in the tokenizer — a fresh `String` per element and
      attribute name, nearly all of them compared against a constant and dropped.
      That set is *closed and tiny*, so a scanned name that matches is now
      returned as the shared literal: **−22 % allocations per node reading XML,
      −14 % reading MathML.** It is not the interning `SECURITY.md` forbids,
      which is about unbounded names a *document* chooses; nothing a document
      supplies is retained.

      **Two methodology findings, both worth more than the item.** The first two
      shapes of the lookup table were type-unstable — a vector of `NTuple{2,Any}`,
      then a heterogeneous tuple indexed by a runtime length — and each boxed on
      every name, making reading **three times slower** than the allocation it
      was removing. And `just bench` measures with `minimum(...)`, which selects
      the runs where the collector did not fire and therefore **hides an
      allocation win by construction**: it showed +2 % time. Over 200 consecutive
      parses, GC included, the same change is −11.4 % wall time and −17.6 % bytes.
      The baseline's allocation column is what shows this; its time column cannot.
- [x] `AirspeedVelocity.jl` regression comments on PRs; a documented performance
      budget. **Done 2026-09-19**, and split in two, because the two numbers fail
      differently.

      **Allocation counts gate**, in `test/quality/performance.jl`, so
      `just verify` and CI both reach it without a workflow of its own. ±10 %
      against `test/harness/baseline.toml` — loose for a deterministic number,
      and meant to be: it catches a copy reintroduced or a closure per node, not
      a dictionary resizing a bucket. It skips loudly across Julia minor
      versions, because a gate that fires for the wrong reason gets switched off.
      Proved to fire before being trusted.

      **Wall time reports**, via `.github/workflows/Benchmark.yml`. On a shared
      runner it varies by a factor of two between runs, so a blocking comparison
      would be a false-failure generator, and a check that cries wolf is a check
      somebody turns off.

      The split is not a preference — it is what the interning measurement
      showed: the deterministic number showed −22 % plainly, and the timing
      statistic reported the opposite. `benchmark/workload.jl` is included by the
      harness *and* by the AirspeedVelocity suite, so the two cannot drift into
      measuring different documents.
- [ ] Extended fuzz campaign (24 h) across all **four** encodings before the
      freeze. *(Three was written when there were three. There are four.)*

      **Not yet met, and deliberately not ticked.** 24 h has not been run. What
      has: the campaign was corrected and measured on 2026-09-19, and is now
      scheduled to accumulate — nightly at 30 min plus a weekly 5 h 30 run, a
      GitHub job being capped at six hours, so roughly nine hours a week and the
      criterion met after about three weeks of green.

      **The correction is the point.** `:recover` was not fuzzed at all: the
      loop ran `(:strict, :lenient)`, and `:recover` shipped two commits earlier
      making the *strongest* of the three promises — never raises but for a
      resource limit. Adding it found two product defects in the first minute
      and one defect in the invariant itself:

      * The **binary reader raised in `:recover`**. Its "no leniency" argument is
        sound for *subtree* recovery — one wrong length and every later byte is
        misread, so there is nothing to resynchronise on — and it had been
        stretched to cover `:recover`, whose contract is only that it does not
        raise. A whole-document error object honours that. Found on the first
        input.
      * **Choosing the reader was outside recovery.** `sniff_format` raises on an
        empty input, before any reader is picked, so `:recover` raised on the
        emptiest document there is.
      * And the **invariant was too strong**: it demanded every recovered object
        be writable, which an `OMFOREIGN` holding verbatim non-XML legitimately
        is not. That is the writer's documented answer, not an escape. Recorded
        rather than quietly loosened.

      Throughput, so the 24 h figure has a measured base rather than a hope:
      **2 318 629 inputs in 8 minutes**, about 4 800 a second, across four
      encodings and three modes — so a 24 h campaign is of the order of 400
      million inputs. The last 8-minute run was clean.
- [x] **E5** — `test/unit/cross_encoding.jl`, a home for properties every encoding
      must share. Two defects survived this session in the same blind spot: the
      conformance driver checks the encodings *agree about objects*, never that
      they share *implementation* properties, and both readers produce the same
      object right up to where one stops producing anything.
- [x] Security review pass against `SECURITY.md`'s threat model. Each of the four
      claims checked against the code *and* a test rather than against the
      intention; the table is in `docs/src/security.md`. Two were wrong: the
      no-`eval` gate walked `src/` and not `ext/`, so the one place in this
      package that turns an OpenMath symbol into a call sat outside it; and
      "names are never interned" omitted its exception — decoding interns
      nothing, `from_openmath` interns, and a service that does both will intern
      every distinct name it is sent. The claim now says *by a parser*, and the
      exception has a remedy, a test and a paragraph in `SECURITY.md`.

**Exit criteria** — no performance regression ≥ 10 % vs. the Phase 4 baseline; TTFX
under budget on 1.10 and 1.13; 24 h fuzz clean.

---

## Phase 9 — API stabilisation `v0.9.0`

- [x] Public API settled; everything not exported is explicitly documented as
      internal. **Done 2026-09-20.** The public API is exactly `names(OpenMath)`,
      and `docs/src/compat.md` says so — including that a documented internal is
      still internal, which is the case a reader gets wrong.
- [x] `docs/src/compat.md` stating the versioning contract. **Done 2026-09-20.**
      It names two things treated as breaking that a case could be made against
      — a change in what a document decodes to, even to the more correct answer,
      and a newly rejected document — and two that are not: the text of an error
      message, and a writer's exact bytes where the object is unchanged. It also
      writes down what would have to be true for a `1.0.0`, as four conditions
      rather than a mood; one of them, "at least one real dependant", is not met
      and cannot be met by working harder.
- [x] Doctests on every exported symbol; `checkdocs = :exports` blocking.
      **Done 2026-09-20.** `checkdocs = :exports` was already blocking and
      already green: all 81 exported symbols had a docstring. **24 had an
      example.** The other 57 were prose nothing executed, which is the failure
      mode this project is built against, passing a gate that only asked whether
      a docstring existed.

      57 doctests written, every one run by the documentation build. A new gate
      in `test/quality/project.jl` asserts the property rather than leaving it to
      decay, with one exception that is named and justified in place:
      `symbolics_phrasebook` lives in the extension, so a `jldoctest` would pull
      the SciML stack into every docs build to check one example; it is exercised
      by `test/unit/symbolics.jl` instead.
- [x] `CHANGELOG.md` complete from `0.0.1`. **Done 2026-09-20.** Complete it was —
      every one of the fifteen commits is represented, checked one by one. What it
      was not is *true*.

      It carried a `[0.0.1] - 2026-09-17` section describing itself as "Phase 0
      and Phase 1" while listing Phase 3 work, and linking to
      `/releases/tag/v0.0.1`. **`v0.0.1` was never tagged and no release was ever
      cut.** A changelog announcing a release nobody can download is worse than
      one that says nothing. Everything is now under `[Unreleased]`, which says
      so in as many words.

      `### Added` and `### Fixed` each appeared three times under one release,
      because every commit prepended its own — mine included. Consolidated into
      one of each in Keep a Changelog's order; 123 bullets before, 123 after.

      And the rule is executable now. `test/quality/project.jl` checks the
      section names, that each appears once per release and in order, and — the
      one that matters — **resolves every version and every link against
      `git tag`**, so a section or a link naming a release that was never cut
      fails. Proved to fire.
- [ ] Registration in the General registry under MIT (decision **D6**).
      **Deliberately not done**, on the author's instruction, 2026-09-20. The
      package is registrable — name free in General, `[compat]` on every
      dependency including the weak one and on `julia`, MIT `LICENSE.md`, public
      repository — and is not being registered. Nothing about that is blocked;
      it is a decision, and registration is the one step in this roadmap that
      cannot be undone.
- [ ] Announce on JuliaLang Discourse; notify the OpenMath Society and the `openmath`
      crate author — a Julia implementation with binary + `OMR` support is worth
      cross-linking from openmath.org's implementation list. **Not done**, same
      instruction.

**Version, decided 2026-09-20: `0.1.0`, not `0.9.0`.** The roadmap's `0.9.0`
came from numbering phases, not from judging maturity, and two things argue
against it. `docs/src/compat.md` lists four conditions for a `1.0.0`, and one of
them — at least one real dependant — cannot be met by working harder, so a
number implying near-maturity would contradict the package's own compatibility
document. And it is the version the registry accepts without manual review:
of 12 447 packages in General, 61 % first register at `0.1.0` and 75.5 % at one
of `0.1.0`, `1.0.0` or `0.0.1`. 44 did first register at `0.9.0`, so it is
possible — measured rather than recalled — just not the default path.

`Project.toml` carries `0.1.0`; `CHANGELOG.md` keeps everything under
`[Unreleased]`, because no tag, release or registry entry exists and a heading
saying otherwise is exactly the defect the previous commit removed.

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
