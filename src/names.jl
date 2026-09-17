# SPDX-License-Identifier: MIT
#
# The OpenMath `Name` production (standard §2.3), which is the XML 1.0 5th edition
# `Name` production. Implemented from the character ranges in the standard.

"""
    is_name_start_char(c::AbstractChar) -> Bool

Whether `c` may begin an OpenMath `Name` (standard §2.3).
"""
function is_name_start_char(c::AbstractChar)
    return c == ':' || c == '_' ||
           ('A' <= c <= 'Z') || ('a' <= c <= 'z') ||
           ('À' <= c <= 'Ö') || ('Ø' <= c <= 'ö') ||
           ('ø' <= c <= '˿') || ('Ͱ' <= c <= 'ͽ') ||
           ('Ϳ' <= c <= '῿') || ('‌' <= c <= '‍') ||
           ('⁰' <= c <= '↏') || ('Ⰰ' <= c <= '⿯') ||
           ('、' <= c <= '퟿') || ('豈' <= c <= '﷏') ||
           ('ﷰ' <= c <= '�') || ('\U00010000' <= c <= '\U000EFFFF')
end

"""
    is_name_char(c::AbstractChar) -> Bool

Whether `c` may occur after the first character of an OpenMath `Name`.
"""
function is_name_char(c::AbstractChar)
    return is_name_start_char(c) || c == '-' || c == '.' || ('0' <= c <= '9') ||
           c == '·' || ('̀' <= c <= 'ͯ') || ('‿' <= c <= '⁀')
end

"""
    isvalidname(s::AbstractString) -> Bool

Whether `s` matches the OpenMath `Name` production.

# Examples
```jldoctest
julia> using OpenMath: isvalidname

julia> isvalidname("plus"), isvalidname("x0"), isvalidname("a-b")
(true, true, true)

julia> isvalidname("0bad"), isvalidname("a b"), isvalidname("")
(false, false, false)
```
"""
function isvalidname(s::AbstractString)
    return name_fault(s) == 0
end

# Returns 0 when `s` is a valid Name, otherwise the 1-based index of the first
# offending character — or 0-with-empty-string for the empty name, which callers
# distinguish by checking `isempty` first.
function name_fault(s::AbstractString)
    isempty(s) && return -1
    i = 1
    for c in s
        ok = i == 1 ? is_name_start_char(c) : is_name_char(c)
        ok || return i
        i += 1
    end
    return 0
end

"""
    checkname(s::AbstractString, what::AbstractString)

Raise [`OpenMathNameError`](@ref) unless `s` matches the `Name` production.
`what` names the role of the value in the error message, e.g. `"symbol name"`.
"""
function checkname(s::AbstractString, what::AbstractString)
    f = name_fault(s)
    f == 0 && return nothing
    throw(OpenMathNameError(String(s), f < 0 ? 0 : f, what))
end

"""
    isvalidcdbase(s::AbstractString) -> Bool

Whether `s` is syntactically an absolute URI, as a `cdbase` must be (REQ-VAL-007).

Only the scheme is checked in full; the remainder is rejected on whitespace. This
is deliberately syntactic — resolving a `cdbase` is a Content Dictionary concern,
not a parsing one.
"""
function isvalidcdbase(s::AbstractString)
    isempty(s) && return false
    any(isspace, s) && return false
    i = findfirst(==(':'), s)
    i === nothing && return false
    scheme = SubString(s, 1, prevind(s, i))
    isempty(scheme) && return false
    isascii(scheme) || return false
    ('a' <= first(scheme) <= 'z' || 'A' <= first(scheme) <= 'Z') || return false
    for c in scheme
        ('a' <= c <= 'z' || 'A' <= c <= 'Z' || '0' <= c <= '9' ||
         c == '+' || c == '-' || c == '.') || return false
    end
    return true
end

function checkcdbase(s::AbstractString)
    isvalidcdbase(s) || throw(OpenMathNameError(String(s), 0, "cdbase URI"))
    return nothing
end
