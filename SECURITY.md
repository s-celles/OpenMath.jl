# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.0.x   | ✅        |

## Reporting a vulnerability

Please report security issues **privately**, through GitHub's coordinated
disclosure mechanism:

1. Go to <https://github.com/s-celles/OpenMath.jl/security/advisories/new>
2. Describe the issue, the affected version, and a reproducer if you have one.

Please do not open a public issue for a security problem. You can expect an
acknowledgement within 7 days and an assessment within 30 days.

## Threat model

`OpenMath.jl` decodes documents that arrive over the network — SCSCP sessions,
HTTP payloads, files of unknown provenance. **Every parser entry point is treated
as accepting hostile input.** The following are considered vulnerabilities:

- A crafted document causing a `StackOverflowError`, an unbounded allocation, a
  hang, or any exception outside the `OpenMathError` hierarchy.
- Any path by which parsed content reaches `eval`, `include_string` or
  `Meta.parse`. Parsed OpenMath is data; it is never code. This is enforced by a
  quality gate (`just quality`).
- Resolution of an XML DTD or external entity.
- Unbounded interning of attacker-controlled names. Names are `String`, never
  `Symbol`, because Julia never garbage-collects interned symbols.

The following are **not** vulnerabilities:

- Resource exhaustion within the configured limits. Tune them with `with_limits`:

  ```julia
  with_limits(OMLimits(; max_depth = 1000, max_nodes = 100_000)) do
      OpenMath.parse(untrusted)
  end
  ```

- A semantically meaningless but well-formed OpenMath object. This package
  transports mathematics; it does not evaluate or trust it.
