# SPDX-License-Identifier: MIT
#
# `:recover` mode (spec §5.3): never raise on a malformed document, put an
# OpenMath error object where the unreadable part was, and keep the rest.
#
# Which error symbol took some deciding, and the obvious answer was wrong. The
# official `error` Content Dictionary defines exactly three symbols —
# `unhandled_symbol`, `unexpected_symbol` and `unsupported_CD` — and **all three
# are about a symbol**: one not present in a dictionary, one present but not
# implemented, one whose dictionary is absent. Their argument is the offending
# `OMS`. None of them describes a malformed integer or a truncated document, and
# writing one there would state something false in a vocabulary that other
# implementations read. (There is also no CD called `error1`, which is what the
# specification's own §5.3 asks for.)
#
# `moreerrors#encodingError` says precisely the right thing — "the error which is
# returned when an application detects a lexical or syntactic error. It should
# have one argument which is a string, which should explain the error that
# occurred" — at the cost of being an *experimental* dictionary rather than an
# official one. A true statement in an experimental vocabulary beats a false one
# in an official vocabulary, so that is the trade taken, and it is recorded here
# rather than left to be inferred from the code.

const RECOVERY_CD = "moreerrors"
const RECOVERY_SYMBOL = "encodingError"

"""
    recovery_error(message) -> OMError

The object `:recover` mode puts in place of something it could not read.
"""
function recovery_error(message::AbstractString)
    OMError(OMSymbol(RECOVERY_CD, RECOVERY_SYMBOL), OMOrForeign[OMString(String(message))])
end

recovery_error(err::OpenMathParseError) = recovery_error(sprint(showerror, err))

"""
    recovered_document(message) -> OMObject

A whole document standing in for one that could not be read at all — a
truncation, a tokenizer failure, or a root element that is not `<OMOBJ>`.
"""
function recovered_document(message::AbstractString)
    OMObject(recovery_error(message), "2.0", nothing, nothing,
        [String(message)])
end

# There is deliberately no `_recovering(f, mode)` helper taking a `do` block.
# It read well and allocated the closure on *every node*, including in
# `:strict`, where it does nothing at all — re-recording the benchmark baseline
# showed +8.5 % allocations in the JSON reader from exactly that. The readers
# branch on `mode` inline, or call a named function, instead.

# Wrap a reader so that `:recover` returns a document rather than raising.
#
# `OpenMathLimitError` is deliberately **not** caught. Limits exist to stop work
# on hostile input (REQ-SEC-002); turning a depth bomb into an error node and
# carrying on would mean the attacker still gets the work done. `:recover` is
# for documents that are broken, not for documents that are attacking you.
function with_recovery(f, mode::Symbol)
    mode === :recover || return f()
    try
        return f()
    catch err
        err isa OpenMathParseError || rethrow()
        return recovered_document(sprint(showerror, err))
    end
end
