# Popcorn

Popcorn is a compact linear notation for OpenMath objects, introduced by Peter
Horn and Dan Roozemond in *OpenMath in SCIEnce: SCSCP and POPCORN*
(Calculemus/MKM 2009, LNAI 5625). It writes `1 + $x` where the XML encoding
needs a document of six elements:

```jldoctest popcorn
julia> using OpenMath

julia> obj = OMS"arith1#plus"(OMInteger(1), OMVariable("x"));

julia> OpenMath.popcorn(obj)
"1 + \$x"

julia> OpenMath.xml(obj)
"<OMOBJ xmlns=\"http://www.openmath.org/OpenMath\" version=\"2.0\"><OMA><OMS cd=\"arith1\" name=\"plus\"/><OMI>1</OMI><OMV name=\"x\"/></OMA></OMOBJ>"
```

It is also how the REPL shows an object:

```jldoctest popcorn
julia> obj
1 + $x

julia> repr(obj)
"OMA(OMS(arith1#plus), OMI(1), OMV(x))"
```

The REPL falls back to that functional form whenever Popcorn would hide
something: a `cdbase` anywhere in the object, or an `OMFOREIGN` with an
encoding. `repr`, string interpolation and containers always use it, and so
does an `OMObject`.

Popcorn is **for reading**. It is not part of the OpenMath standard and not an
interchange format: it has no syntax for `cdbase`, and an `OMFOREIGN` loses its
encoding. Exchange objects in one of the [four encodings](encodings.md).

[`write_popcorn`](@ref) writes to a stream, [`OpenMath.popcorn`](@ref) returns a
`String`, and [`read_popcorn`](@ref) reads it back:

```jldoctest popcorn
julia> read_popcorn("lambda[\$x -> \$x^2 + 1]")
OMOBJ(OMBIND(OMS(fns1#lambda), [x], OMA(OMS(arith1#plus), OMA(OMS(arith1#power), OMV(x), OMI(2)), OMI(1))))

julia> read_popcorn(OpenMath.popcorn(obj)).object == obj
true
```

What [`write_popcorn`](@ref) writes reads back as the same object, but for what
Popcorn has no syntax for. That is a tested property, on generated objects.

## The notation

| OpenMath | Popcorn |
|:--|:--|
| `OMI(42)`, `OMI(-3)` | `42`, `-3` |
| `OMF(0.5)`, `OMF(Inf)` | `0.5`, `0f7FF0000000000000` (the IEEE bits) |
| `OMSTR("a\"b")` | `"a\"b"` |
| `OMV(x)` | `$x` |
| `OMS(arith1#plus)` | `arith1.plus` |
| `OMB(3 bytes)` | `%AQID%` (base64) |
| `OMR(#a)` | `#a` |
| an application | `cd.f($x, 2)` |
| an error | `cd.f!("message")` |
| a binding | `forall[$x, $y -> body]` |
| an attribution | `obj{ecc.type -> setname1.Z}` |
| an `id` | `$x:a`, or `(cd.f($x)):a` on anything but an atom |

A name that is not a plain identifier — or that is one of the grammar's
keywords, such as `or` — is written in single quotes: `$'x-1'`, `logic1.'and'`.

### Infix operators

The symbols of the common Content Dictionaries have infix forms, and brackets
appear only where the grammar needs them:

```jldoctest popcorn
julia> x, y = OMVariable("x"), OMVariable("y");

julia> OpenMath.popcorn(OMS"arith1#times"(OMS"arith1#plus"(x, OMInteger(1)), y))
"(\$x + 1)*\$y"

julia> OpenMath.popcorn(OMS"logic1#implies"(OMS"relation1#lt"(x, y), OMS"relation1#eq"(x, y)))
"\$x < \$y ==> \$x = \$y"
```

From loosest to tightest:

| Level | Operators | Symbols |
|--:|:--|:--|
| 1 | `;` | `prog1#block` |
| 2 | `:=` | `prog1#assign` |
| 3 | `==>` `<=>` | `logic1#implies`, `logic1#equivalent` |
| 4 | `or` | `logic1#or` |
| 5 | `and` | `logic1#and` |
| 6 | `=` `<` `<=` `>` `>=` `!=` `~` | `relation1#eq` … `relation1#neq`, `relation2#approx` |
| 7 | `..` | `interval1#interval` |
| 8 | `+` `-` | `arith1#plus`, `arith1#minus` |
| 9 | prefix `-` | `arith1#unary_minus` |
| 10 | `*` `/` | `arith1#times`, `arith1#divide` |
| 11 | `^` | `arith1#power` |
| 12 | `\|` | `complex1#complex_cartesian` |
| 13 | `//` | `nums1#rational` |

`list1#list` and `set1#set` are written `[a, b]` and `{a, b}`. A symbol with no
infix form, or an operator applied to a number of operands its form cannot
show, is written as a call: `arith1.plus($x)`, `logic1.'and'($x, $y, $z)`.

A few symbols are written without their Content Dictionary: `sin`, `cos`,
`tan`, `exp`, `sinh`, `cosh`, `tanh`, `pi`, `e`, `i`, `infinity`, `true`,
`false`, `not`, `min`, `max`, `abs`, `sum`, `product`, `root`, `lambda`,
`forall`, `exists`.

```jldoctest popcorn
julia> OpenMath.popcorn(OMBinding(OMS"quant1#forall", [OMBoundVariable("x")], OMS"relation1#geq"(OMS"transc1#exp"(x), OMInteger(0))))
"forall[\$x -> exp(\$x) >= 0]"
```

## Reading

[`read_popcorn`](@ref) reads the reference grammar, and a little more than this
package writes: hexadecimal integers (`0x1F`), `/* comments */`, `<>` for
`!=`, and the `if … then … else … endif` and `while … do … endwhile` forms of
`prog1`. A chain `a + b + c` is one `arith1#plus` of three operands, while
`(a + b) + c` keeps its brackets. Errors are `OpenMathParseError`s with the byte
offset of the token at fault:

```jldoctest popcorn
julia> read_popcorn("\$x < \$y < \$z")
ERROR: OpenMathParseError: "<" does not chain; put one side in brackets at byte 9
```

It does not read `x::T`, which the reference library accepts only once a type
symbol has been configured, nor any bare name outside the list above.

How this follows the reference grammar, and where it departs from the
reference library, is in the [design note](design/popcorn.md).
