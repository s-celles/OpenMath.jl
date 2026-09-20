```@meta
EditURL = "https://github.com/s-celles/OpenMath.jl/blob/main/test/harness/report.jl"
```

# Conformance

!!! note "This page is generated"
    Every number below is produced by the conformance driver
    (`test/harness/corpus.jl`) from the corpus in this repository, rendered by
    `test/harness/report.jl`, and regenerated with `just conformance-report`.
    A test asserts the page matches a fresh run, so it cannot drift from what
    the harness measures. Nothing here is typed by hand.

OpenMath.jl implements OpenMath 2.0 (omstd20 rev. 3, 2019-07-01). The standard endorses **four**
encodings, and this package implements all four: an XML encoding (§3.1), a
binary encoding (§3.2), a JSON encoding (§3.3) and Strict Content MathML
(MathML 4 §4.1.3).

## Corpus

**84 of 84** corpus items conform.

Each item is a directory carrying at least one encoding of one object. The
driver decodes what the item carries, **derives every encoding it does not**
from one it does, and requires all of them to agree — so an item added as XML
alone exercises the other three the day their writers land, with no edit to
the item.

| Group | Items | Negative | Passing | |
|:--|--:|--:|--:|:--|
| `invalid/` | 27 | 27 | 27 | ✅ |
| `json/` | 14 | 0 | 14 | ✅ |
| `regression/` | 4 | 0 | 4 | ✅ |
| `standard/` | 39 | 0 | 39 | ✅ |

## Coverage per encoding

*Carried* is an encoding the item holds on disk; *derived* is one the driver
writes and reads back. Both are checked; the distinction is which one the
corpus had to store.

| Encoding | Carried | Derived | Skipped | Covered | |
|:--|--:|--:|--:|--:|--:|
| `binary` | 5 | 78 | 1 | **83** | 99 % |
| `json` | 14 | 69 | 1 | **83** | 99 % |
| `mathml` | 0 | 83 | 1 | **83** | 99 % |
| `xml` | 65 | 19 | 0 | **84** | 100 % |

## Failures

None. Every item above conforms on this commit.

## What is not counted here

Several hundred further items are harvested from the official Content
Dictionaries by `just corpus-fetch`. They are a derived work under a licence
that asks more of a derived work than a test fixture should carry, so they
live outside the repository and are **excluded from this page**: it reports
on what a clean checkout can verify. `just conformance-full` runs them too.

How many there are is deliberately not stated. It is a property of whoever
ran `corpus-fetch`, not of this repository, and this page once printed the
number from the machine that generated it — so the page claiming to report
what a clean checkout can verify was itself unreproducible on one, and every
CI job failed the staleness gate that exists to catch exactly that.

The report behind this page is also available as JSON — `just
conformance-report` writes it to `refs/conformance.json` — for anyone who
would rather consume the numbers than read them.
