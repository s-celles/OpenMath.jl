# Contributing

Thanks for considering a contribution.

## The loop

```console
$ just next                # the first unblocked task card, if any
$ just verify fast         # inner loop, under ten seconds
$ just verify standard     # before opening a pull request
$ just docs                # must build with zero warnings
```

`just verify` is the single source of truth. If it is green, the change is ready
to review; if it is red, the JSON report names the file, the requirement and one
recommended next action.

## Ground rules

- **Tests first.** Every change begins with a failing test. New behaviour needs a
  test item and, once the encoders exist, a corpus item.
- **Requirements are traceable.** Cite the requirement id (`REQ-XXX-NNN` from
  `specs/requirements.md`) in the header comment of the test file that covers it;
  the verifier reads it back and shows it on failure.
- **Conventional commits**: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
  `chore:`. The project follows Semantic Versioning.
- **Changelog.** Every notable change goes into `CHANGELOG.md` under
  `Unreleased`, in the same commit as the change.
- **Clean room.** The Rust `openmath` crate is GPL-3.0-or-later and this package
  is MIT. You may read it to understand a design decision. You may not copy code,
  comments or data tables from it. Everything finer-grained than architecture must
  be derived from the published standard.
- **Corpus is append-only.** Once the conformance corpus exists, an existing item
  may not be modified or deleted to make a test pass. Add items; never weaken them.

## Opt-in checks

Two commands are deliberately outside CI, because they need a network clone and a
Rust toolchain and they build a binary that links GPL-3 code:

```console
$ just oracle-setup    # download the reference crate, build the oracle wrapper
$ just oracle          # run the corpus through both implementations
$ just clean-room      # no verbatim overlap with the GPL-3 reference
$ just oracle-clean    # remove both again
```

Nothing there is required to build, test, document or release the package, and
`just all` never invokes it. Run them when you want the answer — before touching
an encoder is a good moment. Disagreements go to `upstream-bugs.md` with the
exact crate version, after checking the document against an independent parser.

## Supported versions

Julia 1.10 (LTS) and 1.13, on Linux, macOS and Windows.
