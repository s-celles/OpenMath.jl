# Performance

Measured, not asserted. `just bench` prints these numbers and
`just bench --save` records them in `test/harness/baseline.toml`, which is what
"no regression ≥ 10 %" is measured against.

## Time to first parse

The number that decides whether a package feels slow, because a script that reads
one document pays it and nothing else.

| | before | after |
|:--|--:|--:|
| bare `julia` | 0.121 s | 0.121 s |
| `using OpenMath` | 0.147 s | 0.231 s |
| **+ the first `parse`** | **4.132 s** | **0.32 s** |

Loading the package was never the problem — it cost 26 ms. The four seconds were
inference and code generation on the first call, paid again by every process. A
`PrecompileTools` workload in `src/precompile.jl` caches it.

That workload is the only reason this package has a runtime dependency.
`PrecompileTools` is pure Julia with no binary artifact, so REQ-PRJ-002 still
holds, and the measurement above is what justifies it: the alternative was
telling every caller to eat four seconds.

## Throughput

A specimen of 1601 nodes, best of 30 runs, on one machine:

| | bytes | ms | MiB/s | allocations per node |
|:--|--:|--:|--:|--:|
| write XML | 34 687 | 0.92 | 36.1 | 9.4 |
| read XML | 34 687 | 1.16 | 28.5 | 20.4 |
| write JSON | 60 676 | 0.97 | 59.8 | 12.3 |
| read JSON | 60 676 | 1.36 | 42.6 | 23.5 |
| write MathML | 40 686 | 0.86 | 45.1 | 7.9 |
| read MathML | 40 686 | 1.31 | 29.7 | 25.5 |
| write binary | 12 967 | 1.03 | 12.1 | 13.2 |
| **read binary** | **12 967** | **0.23** | 53.8 | **6.6** |

Two things worth reading off it.

**The binary encoding does what it was designed for.** 12 967 bytes against
34 687 for XML and 60 676 for JSON — 2.7× and 4.7× smaller — and it reads five
times faster than XML with a third of the allocations. §3.2 opens by saying it
"was essentially designed to be more compact than the XML encodings, so that it
can be more efficient if large amounts of data are involved", and that is
measurably true.

**Reading JSON was the slow path**, at 38 allocations per node against XML's 20.
That is what this table is for, and following it found two defects:

- `_scan_string!` allocated an `IOBuffer` for *every* string, including the
  overwhelming majority that contain no escape. Those now copy the span in one
  go. **−22 % allocations.**
- The reader built its error paths eagerly — `path * "/applicant"` at every node,
  a string of length O(depth), allocated whether or not anything went wrong. It
  was 4.6 MB of the 4.7 MB a 1601-node document spent. Paths are now a linked
  list materialised only on the way to throwing. **−24 % more.**

Reading JSON now costs 23.5 allocations per node and 1.36 ms, against XML's 20.4
and 1.20 ms — from twice the cost to near parity. (A little of the gain was given
back when the builder moved onto an explicit stack: the frames cost something,
and unbounded depth is worth more than 1.2 allocations per node.)

The second defect is the one worth remembering: it is exactly the shape the XML
reader had in Phase 2, where it caused an out-of-memory at 200 000 levels. The
fix was never propagated, and neither was the test that would have caught it.

Throughput varies by roughly a factor of two between runs on a shared machine, so
a regression budget against these has to be generous: they catch a change of
order, not of constant factor. The time-to-first-parse figures are the stable
ones.

## Invalidations

Loading a package can invalidate compiled code other packages already hold, and
every invalidated method instance is latency a downstream user pays without
having asked for it. `just invalidations` measures it.

```
  method instances invalidated   9
  trees whose method is ours     0
  trees from elsewhere           1

  · Dates: is_valid_toml_value  (10 children)
```

**None of the nine is caused by a method this package inserts.** The single tree
is `Dates` superseding `Base.TOML.Printer.is_valid_toml_value(::Any)`, reached
by `OpenMath → PrecompileTools → Preferences → TOML → Dates`: two standard
libraries meeting on the way in, which is not ours to narrow.

That distinction is the point of the audit. A count alone is not actionable —
the question is not *how many* but *whose*. An invalidation caused by a method
we insert is almost always a signature wider than the argument it means, or an
outright piracy, and both are ours to fix. One caused by a dependency chain is
not, and reporting them together would make the gate noise.

The number is recorded in `test/harness/baseline.toml`, so a rise fails rather
than being absorbed, and raising the ceiling is an edit in the same commit as
whatever caused it. `.github/workflows/Invalidations.yml` makes the same
comparison on a pull request against the default branch — it used to print the
two numbers and leave the comparing to whoever read the log, which is the same
as not comparing them.

It is also the other half of a measurement this documentation already carries.
[Time to first parse](#Time-to-first-parse) justified adding `PrecompileTools`,
the package's one dependency, by measuring what it bought: 4.132 s to 0.32 s.
This measures what it cost: nine invalidations, from the `TOML`/`Dates` pair it
drags in. Both numbers now exist.

## What a benchmark of the minimum cannot see

`just bench` reports `minimum(...)` over thirty samples, which is the right
statistic for comparing *computation* — it discards the runs where the operating
system or the collector interfered. It is the wrong statistic for an allocation
change, and it hid one completely.

Interning markup names removed about a fifth of what the XML reader allocates.
Measured as a minimum over forty runs, the change looked like **+2 % time**:
the minimum is, almost by definition, a run in which the garbage collector did
not fire, so the saving has nowhere to show. Measured over 200 consecutive
parses with collection counted:

| | before | after |
|:--|--:|--:|
| wall time, 200 parses | 1549.2 ms | **1372.3 ms** |
| of which collection | 160.7 ms | 135.2 ms |
| allocated | 1306.0 MB | **1075.5 MB** |

−11.4 % wall time, not +2 %. The allocation column of
`test/harness/baseline.toml` is what makes such a change visible; the time
column cannot, and reading only the time column would have led to reverting it.

## The performance budget

Two halves, because the two numbers fail differently.

| | measured by | on a regression |
|:--|:--|:--|
| **allocation counts** | `test/quality/performance.jl`, in `just verify` and CI | **fails** |
| **wall time** | `.github/workflows/Benchmark.yml`, AirspeedVelocity, on each pull request | comments |

**Allocations gate.** An allocation count is deterministic within a Julia
version, so a rise is a fact rather than a mood. The budget is ±10 % against
`test/harness/baseline.toml` — loose for a deterministic number, and meant to
be: it catches a change of *shape*, such as a copy reintroduced or a closure
built per node, not the noise of a dictionary resizing a bucket differently. It
skips loudly when the running Julia's minor version differs from the one the
baseline was recorded on, because comparing counts across versions fires for the
wrong reason, and a gate that fires for the wrong reason gets switched off.

Raising the ceiling is `just bench --save` in the same commit as whatever caused
the rise, which makes it a reviewable edit rather than a silent drift.

**Time reports.** Wall time on a shared runner varies by roughly a factor of two
between runs. A blocking comparison would produce false failures, and a check
that cries wolf is a check somebody turns off, so the pull-request comment
states the comparison and leaves the judgement to a reader who can see the
change. Both sides measure the same workload — `benchmark/workload.jl` is
included by the harness *and* by `benchmark/benchmarks.jl`, because two
definitions of "the document we measure" would drift and then the two numbers
would not be about the same thing.

This split is not a preference. It is what the interning measurement above
demonstrated: the deterministic number showed the improvement plainly, and the
timing statistic reported the opposite.
