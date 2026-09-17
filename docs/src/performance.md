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
