# SPDX-License-Identifier: MIT
#
# Which XML tokenizer the package is built with (decision D1, re-opened).
#
#   :own     the hand-written pull tokenizer, src/xml/tokenizer.jl
#   :xmljl   XML.jl FlatNode at wellformed = :strict, src/xml/tokenizer_xmljl.jl
#
# A literal in a file, rewritten by `just xml-backend NAME`, rather than a
# `Preferences` entry. A preference is the idiomatic mechanism and it was tried:
# it needs a dependency, and JET's virtual module cannot resolve one, so the
# whole package became unanalysable — no `XML_BACKEND`, no tokenizer included,
# every name in the readers undefined. This is a two-way door for one
# experiment, and it does not deserve to cost the static analysis of the readers.
#
# Whichever backend survives, this file goes away with the other.
const XML_BACKEND = :own
