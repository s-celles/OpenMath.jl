# Validation and normalisation

## Validation

[`validate`](@ref) returns every problem it finds, in document order, and never
throws — whatever the input.

```jldoctest
julia> using OpenMath

julia> obj = OMApplication(OMS"arith1#plus", [OMReference("#nowhere")]);

julia> only(validate(obj))
OMValidationIssue(:dangling_reference at /arguments[1]: no element carries the id "nowhere" [omstd20 §3.1.2])
```

Each issue carries the path to the offending sub-object and a citation of the
clause it violates.

## `cdbase` scoping

`cdbase` scopes lexically (standard §2.1.4): a symbol inherits the base of the
nearest enclosing element that declares one. [`resolve_cdbase`](@ref) pushes the
inherited value onto every symbol, which is what makes two objects comparable
regardless of where the attribute happened to be written.
[`minimize_cdbase`](@ref) is the inverse, and is what a writer wants.

```jldoctest
julia> using OpenMath

julia> a = OMApplication(OMS"arith1#plus", [OMInteger(1)]);

julia> resolve_cdbase(a).applicant.cdbase
"http://www.openmath.org/cd"

julia> minimize_cdbase(resolve_cdbase(a)) == a
true
```

## Structure sharing

[`expand_references`](@ref) replaces each `OMR` by a copy of its referent, and
refuses a cycle — "an OpenMath element may not dominate itself".

```jldoctest
julia> using OpenMath

julia> cyclic = OMApplication(OMS"arith1#plus", [OMReference("#a")]; id = "a");

julia> expand_references(cyclic)
ERROR: OpenMathReferenceError: reference cycle: an OpenMath element may not dominate itself (#a)
```

[`share_structure`](@ref) is the inverse: it finds repeated subtrees, keeps the
first occurrence, and replaces the rest by references to it.

```jldoctest
julia> using OpenMath

julia> sub = OMS"arith1#plus"(OMVariable("x"), OMInteger(1));

julia> shared = share_structure(OMS"arith1#times"(sub, sub, sub));

julia> count(n -> n isa OMReference, collect_nodes(shared))
2

julia> expand_references(shared) == OMS"arith1#times"(sub, sub, sub)
true
```

The pair is meaning-preserving in the only sense that counts: expanding a shared
object gives back what expanding the original gives. That is asserted on
generated objects, not just on examples.

**The first occurrence is what becomes the definition**, which is what keeps a
reference from ever preceding its target. That is not tidiness — the binary
encoding forbids forward references outright (§3.2.5), so a pass that produced
one would build objects this package could not write.

Two things it will not do. A leaf is never shared, because a reference costs more
than the leaf in every encoding the standard defines; `min_nodes` lowers the
threshold for a caller who knows otherwise. And an `id` that an existing `OMR`
names is never taken away: where one occurrence of a repeated subtree carries
such an id, the definition adopts it, and where two occurrences carry *different*
live anchors the subtree is left alone entirely, because only one could survive
and the other reference would dangle.

What it buys, on an expression holding the same subterm four times:

| Encoding | Expanded | Shared | |
|:--|--:|--:|--:|
| XML | 707 B | 399 B | 44 % smaller |
| JSON | 1315 B | 675 B | 49 % smaller |
| binary | 207 B | 98 B | 53 % smaller |

Sharing is never applied for you. It changes the bytes an object is written as,
and a writer that silently rewrote its input would be the wrong default —
[`canonicalize`](@ref) expands references rather than introducing them.

## Canonical form

[`canonicalize`](@ref) is the normal form used for comparison: references
expanded, attributions flattened, `cdbase` resolved, `id`s dropped. It is
idempotent.

```jldoctest
julia> using OpenMath

julia> c = canonicalize(OMS"arith1#plus"(OMInteger(1)));

julia> canonicalize(c) == c
true
```
