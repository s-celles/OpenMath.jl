# SPDX-License-Identifier: MIT
#
# Auto-persistence of shrunk counterexamples (harness spec §6.4).
#
# A property that has been falsified once will be falsified again by the same
# shape of input, but only if someone writes it down. This turns each shrunk
# counterexample into a permanent corpus item, which is the mechanism that makes
# the harness compound: the property layer explores, the corpus remembers.
#
# The design deliberately does not reach into Supposition's internals. A property
# reports each failing input as it goes; shrinking re-runs the property on ever
# smaller inputs, so the *last* failing input a property reports is its minimal
# counterexample. Keeping only the last one per property is therefore both
# correct and independent of how shrinking is implemented.

module Regression

using OpenMath

const ROOT = normpath(joinpath(@__DIR__, "..", "corpus", "regression"))

const PENDING = Dict{String, Any}()

"""
    record!(property, object)

Remember `object` as the current counterexample for `property`. Called from
inside a property, on the failing path only, so later (smaller) failures
overwrite earlier ones.
"""
function record!(property::AbstractString, object)
    PENDING[String(property)] = object
    return nothing
end

"""
    flush!() -> Vector{String}

Write every pending counterexample as a corpus item and return their names.
Existing items are left alone: the corpus is append-only, and a property that
fails the same way twice should not rewrite the fixture it already has.
"""
function flush!()
    written = String[]
    for (property, object) in sort!(collect(PENDING); by = first)
        name = _item_name(property, object)
        dir = joinpath(ROOT, name)
        isdir(dir) && continue
        _write_item(dir, property, object) && push!(written, "regression/$name")
    end
    empty!(PENDING)
    return written
end

# The name is derived from the object itself, so re-running a still-failing
# property lands on the same directory instead of accumulating near-duplicates.
function _item_name(property::AbstractString, object)
    digest = string(hash(object); base = 16, pad = 16)[1:8]
    slug = replace(lowercase(String(property)), r"[^a-z0-9]+" => "-")
    return string(strip(slug, '-'), "-", digest)
end

function _write_item(dir::AbstractString, property::AbstractString, object)
    node = object isa OMObject ? object : nothing
    document = node === nothing && object isa OMNode ? OMObject(object) : node
    document === nothing && return false      # not an object; nothing to store

    xml = try
        OpenMath.xml(document)
    catch
        # The writer itself may be what is broken. Recording the counterexample is
        # still worth doing, so fall back to the functional form in the metadata
        # and skip the encoded file rather than losing the case entirely.
        nothing
    end

    mkpath(dir)
    if xml !== nothing
        write(joinpath(dir, "object.xml"), xml * "\n")
    end
    open(joinpath(dir, "meta.toml"), "w") do io
        println(io, "source = ", repr("property $property, shrunk by Supposition"))
        println(io, "provenance = \"shrunk-counterexample\"")
        println(io, "tags = [\"regression\", ", repr(String(property)), "]")
        println(io, "strict = true")
        println(io, "skip = []")
        xml === nothing && println(io, "note = \"the writer could not encode this; ",
            "see `functional` below\"")
        println(io, "functional = ", repr(first(sprint(show, document), 400)))
    end
    return true
end

"""
    checked(f, property, object) -> Bool

Run `f(object)`, recording `object` as a counterexample when the property is
false. Use inside a `@check` body so that a falsification is remembered without
each property having to repeat the bookkeeping.
"""
function checked(f, property::AbstractString, object)
    ok = f(object)::Bool
    ok || record!(property, object)
    return ok
end

end # module
