# Popcorn — following the grammar, not the renderer

**Status**: the printer is implemented (REQ-POP-001); the parser is not yet.

Popcorn has no standard. Its definition is the 2009 paper — Horn and Roozemond,
*OpenMath in SCIEnce: SCSCP and POPCORN*, Calculemus/MKM 2009, LNAI 5625,
pp. 474–479 — and the Java library `org.symcomp.openmath` (Apache 2.0, last
commit `e982655`, 2010-10-20), which carries three things:

- `PopcornAST.g`, the ANTLR grammar: what a Popcorn string *is*;
- `PopcornWalker.g` and `PopcornHelper.java`: what object a parse *builds*;
- `PopcornRenderer.java` and `popcorn/symbols/*.java`: what the library *prints*.

The three disagree in places. This printer follows the first two, because the
only promise worth making about printed Popcorn is that it reads back as the
object it came from. None of the library's code is carried here; it was read as
a specification, and this page records what was taken from it.

## Precedence comes from the grammar

The renderer gives each operator a number — `plus` 70, `minus` 75, `times` 80,
`divide` 85, `power` 90. The grammar puts `+` and `-` on one rule and `*` and
`/` on another, so `a - b + c` parses as `plus(minus(a, b), c)`; a printer using
the renderer's numbers would bracket `(a - b) + c` for no reason, and worse, the
renderer's own `plus` method tests the *array* of operands, not an operand, for
`unary_minus`, so that branch never runs. The fourteen levels in
[the notation page](../popcorn.md#Infix-operators) are the grammar's rule nesting.

## What a parse builds decides what can be printed

- **`-3` is the integer -3.** `applyUnaryMinus` folds a literal, so
  `unary_minus(OMI(3))` cannot be written `-3`, nor `-(3)`: it is printed as the
  call `arith1.unary_minus(3)`. A negative literal is printed `-3`, at the level
  of a prefix minus, so `(-2)^2` and `$x*(-3)` keep their brackets.
- **`..` builds `interval1#interval` only.** `interval1#integer_interval`, which
  the renderer also prints with `..`, is a call.
- **`+`, `*` and `;` are flattened**, by `applyFlat`, on both sides and through
  brackets: `(a + b) + c` and `a + (b + c)` both build `plus(a, b, c)` in the
  reference parser. This printer brackets a nested `plus` all the same, so that
  a parser that does respect brackets — this package's, when it exists — reads
  the object back exactly. The reference parser cannot, for any notation.
- **`and` and `or` are not flattened**: the walker builds them two operands at a
  time. So they are printed infix with exactly two operands, and
  `and(a, b, c)` is a call. Printing `a and b and c` would read back as
  `and(and(a, b), c)`.

## Names the renderer prints and its parser cannot read

- **Bare names.** The renderer prints `ln`, `log`, `arcsin`, `arccos`,
  `arctan`, `gcd` and `lcm` without their Content Dictionary; none of them is in
  `PopcornHelper.translate`, the table the parser resolves bare names with. Only
  names checked against that table are printed bare here.
- **Keywords.** `or`, `and`, `if`, `then`, `else`, `endif`, `while`, `do` and
  `endwhile` are tokens of the grammar, so `$or` lexes as `$` followed by a
  keyword, and `logic1.and` does not lex as a symbol. The renderer quotes a name
  only when it is not an identifier; this printer quotes keywords as well:
  `$'or'`, `logic1.'and'`.
- **Ids on compound objects.** The renderer prints an id after an attribution
  — `x{…}:id` — which the grammar rejects: an id belongs to an *anchor*, an atom
  or a bracketed expression. Here an id on anything but an atom is printed on
  the bracketed object: `(cd.f($x)):id`.

## Known limits of the grammar itself

These are kept, and noted, because a Popcorn string this package prints should
also be one the reference reads where it can:

- `HEXFLOAT` is `'0f'` followed by **one** hex digit in the grammar, so the
  reference lexer cannot read the sixteen digits of a non-finite float. Popcorn
  has no other way to write one; it is printed `0f7FF0000000000000`.
- `OMB` accepts letters, digits and `=` only, not the `+` and `/` of base64.
  Bytes are printed in standard base64 regardless.
- `cdbase` has no syntax. A symbol is printed by its Content Dictionary and name,
  and the infix and bare forms are used only when it has no `cdbase` of its own.
- `OMFOREIGN` is printed between backquotes; its encoding has no syntax.
