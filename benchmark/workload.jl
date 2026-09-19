# SPDX-License-Identifier: MIT
#
# The benchmark workload, defined once.
#
# `just bench` (test/harness/bench.jl) records the baseline from it, and
# `benchmark/benchmarks.jl` hands the same thing to AirspeedVelocity for the
# pull-request comparison. Two definitions of "the document we measure" would
# drift, and then the two numbers would not be about the same thing.

using OpenMath

"""
    specimen(n) -> OMObject

A document with the shape real ones have: nesting, symbols, numbers of every
awkward kind, a string that needs escaping, and an integer too large for `Int64`.
"""
function specimen(n::Int)
    leaf(i) = OMS"arith1#plus"(OMInteger(i), OMFloat(i / 7),
        OMVariable("x$(i)"), OMString("a<b&c λ"))
    body = foldl((acc, i) -> OMS"arith1#times"(acc, leaf(i)), 1:n;
        init = OMInteger(big(2)^200))
    return OMObject(body)
end

# (name, write, read). Binary is held as a `String` like the rest so the harness
# needs no special case for the one encoding that is not text.
const ENCODINGS = (
    (:xml, OpenMath.xml, s -> OpenMath.parse(s; format = :xml)),
    (:json, OpenMath.json, s -> OpenMath.parse(s; format = :json)),
    (:mathml, OpenMath.mathml, s -> OpenMath.parse(s; format = :mathml)),
    (:binary, obj -> String(OpenMath.binary(obj)),
        s -> OpenMath.parse(Vector{UInt8}(codeunits(s)); format = :binary))
)
