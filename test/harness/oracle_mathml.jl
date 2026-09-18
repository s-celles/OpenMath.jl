# SPDX-License-Identifier: MIT
#
# The phrasebook oracle: MathML.jl (harness spec §6.5, design note
# docs/src/design/phrasebook.md).
#
# E2's rule is that an oracle's yield tracks coverage overlap, and this is the
# closest overlap available anywhere: MathML.jl maps *the same vocabulary* into
# *the same target language*. It reads the non-strict Content MathML dialect this
# package deliberately refuses, so it cannot be handed our output. The test is a
# shared *input* written twice:
#
#   one mathematical object
#      ├─ as non-strict Content MathML  →  MathML.jl  →  Symbolics expression
#      └─ as OpenMath                   →  us         →  Symbolics expression
#                                                         compare
#
# The pairs are written by hand. Neither implementation generates the other's
# input, which is what makes agreement worth anything.
#
# Since Appendix F landed there is a second, stronger comparison available: feed
# the *same* non-strict document to both. MathML.jl reads it directly; we
# transform it with Appendix F, decode it as OpenMath and interpret it with the
# Symbolics phrasebook. Two independent routes from one input to one language,
# which is as close to a real oracle as this pairing gets.
#
#   just oracle-mathml-setup
#   just oracle-mathml
#
# runs under --project=refs/mathml-env, not the test environment, so its imports
# are exempt from the declared-dependency gate in test/quality/project.jl.

using OpenMath
using Symbolics
using MathML

const NS = "http://www.w3.org/1998/Math/MathML"

# (name, non-strict Content MathML, the same object in OpenMath)
const PAIRS = Any[
    ("plus", "<apply><plus/><ci>x</ci><cn>1</cn></apply>",
        OMS"arith1#plus"(OMVariable("x"), OMInteger(1))),
    ("times", "<apply><times/><cn>2</cn><ci>x</ci></apply>",
        OMS"arith1#times"(OMInteger(2), OMVariable("x"))),
    ("minus", "<apply><minus/><ci>x</ci><ci>y</ci></apply>",
        OMS"arith1#minus"(OMVariable("x"), OMVariable("y"))),
    ("divide", "<apply><divide/><ci>x</ci><ci>y</ci></apply>",
        OMS"arith1#divide"(OMVariable("x"), OMVariable("y"))),
    ("power", "<apply><power/><ci>x</ci><cn>2</cn></apply>",
        OMS"arith1#power"(OMVariable("x"), OMInteger(2))),
    ("abs", "<apply><abs/><ci>x</ci></apply>",
        OMS"arith1#abs"(OMVariable("x"))),
    ("root", "<apply><root/><ci>x</ci></apply>",
        OMS"arith1#root"(OMVariable("x"), OMInteger(2))),
    ("sin", "<apply><sin/><ci>x</ci></apply>",
        OMS"transc1#sin"(OMVariable("x"))),
    ("cos", "<apply><cos/><ci>x</ci></apply>",
        OMS"transc1#cos"(OMVariable("x"))),
    ("tanh", "<apply><tanh/><ci>x</ci></apply>",
        OMS"transc1#tanh"(OMVariable("x"))),
    ("arctan", "<apply><arctan/><ci>x</ci></apply>",
        OMS"transc1#arctan"(OMVariable("x"))),
    ("exp", "<apply><exp/><ci>x</ci></apply>",
        OMS"transc1#exp"(OMVariable("x"))),
    ("ln", "<apply><ln/><ci>x</ci></apply>",
        OMS"transc1#ln"(OMVariable("x"))),
    ("max", "<apply><max/><ci>x</ci><ci>y</ci></apply>",
        OMS"minmax1#max"(OMVariable("x"), OMVariable("y"))),
    ("min", "<apply><min/><ci>x</ci><ci>y</ci></apply>",
        OMS"minmax1#min"(OMVariable("x"), OMVariable("y"))),
    ("floor", "<apply><floor/><ci>x</ci></apply>",
        OMS"rounding1#floor"(OMVariable("x"))),
    ("ceiling", "<apply><ceiling/><ci>x</ci></apply>",
        OMS"rounding1#ceiling"(OMVariable("x"))),
    ("nested",
        "<apply><plus/><apply><sin/><ci>x</ci></apply><apply><cos/><ci>y</ci></apply></apply>",
        OMS"arith1#plus"(OMS"transc1#sin"(OMVariable("x")),
            OMS"transc1#cos"(OMVariable("y")))),
    ("deep",
        "<apply><times/><cn>2</cn><apply><power/><apply><plus/><ci>x</ci><ci>y</ci></apply><cn>2</cn></apply></apply>",
        OMS"arith1#times"(OMInteger(2),
            OMS"arith1#power"(OMS"arith1#plus"(OMVariable("x"), OMVariable("y")),
                OMInteger(2)))),
    ("pi", "<pi/>", OMS"nums1#pi"),
    ("e", "<exponentiale/>", OMS"nums1#e")
]

wrap(body) = "<math xmlns=\"$(NS)\">$(body)</math>"

struct Disagreement
    name::String
    detail::String
end

function main(argv)
    println("\n  oracle — MathML.jl, ", length(PAIRS), " paired vectors\n")
    p = OpenMath.symbolics_phrasebook()
    findings = Disagreement[]
    agreed = 0

    for (name, mml, om) in PAIRS
        theirs = try
            only(MathML.parse_str(wrap(mml)))
        catch err
            push!(findings,
                Disagreement(name, "MathML.jl could not read it: " *
                                   first(sprint(showerror, err), 100)))
            continue
        end
        ours = try
            interpret(p, om)
        catch err
            push!(findings,
                Disagreement(name, "we could not interpret it: " *
                                   first(sprint(showerror, err), 100)))
            continue
        end
        if isequal(Symbolics.unwrap(theirs), Symbolics.unwrap(ours))
            agreed += 1
        else
            push!(findings,
                Disagreement(name, "MathML.jl gives $(theirs), we give $(ours)"))
        end
    end

    # --- the same input through both, via Appendix F --------------------------
    shared_agreed = 0
    for (name, mml, _) in PAIRS
        doc = wrap(mml)
        theirs = try
            only(MathML.parse_str(doc))
        catch err
            push!(findings,
                Disagreement(name * " (shared)",
                    "MathML.jl could not read it: " * first(sprint(showerror, err), 80)))
            continue
        end
        ours = try
            om = OpenMath.parse(doc; format = :mathml, strict = false)
            interpret(p, om.object)
        catch err
            push!(findings,
                Disagreement(name * " (shared)",
                    "Appendix F or the phrasebook refused it: " *
                    first(sprint(showerror, err), 100)))
            continue
        end
        if isequal(Symbolics.unwrap(theirs), Symbolics.unwrap(ours))
            shared_agreed += 1
        else
            push!(findings, Disagreement(name * " (shared)",
                "MathML.jl gives $(theirs), we give $(ours)"))
        end
    end

    println("  hand-written pairs          ", agreed, "/", length(PAIRS), " agree")
    println("  the same document, via F    ", shared_agreed, "/", length(PAIRS),
        " agree")
    for f in findings
        println("    ✗ ", rpad(f.name, 10), f.detail)
    end
    println()
    return isempty(findings) ? 0 : 1
end

exit(main(ARGS))
