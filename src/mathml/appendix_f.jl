# SPDX-License-Identifier: MIT
#
# MathML 4 Appendix F — the non-strict → strict transformation (REQ-MML-006).
#
# `read_mathml` refuses non-strict Content MathML by default, because the full
# language has constructs with no OpenMath counterpart and guessing at them is
# how this bridge usually goes wrong. Appendix F removes the guessing: it defines
# the transformation *normatively*, so with `strict = false` there is a rule, and
# it is either followed or the input is refused naming the section.
#
# What is implemented, and what is not, is in
# docs/src/design/mathml-appendix-f.md. In short: the token, operator, constant
# and container rules (F.4.3, F.4.4, F.7.1, F.8, F.9.1), and not the qualifier
# and `domainofapplication` machinery (F.2, F.3, F.5, F.6), which rewrites
# derivatives, integrals, limits, sums, roots, logarithms, moments and restricted
# functions and is a much larger piece of work.

# F.8 "Rewrite: element — Rewrite any remaining operator defined in 4.3 Content
# MathML for Specific Structures to a csymbol referencing the symbol identified
# in the syntax table."
#
# The table is the one MathML's Content elements were named after, so it is also
# the phrasebook's vocabulary; `test/unit/mathml_appendix_f.jl` asserts the two
# agree, since a name in one and not the other is a gap rather than a choice.
const _F_OPERATORS = Dict{String, Tuple{String, String}}(
    "plus" => ("arith1", "plus"), "times" => ("arith1", "times"),
    "divide" => ("arith1", "divide"), "power" => ("arith1", "power"),
    "abs" => ("arith1", "abs"), "root" => ("arith1", "root"),
    "gcd" => ("arith1", "gcd"), "lcm" => ("arith1", "lcm"),
    "sum" => ("arith1", "sum"), "product" => ("arith1", "product"),
    # F.8.1: the symbol depends on the argument count, resolved in `apply`.
    "minus" => ("arith1", "minus"),
    "exp" => ("transc1", "exp"), "ln" => ("transc1", "ln"),
    "log" => ("transc1", "log"),
    "eq" => ("relation1", "eq"), "neq" => ("relation1", "neq"),
    "lt" => ("relation1", "lt"), "gt" => ("relation1", "gt"),
    "leq" => ("relation1", "leq"), "geq" => ("relation1", "geq"),
    "approx" => ("relation1", "approx"),
    "and" => ("logic1", "and"), "or" => ("logic1", "or"),
    "xor" => ("logic1", "xor"), "not" => ("logic1", "not"),
    "implies" => ("logic1", "implies"),
    "factorial" => ("integer1", "factorial"),
    "quotient" => ("integer1", "quotient"), "rem" => ("integer1", "remainder"),
    "ceiling" => ("rounding1", "ceiling"), "floor" => ("rounding1", "floor"),
    "round" => ("rounding1", "round"), "trunc" => ("rounding1", "trunc"),
    "max" => ("minmax1", "max"), "min" => ("minmax1", "min"),
    "real" => ("complex1", "real"), "imaginary" => ("complex1", "imaginary"),
    "conjugate" => ("complex1", "conjugate"), "arg" => ("complex1", "argument"),
    "ident" => ("fns1", "identity"), "inverse" => ("fns1", "inverse"),
    "compose" => ("fns1", "left_compose"),
    "mean" => ("s_data1", "mean"), "median" => ("s_data1", "median"),
    "mode" => ("s_data1", "mode"), "sdev" => ("s_data1", "sdev"),
    "variance" => ("s_data1", "variance"),
    "vector" => ("linalg2", "vector"), "matrix" => ("linalg2", "matrix"),
    "matrixrow" => ("linalg2", "matrixrow"),
    "list" => ("list1", "list"), "set" => ("set1", "set")
)

# F.4 "Container markup". These five are *also* operator names — `<set/>` may
# stand in applicant position — but they are normally written with their members
# as children, and F.4 rewrites that form into an application of the same
# symbol. They were in the table above and nowhere else, so the container form
# fell through to "unhandled element": reachable only the way nobody writes one.
#
# The value is the attribute that selects a different symbol, and the symbols it
# selects. An attribute value not listed is refused rather than dropped, because
# dropping `type="multiset"` silently turns a multiset into a set.
const _F_CONTAINERS = Dict{String, Tuple{String, Dict{String, Tuple{String, String}}}}(
    "set" => ("type", Dict("set" => ("set1", "set"),
        "multiset" => ("multiset1", "multiset"))),
    "list" => ("order", Dict{String, Tuple{String, String}}()),
    "vector" => ("", Dict{String, Tuple{String, String}}()),
    "matrix" => ("", Dict{String, Tuple{String, String}}()),
    "matrixrow" => ("", Dict{String, Tuple{String, String}}())
)

for t in ("sin", "cos", "tan", "sec", "csc", "cot",
    "sinh", "cosh", "tanh", "sech", "csch", "coth")
    _F_OPERATORS[t] = ("transc1", t)
    _F_OPERATORS["arc" * t] = ("transc1", "arc" * t)
end

# F.7.1 "Rewrite: cn constant — An expression of the form <cn type="constant">c</cn>
# has the Strict Content MathML equivalent <csymbol cd="nums1">c2</csymbol>",
# and the empty operator elements that denote the same constants.
const _F_CONSTANTS = Dict{String, Tuple{String, String}}(
    "pi" => ("nums1", "pi"),
    "exponentiale" => ("nums1", "e"),
    "imaginaryi" => ("nums1", "i"),
    "notanumber" => ("nums1", "NaN"),
    "infinity" => ("nums1", "infinity"),
    "true" => ("logic1", "true"),
    "false" => ("logic1", "false"),
    "emptyset" => ("set1", "emptyset"),
    "eulergamma" => ("nums1", "gamma"),
    # The characters MathML uses for the same constants inside <cn type="constant">.
    "π" => ("nums1", "pi"), "ⅇ" => ("nums1", "e"), "ⅈ" => ("nums1", "i"),
    "NaN" => ("nums1", "NaN"), "∞" => ("nums1", "infinity"),
    "γ" => ("nums1", "gamma"), "true" => ("logic1", "true")
)

# F.7.1 "The symbol used in the result depends on the type attribute according to
# the following table" — for a `cn` with `sep` children.
const _F_SEP_TYPES = Dict{String, Tuple{String, String}}(
    "rational" => ("nums1", "rational"),
    "complex-cartesian" => ("nums1", "complex_cartesian"),
    "complex-polar" => ("nums1", "complex_polar"),
    "e-notation" => ("nums1", "bigfloat")
)

# The sections this transformation does not implement, named so that an input
# needing one is refused with the reason rather than mis-transformed.
const _F_UNIMPLEMENTED = Dict{String, String}(
    "degree" => "F.2, idiomatic qualifiers",
    "lowlimit" => "F.2, idiomatic qualifiers",
    "uplimit" => "F.2, idiomatic qualifiers",
    "condition" => "F.3, rewrite to domainofapplication",
    "domainofapplication" => "F.3, rewrite to domainofapplication",
    "momentabout" => "F.2.7, moments",
    "logbase" => "F.2.6, logarithms",
    "interval" => "F.4, container markup",
    "int" => "F.2.2, integrals",
    "diff" => "F.2.1, derivatives",
    "partialdiff" => "F.2.1, derivatives",
    "limit" => "F.2.3, limits",
    "moment" => "F.2.7, moments",
    "forall" => "F.5.2, quantifiers",
    "exists" => "F.5.2, quantifiers"
)

_f_symbol(entry::Tuple{String, String}) = OMSymbol(entry[1], entry[2])

# Whether this frame stands where an `<apply>`'s operator goes.
function _f_is_applicant(f::_MMLFrame)
    parent = f.parent
    return parent !== nothing && parent.tag == "apply" && isempty(parent.children)
end

"""
    OpenMath.appendix_f_operators() -> Dict{String,Tuple{String,String}}

The element-to-symbol table of MathML 4 Appendix F §F.8, as this package
implements it: a non-strict operator element name mapped to the
`(cd, name)` of the Content Dictionary symbol it becomes.
"""
appendix_f_operators() = copy(_F_OPERATORS)

# The elements `strict = false` additionally accepts. `bvar` is not here because
# the strict reader already has it: it is legitimate inside a binder and only its
# use as a *qualifier* on an `apply` belongs to F.2, which is detected there.
const _F_EXTRA_ELEMENTS = Set{String}(vcat(
    collect(keys(_F_OPERATORS)), collect(keys(_F_CONSTANTS)),
    collect(keys(_F_UNIMPLEMENTED)),
    ["lambda", "piecewise", "piece", "otherwise", "sep"]))

# A marker written into a `cn`'s text where a `<sep/>` stood. F.7.1 splits the
# content on them, and no numeric lexical form can contain a NUL.
const _F_SEP = '\0'

# Returned when Appendix F has nothing to say about an element, so the strict
# builder should handle it unchanged. A sentinel rather than `nothing`, because
# `nothing` means "this element produced no node" — which `<sep/>` does.
struct _FHandled end
const _F_HANDLED = _FHandled()

# The transformation proper, applied before the strict builder sees the frame.
function _f_build(f::_MMLFrame)
    t = f.tag

    # F.8 "Rewrite: element". An operator element in applicant position is the
    # symbol it names; the same element standing alone is that symbol too — for
    # an operator. For a *container* it is not: `<set/>` heading an `apply` is
    # the symbol, and `<set/>` on its own is the empty set. So the container
    # elements are excluded here unless they are in applicant position, which is
    # exactly "first child of an `apply`" and is knowable because the parent's
    # earlier children are already built by the time this runs.
    if haskey(_F_OPERATORS, t) && isempty(f.children) && isempty(strip(_mml_text(f))) &&
       (!haskey(_F_CONTAINERS, t) || _f_is_applicant(f))
        return _f_symbol(_F_OPERATORS[t])
    end
    haskey(_F_CONSTANTS, t) && return _f_symbol(_F_CONSTANTS[t])

    # F.7.1. `<sep/>` marks a boundary in the containing `<cn>`'s content.
    if t == "sep"
        f.parent === nothing && _mmlerr(f, "<sep/> outside a <cn>")
        buf = f.parent.text
        buf === nothing && _mmlerr(f, "<sep/> is only meaningful inside <cn>")
        write(buf, _F_SEP)
        return nothing
    end

    t == "cn" && return _f_cn(f)

    # F.4 "Container markup" — `<set>1 2</set>` is `set1#set(1, 2)`.
    if haskey(_F_CONTAINERS, t)
        attribute, choices = _F_CONTAINERS[t]
        entry = _F_OPERATORS[t]
        value = attribute == "" ? nothing : _mml_attribute(f, attribute)
        if value !== nothing
            chosen = get(choices, value, nothing)
            chosen === nothing && _mmlerr(f,
                "<$(t) $(attribute)=$(repr(value))> has no symbol in Appendix F: " *
                "OpenMath has nothing that means it, and dropping the attribute " *
                "would silently change what the element denotes")
            entry = chosen
        end
        kids = OMNode[]
        for c in f.children
            c isa OMNode || _mmlerr(f, "<$(t)> may not contain $(typeof(c))")
            push!(kids, c)
        end
        return OMApplication(_f_symbol(entry), kids; id = _mml_attribute(f, "id"))
    end

    # F.4.3 "Lambda expressions" — `<lambda>` is the non-strict spelling of a
    # `<bind>` whose binder is `fns1#lambda`.
    if t == "lambda"
        vars = OMBoundVariable[]
        body = nothing
        for c in f.children
            if c isa _MMLBoundVariable
                push!(vars, c.variable)
            elseif body === nothing
                body = c
            else
                _mmlerr(f, "<lambda> takes bound variables and one body")
            end
        end
        isempty(vars) && _mmlerr(f, "<lambda> needs at least one <bvar>")
        body === nothing && _mmlerr(f, "<lambda> has no body")
        body isa OMNode || _mmlerr(f, "the body of <lambda> must be an object")
        return OMBinding(_f_symbol(("fns1", "lambda")), vars, body;
            id = _mml_attribute(f, "id"))
    end

    # F.4.4 "Piecewise functions".
    if t == "piece" || t == "otherwise" || t == "piecewise"
        kids = OMNode[]
        for c in f.children
            c isa OMNode || _mmlerr(f, "<$(t)> may not contain $(typeof(c))")
            push!(kids, c)
        end
        t == "piece" && length(kids) == 2 ||
            t != "piece" || _mmlerr(f, "<piece> takes a value and a condition")
        t == "otherwise" && length(kids) == 1 ||
            t != "otherwise" || _mmlerr(f, "<otherwise> takes one value")
        return OMApplication(_f_symbol(("piece1", t)), kids;
            id = _mml_attribute(f, "id"))
    end

    if t == "apply"
        # F.2 — a `<bvar>` directly inside an `<apply>` is an idiomatic qualifier.
        for c in f.children
            c isa _MMLBoundVariable && _mmlerr(f,
                "a <bvar> qualifier on <apply> needs MathML 4 Appendix " *
                "F.2, idiomatic qualifiers, which this package does not implement")
        end
        head = isempty(f.children) ? nothing : f.children[1]
        # F.8.1 "Rewrite the minus operator — The choice of symbol for the minus
        # operator depends on the number of the arguments."
        if length(f.children) == 2 && head isa OMSymbol &&
           head.cd == "arith1" && head.name == "minus"
            f.children[1] = OMSymbol("arith1", "unary_minus")
        end
        # F.2.5 "Roots", degenerate case. `arith1#root` takes the radicand and
        # the degree; `<root/>` without a `<degree>` qualifier is the square
        # root, so the 2 has to be supplied. The qualifier form belongs to F.2
        # and is refused by `<degree>` being unimplemented, so this only ever
        # fires where the answer is not a guess.
        if length(f.children) == 2 && head isa OMSymbol &&
           head.cd == "arith1" && head.name == "root"
            push!(f.children, OMInteger(2))
        end
        # F.2.6 "Logarithms", degenerate case. `transc1#log` takes the base and
        # the argument — the CD's own FMP reads `log(a, c) = b` when `a^b = c` —
        # and MathML 4 §4.3 makes a `<log/>` without a `<logbase>` base 10. So
        # the 10 is supplied, for the same reason and with the same safeguard as
        # the root above: `<logbase>` is unimplemented, so the qualifier form is
        # refused before this can fire on it.
        if length(f.children) == 2 && head isa OMSymbol &&
           head.cd == "transc1" && head.name == "log"
            insert!(f.children, 2, OMInteger(10))
        end
    end

    return _F_HANDLED
end

# F.7.1 and F.9.1, for `cn`.
function _f_cn(f::_MMLFrame)
    kind = _mml_attribute(f, "type")
    base = _mml_attribute(f, "base")
    text = String(strip(_mml_text(f)))
    id = _mml_attribute(f, "id")

    # "Rewrite: cn sep". The symbol depends on the type attribute.
    if occursin(_F_SEP, text)
        parts = String.(strip.(split(text, _F_SEP)))
        entry = get(_F_SEP_TYPES, kind === nothing ? "" : kind, nothing)
        entry === nothing && _mmlerr(f,
            "<cn type=$(repr(kind))> with <sep/> has no symbol in Appendix F's " *
            "table; a system-dependent choice is required and this package " *
            "does not make one")
        args = OMNode[_f_integer(f, p, base) for p in parts]
        # "In the case of bigfloat the symbol takes three arguments,
        #  <cn type="integer">10</cn> should be inserted as the second argument."
        entry == ("nums1", "bigfloat") && length(args) == 2 &&
            (args = OMNode[args[1], OMInteger(10), args[2]])
        return OMApplication(_f_symbol(entry), args; id = id)
    end

    # "Rewrite: cn constant".
    if kind == "constant"
        entry = get(_F_CONSTANTS, text, nothing)
        entry === nothing &&
            _mmlerr(f, "<cn type=\"constant\"> $(repr(text)) is not in the table " *
                       "of Appendix F §F.7.1")
        return _f_symbol(entry)
    end

    # "Rewrite: cn based_integer. A cn element with a base attribute other than
    #  10 is rewritten as follows. (A base attribute with value 10 is simply
    #  removed.)"
    if base !== nothing && base != "10"
        b = tryparse(Int, base)
        b === nothing && _mmlerr(f, "<cn base=$(repr(base))> is not a number")
        head = (kind === nothing || kind == "integer") &&
               all(c -> isletter(c) || isdigit(c) || isspace(c), text) ?
               "based_integer" : "based_float"
        return OMApplication(_f_symbol(("nums1", head)),
            OMNode[OMInteger(b), OMString(text)]; id = id)
    end

    # F.9.1. Strict `cn` needs a type; non-strict defaults to "real", and a value
    # written as an integer is an integer.
    if kind === nothing
        v = tryparse(BigInt, text)
        v === nothing || return OMInteger(v; id = id)
        d = tryparse(Float64, text)
        d === nothing && _mmlerr(f, "<cn> content $(repr(text)) is not a number")
        return OMFloat(d; id = id)
    end
    if kind == "real" || kind == "double"
        d = tryparse(Float64, text)
        d === nothing && _mmlerr(f, "<cn type=$(repr(kind))> content $(repr(text)) " *
                   "is not a number")
        return OMFloat(d; id = id)
    end
    return _F_HANDLED
end

function _f_integer(f::_MMLFrame, text::AbstractString, base)
    b = base === nothing ? 10 : something(tryparse(Int, base), 10)
    v = tryparse(BigInt, text; base = b)
    v === nothing && _mmlerr(f, "$(repr(String(text))) is not a base-$(b) integer")
    return OMInteger(v)
end
