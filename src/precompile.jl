# SPDX-License-Identifier: MIT
#
# The precompilation workload (roadmap Phase 8).
#
# This file exists because of a measurement, not a hunch. Before it:
#
#   bare julia                 0.121 s
#   using OpenMath             0.147 s   ← loading the package costs 26 ms
#   + one XML parse            4.132 s   ← four seconds of first-call compilation
#
# Loading was never the problem. The whole cost was inference and code generation
# on the first `parse`, paid again by every process, which for a script that
# reads one document is the entire runtime. That is what `PrecompileTools` caches,
# and it is the only reason this package has a runtime dependency at all —
# `PrecompileTools` is pure Julia with no binary artifact, so REQ-PRJ-002 holds.
#
# The workload exercises one document through every reader, every writer and the
# normalisation passes. It is deliberately small: precompiling a wide surface
# costs build time and cache size for paths most callers never touch, and the
# measurement above says the win is concentrated in the first parse.

using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    # Built inside the setup block so that constructing it is not itself timed
    # into the workload, and so nothing here runs at load time.
    obj = OMObject(OMApplication(OMSymbol("arith1", "plus"),
        OMNode[OMInteger(1), OMInteger(big(2)^80), OMFloat(1.5), OMFloat(NaN),
            OMVariable("x"), OMString("a<b&c"), OMBytes(UInt8[0x01, 0xff]),
            OMApplication(OMSymbol("transc1", "sin"), OMNode[OMVariable("y")]),
            OMBinding(OMSymbol("fns1", "lambda"),
                [OMBoundVariable("z")], OMVariable("z")),
            OMError(OMSymbol("error1", "unhandled"), OMOrForeign[OMInteger(0)]),
            OMAttribution(
                [OMAttributePair(OMSymbol("ecc", "type"),
                    OMString("R"))], OMVariable("w"))]))

    @compile_workload begin
        for (write, format) in ((xml, :xml), (json, :json), (mathml, :mathml))
            src = write(obj)
            parse(src; format = format)
            parse(src)                       # through the sniffer, as callers do
        end
        bytes = binary(obj)
        read_binary(bytes)
        parse(bytes)

        canonicalize(obj)
        validate(obj.object)
        isvalid_openmath(obj.object)
        interpret(Phrasebook(), OMApplication(OMSymbol("arith1", "plus"),
            OMNode[OMInteger(1), OMInteger(2)]))
    end
end
