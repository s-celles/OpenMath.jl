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
