# SPDX-License-Identifier: MIT
#
# Properties every encoding must share.
#
# This file exists because of a failure mode the harness had no place for. The
# conformance driver checks that the four encodings **agree about objects** —
# read one, write another, compare. It has never checked that they share
# *implementation* properties, and twice in one session a defect survived
# precisely there:
#
#   * The XML reader's eagerly-built error paths were fixed in Phase 2 after
#     causing an out-of-memory at 200 000 levels (E1 №1). The JSON reader had the
#     same defect, and neither the fix nor the test was propagated. It survived
#     two more phases.
#
#   * The JSON reader builds its tree by recursion where the other three use
#     explicit stacks, so it alone can reach a `StackOverflowError`.
#
# Agreement about objects cannot catch either: both readers produce the same
# object, right up to the point where one of them stops producing anything.
#
# So anything of the form "every encoding must…" belongs here, parametrised over
# all four, where a fix applied to one is visibly absent from the others.

const _ALL_ENCODINGS = (:xml, :json, :mathml, :binary)

@testitem "cross-encoding: depth never escapes the OpenMathError family (REQ-SEC-002)" tags = [
    :unit, :slow] begin
    using OpenMath

    n = 40_000
    nested = foldl((acc, _) -> OMApplication(OMVariable("f"), [acc]), 1:n;
        init = OMInteger(0))
    doc = OMObject(nested)

    encode = Dict(:xml => OpenMath.xml, :json => OpenMath.json,
        :mathml => OpenMath.mathml, :binary => o -> String(OpenMath.binary(o)))
    decode = Dict(
        :xml => s -> OpenMath.parse(s; format = :xml),
        :json => s -> OpenMath.parse(s; format = :json),
        :mathml => s -> OpenMath.parse(s; format = :mathml),
        :binary => s -> OpenMath.parse(Vector{UInt8}(codeunits(s)); format = :binary))

    # `limited` is a fact about the implementations, not a licence: an encoding
    # may refuse a depth, and must refuse it with an `OpenMathError`. Moving one
    # into or out of this set is a deliberate edit, which is the point — the JSON
    # reader's recursion was invisible until something listed it, and the set is
    # empty again now that its builder runs on a stack.
    limited = Set{Symbol}()

    for e in (:xml, :json, :mathml, :binary)
        outcome = try
            src = with_limits(OMLimits(; max_depth = 10n)) do
                encode[e](doc)
            end
            back = with_limits(OMLimits(; max_depth = 10n)) do
                decode[e](src)
            end
            depth(back.object) == n + 1 ? :ok : :wrong
        catch err
            err isa OpenMath.OpenMathError ? :refused : :escaped
        end
        @test "$(e): $(e in limited ? "refused" : "ok")" == "$(e): $(outcome)"
    end
end

@testitem "cross-encoding: a truncated document is an OpenMathError, whichever it is" tags = [
    :unit] begin
    using OpenMath
    obj = OMObject(OMS"arith1#plus"(OMInteger(big(2)^90), OMFloat(NaN),
        OMString("a<b&c λ"), OMVariable("x")))
    writers = (:xml => OpenMath.xml, :json => OpenMath.json,
        :mathml => OpenMath.mathml, :binary => o -> String(OpenMath.binary(o)))

    for (name, write) in writers
        src = write(obj)
        units = codeunits(src)
        for cut in 0:max(1, length(units) ÷ 17):(length(units) - 1)
            piece = String(units[1:cut])
            e = try
                name === :binary ?
                OpenMath.parse(Vector{UInt8}(codeunits(piece)); format = :binary) :
                OpenMath.parse(piece; format = name)
                nothing
            catch err
                err
            end
            # A truncated document may not parse, and if it does not, the failure
            # belongs to the family the API promises (REQ-SEC-001).
            @test e === nothing || e isa OpenMath.OpenMathError
        end
    end
end

@testitem "cross-encoding: every writer is byte-idempotent" tags = [:unit] begin
    using OpenMath
    # Stated once, over all four, rather than four times in four files where the
    # fourth can quietly be forgotten.
    objects = [OMInteger(big(2)^200), OMFloat(NaN), OMFloat(-0.0), OMString("λ<&"),
        OMBytes(UInt8[0, 255]), OMVariable("λ"),
        OMS"arith1#plus"(OMInteger(1), OMVariable("x")),
        OMBinding(OMS"fns1#lambda", [OMBoundVariable("x")], OMVariable("x")),
        OMAttribution([OMAttributePair(OMS"ecc#type", OMString("R"))],
            OMVariable("x"))]
    pairs = (
        (:xml, OpenMath.xml, s -> OpenMath.parse(s; format = :xml)),
        (:json, OpenMath.json, s -> OpenMath.parse(s; format = :json)),
        (:mathml, OpenMath.mathml, s -> OpenMath.parse(s; format = :mathml)),
        (:binary, o -> String(OpenMath.binary(o)),
            s -> OpenMath.parse(Vector{UInt8}(codeunits(s)); format = :binary)))

    for obj in objects, (name, write, read) in pairs

        once = write(OMObject(obj))
        @test "$(name): stable" ==
              "$(name): $(once == write(read(once)) ? "stable" : "changed")"
    end
end

@testitem "security: parsing interns nothing; conversion does (REQ-SEC-001)" tags = [
    :unit] begin
    using OpenMath
    # SECURITY.md lists "unbounded interning of attacker-controlled names" as a
    # vulnerability, and the object model honours that: every name is a `String`,
    # because Julia never garbage-collects an interned `Symbol`.
    #
    # `from_openmath` is where that stops being true, and it is worth a test
    # rather than a sentence. It is not a parser entry point — a caller invokes it
    # deliberately — but a service that parses untrusted OpenMath and converts it
    # is the obvious thing to write, and it interns every distinct variable name
    # it is sent.
    name = "attacker_controlled_" * string(hash(time_ns()); base = 16)
    doc = """{"kind":"OMOBJ","object":{"kind":"OMV","name":"$(name)"}}"""

    parsed = OpenMath.parse(doc; format = :json).object
    @test parsed isa OMVariable
    @test parsed.name isa String                 # parsing alone interns nothing

    @test from_openmath(parsed) isa Symbol       # conversion does

    # And the remedy is one line, which is the reason `define_variable!` exists
    # and the reason this is a caveat rather than a defect.
    safe = Phrasebook()
    define_variable!(safe, identity)
    @test interpret(safe, parsed) === parsed.name
    @test interpret(safe, parsed) isa String
end
