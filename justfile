# SPDX-License-Identifier: MIT
#
# The agent's and the contributor's API (harness spec §7). Every target is
# deterministic, has bounded output, and exits non-zero on failure.
#
# `just --list` shows the comment line immediately above each recipe, so every
# recipe keeps a single-line description and any longer rationale goes in a block
# separated from it.

julia := "julia"
proj  := "--project=."
tproj := "--project=test"

# List the available targets.
default:
    @just --list

# --- the loop -----------------------------------------------------------------

# The single source of truth. tier = fast | standard | full.
verify tier="standard" *ARGS:
    {{julia}} {{tproj}} test/harness/verify.jl --tier {{tier}} {{ARGS}}

# The same, on the oldest supported Julia (REQ-PRJ-001 names 1.10 LTS and 1.13).
#
# This exists because it did not, and the first CI run found three defects on
# 1.10 that every local run had passed: two undeclared test dependencies that a
# grown manifest hid, and a genuine `MethodError` that JET sees on 1.10 and not
# on 1.13. "The single source of truth" covered one of the two versions the
# package promises.
# Its environment lives under refs/ because Manifest.toml is shared between
# Julia versions: resolving the test environment on 1.13 pins versions 1.10
# cannot load, and back again. `just verify-lts-setup` builds it once.
verify-lts-setup:
    {{julia}} +1.10 {{tproj}} test/harness/lts_env.jl

verify-lts tier="full" *ARGS:
    {{julia}} +1.10 --project=refs/lts-test test/harness/verify.jl --tier {{tier}} {{ARGS}}

# Both supported versions, which is what CI actually gates on.
verify-all: verify-lts (verify "full")

# The same, as JSON, for the agent loop.
verify-json tier="standard":
    @{{julia}} {{tproj}} test/harness/verify.jl --tier {{tier}} --json

# The inner loop: everything that must stay under ten seconds.
check: (verify "fast")

# Print the first unblocked task card.
next:
    @{{julia}} {{tproj}} test/harness/next.jl

# --- tests --------------------------------------------------------------------

# Run the whole test suite through TestItemRunner.
test:
    {{julia}} {{tproj}} test/runtests.jl

# Run only the test items carrying TAGS (comma-separated).
test-tags TAGS:
    OPENMATH_TEST_TAGS={{TAGS}} {{julia}} {{tproj}} test/runtests.jl

# Unit tests only.
test-fast: (test-tags "unit")

# Apply SciML formatting to every Julia file.
format:
    @{{julia}} {{tproj}} -e 'using JuliaFormatter; format(".")'

# Quality gates: formatting, Aqua, JET, SPDX headers, dependency hygiene, no-eval.
quality: (test-tags "quality")

# Conformance corpus driver; includes downloaded vectors when they are present.
conformance: (test-tags "conformance")

# Property-based layer on Supposition.jl.
property: (test-tags "property")

# The long-running items: deep documents and their complexity budgets.
slow: (test-tags "slow")

# --- guardrails ---------------------------------------------------------------

# Measure throughput, allocations per node and time to first parse.
bench *ARGS:
    @{{julia}} {{tproj}} test/harness/bench.jl {{ARGS}}

# Mutation-fuzz the readers. No network, no foreign toolchain — hence in CI.
fuzz *ARGS:
    @{{julia}} {{tproj}} test/harness/fuzz.jl {{ARGS}}

# Corpus integrity: an existing item may not be modified or deleted.
corpus-check *ARGS:
    @{{julia}} {{tproj}} test/harness/corpus_check.jl {{ARGS}}

# Clean-room check against the GPL-3 reference (run `just oracle-setup` first).
clean-room *ARGS:
    @{{julia}} {{tproj}} test/harness/clean_room.jl {{ARGS}}

# --- opt-in checks, deliberately NOT in CI ------------------------------------
#
# These need a network clone and a Rust toolchain, and they build a binary that
# links GPL-3 code. Running them in CI would make every build depend on a
# third-party repository staying reachable — which contradicts the hermeticity
# `just verify` promises — and would put GPL-3 artefacts in the pipeline of an
# MIT package. So they are commands you run when you want the answer.
#
# Nothing in this section is required to build, test, document or release the
# package, and `just all` never invokes any of it.
#
# Nothing downloaded here is ever committed. Everything lands under refs/, which is
# gitignored, and a quality gate enforces that nothing under it becomes tracked.
#
# For the reference crate that is a licence boundary: it is GPL-3 and we are MIT.
# For the Content Dictionary vectors it is a different licence question — the
# dictionaries may be redistributed verbatim, but extracted fragments are a
# derived work, and their licence asks a derived work to carry a prominent
# reference to the original and a prominent statement that it is not the original.
# That is more than a test fixture should carry, so they are downloaded rather
# than shipped. Downloading is not redistribution, so nothing is lost but the
# repository stays clean.

# Download conformance vectors from the official Content Dictionaries (network).
corpus-fetch *ARGS:
    @{{julia}} {{tproj}} test/harness/corpus_fetch.jl {{ARGS}}

# Download those vectors and run the conformance suite against them.
conformance-full: corpus-fetch conformance

# Delete the downloaded vectors.
corpus-clean:
    rm -rf refs/corpus-cd

# Download the GPL-3 reference crate into refs/ and build the oracle wrapper.
oracle-setup:
    @{{julia}} {{tproj}} test/harness/oracle_build.jl

# Differential test: run the corpus through both implementations, compare meaning.
oracle *ARGS:
    @{{julia}} {{tproj}} test/harness/oracle.jl {{ARGS}}

# Delete the oracle and the reference clone.
oracle-clean:
    rm -rf refs/om-oracle refs/rust-openmath

# Download binary streams written by GAP's openmath package (network).
#
# The one encoding with no oracle in this repository is the binary one: the Rust
# crate lists §3.2 under TODO. GAP implements it and ships streams it produced
# itself. What is downloaded is data, not source — no GPL code is read or linked —
# and it lands in gitignored refs/, never in the repository.
gap-vectors:
    @{{julia}} {{tproj}} test/harness/gap_vectors.jl

# Download them and run the conformance suite, which picks them up when present.
conformance-gap: gap-vectors conformance

# Delete the downloaded GAP vectors.
gap-vectors-clean:
    rm -rf refs/gap-openmath

# Install GAP and its openmath package into refs/ (network, ~1 GB, a C build).
#
# GAP is the only other implementation of the binary encoding, so it is the only
# differential oracle §3.2 can have. Same licence boundary as the Rust oracle:
# GPL run as a subprocess, never linked, never committed, all under gitignored
# refs/. Installed with conda into refs/gap-env rather than as a system package,
# so `just oracle-gap-clean` really removes it.
oracle-gap-setup:
    @{{julia}} {{tproj}} test/harness/oracle_gap_build.jl

# Differential test of the binary encoding against GAP, in both directions.
oracle-gap *ARGS:
    @{{julia}} {{tproj}} test/harness/oracle_gap.jl {{ARGS}}

# Delete the GAP installation and its packages.
oracle-gap-clean:
    rm -rf refs/gap-env refs/gap-root

# Build the MathML.jl environment for the phrasebook oracle (network).
#
# Kept out of test/Project.toml on purpose: MathML.jl pins Symbolics to an exact
# version, and a test dependency on it would pin this package's test environment
# to that one patch release. See docs/src/design/phrasebook.md.
oracle-mathml-setup:
    @{{julia}} {{tproj}} test/harness/oracle_mathml_build.jl

# Differential test of the phrasebook against MathML.jl, on paired vectors.
oracle-mathml *ARGS:
    @{{julia}} --project=refs/mathml-env test/harness/oracle_mathml.jl {{ARGS}}

# Delete the MathML.jl environment.
oracle-mathml-clean:
    rm -rf refs/mathml-env

# --- documentation ------------------------------------------------------------

# Build the documentation. Fails on any warning.
docs:
    {{julia}} --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path=pwd())); Pkg.instantiate()'
    {{julia}} --project=docs docs/make.jl

# --- everything ---------------------------------------------------------------

# Quality, tests and docs — what CI runs. Never the opt-in section above.
all: quality test docs

# Remove build artifacts.
clean:
    rm -rf docs/build
