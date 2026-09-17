# OpenMath.jl

A Julia implementation of the [OpenMath 2.0](https://openmath.org/) standard.

OpenMath encodes the *semantics* of mathematical objects rather than their
appearance. An OpenMath object is a small, fully specified tree whose leaves take
their meaning from **Content Dictionaries** — machine-readable documents defining
symbols such as `arith1#plus` or `calculus1#diff`.

!!! warning "Early development"
    The object model, validation, the normalisation passes, all four endorsed
    encodings and Content Dictionary parsing are in place. The API is not yet
    stable; see the roadmap for what 0.9.0 requires.

## Quick start

```jldoctest
julia> using OpenMath

julia> e = OMS"arith1#plus"(OMInteger(1), OMVariable("x"))
OMA(OMS(arith1#plus), OMI(1), OMV(x))

julia> isvalid_openmath(e)
true

julia> canonicalize(e).applicant.cdbase
"http://www.openmath.org/cd"
```

## Reading the XML encoding

```jldoctest
julia> using OpenMath

julia> o = OpenMath.parse("""
           <OMOBJ xmlns="http://www.openmath.org/OpenMath">
             <OMA><OMS cd="arith1" name="plus"/><OMI>1</OMI><OMV name="x"/></OMA>
           </OMOBJ>""");

julia> o.object
OMA(OMS(arith1#plus), OMI(1), OMV(x))
```

`OpenMath.parse` determines the encoding from the leading bytes by default — see
[The four encodings](encodings.md) — and takes a strictness mode: `:strict`
rejects any deviation from the standard, `:lenient` accepts documented ones and
records them on the result.

```jldoctest
julia> using OpenMath

julia> o = OpenMath.parse("<OMOBJ><OMI>1</OMI></OMOBJ>"; mode = :lenient);

julia> o.warnings
1-element Vector{String}:
 "no OpenMath namespace declared"
```

## Writing the XML encoding

```jldoctest
julia> using OpenMath

julia> OpenMath.xml(OMObject(OMS"arith1#plus"(OMInteger(1), OMVariable("x"))))
"<OMOBJ xmlns=\"http://www.openmath.org/OpenMath\" version=\"2.0\"><OMA><OMS cd=\"arith1\" name=\"plus\"/><OMI>1</OMI><OMV name=\"x\"/></OMA></OMOBJ>"
```

`cdbase` is written only where the effective base changes, and `OMF` takes the
IEEE-754 `hex` form exactly when the decimal one would lose the value.

## Converting Julia values

[`to_openmath`](@ref) and [`from_openmath`](@ref) are the extension points.

```jldoctest
julia> using OpenMath

julia> to_openmath(3 // 4)
OMA(OMS(nums1#rational), OMI(3), OMI(4))

julia> from_openmath(to_openmath([1, 2, 3]))
3-element Vector{Int64}:
 1
 2
 3
```

A third-party type joins in by adding one method — no subtyping required:

```jldoctest
julia> using OpenMath

julia> struct Celsius
           value::Float64
       end

julia> OpenMath.to_openmath(c::Celsius) =
           OMS"http://example.org/cd#units#celsius"(to_openmath(c.value));

julia> to_openmath(Celsius(21.5))
OMA(OMS(http://example.org/cd#units#celsius), OMF(21.5))
```
