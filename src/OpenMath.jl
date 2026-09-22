# SPDX-License-Identifier: MIT

"""
    OpenMath

A Julia implementation of the [OpenMath 2.0](https://openmath.org/) standard: an
object model for the *semantics* of mathematical objects, and readers and writers
for the official encodings.

Phase 1 provides the object model, validation and the normalisation passes. The
four endorsed encodings — XML, JSON, Strict Content MathML and binary — are all
implemented; see `ROADMAP.md` for what remains.

# Examples
```jldoctest
julia> using OpenMath

julia> e = OMS"arith1#plus"(OMInteger(1), OMVariable("x"))
OMA(OMS(arith1#plus), OMI(1), OMV(x))

julia> isvalid_openmath(e)
true

julia> canonicalize(e).applicant.cdbase
"http://www.openmath.org/cd"
```
"""
module OpenMath

include("errors.jl")
include("limits.jl")
include("names.jl")
include("types.jl")
include("traversal.jl")
include("equality.jl")
include("validate.jl")
include("passes.jl")
include("show.jl")
include("interface.jl")
include("bytes.jl")
include("base64.jl")
include("recover.jl")
# Decision D1 is re-opened (docs/src/design/xml-backend.md): `XML.jl` at
# `wellformed = :strict` now refuses an undeclared entity reference, which was
# the one argument for owning a tokenizer. Both backends present the same event
# surface, so the three readers built on it are identical either way and a
# comparison measures the tokenizer alone. `just xml-backend own|xmljl` switches.
include("xml/backend.jl")

include("xml/qname.jl")
if XML_BACKEND === :own
    include("xml/tokenizer.jl")
elseif XML_BACKEND === :xmljl
    include("xml/tokenizer_xmljl.jl")
else
    error("XML_BACKEND must be :own or :xmljl, got $(repr(XML_BACKEND))")
end
include("xml/reader.jl")
include("xml/writer.jl")
include("json/scanner.jl")
include("json/reader.jl")
include("json/writer.jl")
include("mathml/writer.jl")
include("mathml/reader.jl")
# After the reader: Appendix F dispatches on its frame type.
include("mathml/appendix_f.jl")
include("binary/tokens.jl")
include("binary/writer.jl")
include("binary/reader.jl")
include("phrasebook/core.jl")
include("phrasebook/base.jl")
include("cd/parser.jl")
include("cd/registry.jl")
include("api.jl")
include("precompile.jl")

# Constants
export CD_BASE, XML_NS

# Object model
export OMNode, OMLeaf, OMComposite, OMOrForeign
export OMInteger, OMFloat, OMString, OMBytes, OMVariable, OMSymbol
export OMApplication, OMBinding, OMError, OMAttribution, OMForeign, OMReference
export OMAttributePair, OMBoundVariable, OMObject
export @OMS_str, @om_str, @omxml_str, @omjson_str

# Traversal
export kind, children, walk, collect_nodes, count_nodes, depth, map_openmath

# Equality
export isequal_with_ids

# Validation
export validate, isvalid_openmath

# Passes
export resolve_cdbase, minimize_cdbase, collapse_attributions
export expand_references, share_structure, strip_ids, canonicalize
export isinternal, reference_target

# Limits
export OMLimits, limits, with_limits

# Conversion
export to_openmath, from_openmath

# Phrasebooks
export Phrasebook, define!, define_variable!, define_leaf!, interpret, express
export symbols, base_vocabulary, symbolics_phrasebook
export with_phrasebook, current_phrasebook

# Encodings
export read_xml, write_xml, read_json, write_json
export read_mathml, write_mathml, MATHML_NS
export read_binary, write_binary

# Content Dictionaries
export ContentDictionary, CDDefinition, STSSignatures, CDRegistry
export lookup, describe, signature, arity, validate_against_cds
export load_cd_directory, load_cd_directory!, load_sts_directory!

end # module
