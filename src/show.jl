# SPDX-License-Identifier: MIT
#
# The compact functional rendering (REQ-API-008, text/plain half). The encoding
# MIMEs `application/openmath+xml` and `+json` arrive with Phases 2 and 3.

Base.show(io::IO, x::OMInteger) = print(io, "OMI(", x.value, ")")
Base.show(io::IO, x::OMFloat) = print(io, "OMF(", x.value, ")")
Base.show(io::IO, x::OMString) = print(io, "OMSTR(", repr(x.value), ")")
Base.show(io::IO, x::OMVariable) = print(io, "OMV(", x.name, ")")
Base.show(io::IO, x::OMReference) = print(io, "OMR(", x.href, ")")

function Base.show(io::IO, x::OMBytes)
    n = length(x.value)
    print(io, "OMB(", n, n == 1 ? " byte)" : " bytes)")
    return nothing
end

function Base.show(io::IO, x::OMSymbol)
    print(io, "OMS(")
    x.cdbase === nothing || print(io, x.cdbase, "#")
    print(io, x.cd, "#", x.name, ")")
    return nothing
end

function Base.show(io::IO, x::OMForeign)
    print(io, "OMFOREIGN(")
    x.encoding === nothing || print(io, x.encoding, ", ")
    print(io, repr(x.value), ")")
    return nothing
end

function Base.show(io::IO, x::OMApplication)
    print(io, "OMA(")
    _show_cdbase(io, x.cdbase)
    show(io, x.applicant)
    for a in x.arguments
        print(io, ", ")
        show(io, a)
    end
    print(io, ")")
    return nothing
end

function Base.show(io::IO, x::OMBinding)
    print(io, "OMBIND(")
    _show_cdbase(io, x.cdbase)
    show(io, x.binder)
    print(io, ", [", join((v.name for v in x.variables), ", "), "], ")
    show(io, x.body)
    print(io, ")")
    return nothing
end

function Base.show(io::IO, x::OMError)
    print(io, "OME(")
    _show_cdbase(io, x.cdbase)
    show(io, x.head)
    for a in x.arguments
        print(io, ", ")
        show(io, a)
    end
    print(io, ")")
    return nothing
end

function Base.show(io::IO, x::OMAttribution)
    print(io, "OMATTR(")
    _show_cdbase(io, x.cdbase)
    show(io, x.object)
    for p in x.attributes
        print(io, ", ")
        show(io, p.key)
        print(io, "=")
        show(io, p.value)
    end
    print(io, ")")
    return nothing
end

function Base.show(io::IO, p::OMAttributePair)
    (show(io, p.key); print(io, "="); show(io, p.value); nothing)
end

function Base.show(io::IO, x::OMObject)
    print(io, "OMOBJ(")
    _show_cdbase(io, x.cdbase)
    show(io, x.object)
    print(io, ")")
    return nothing
end

_show_cdbase(io::IO, ::Nothing) = nothing
_show_cdbase(io::IO, b::String) = (print(io, "cdbase=", b, ", "); nothing)
