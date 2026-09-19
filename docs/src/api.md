# API reference

```@meta
CurrentModule = OpenMath
```

## Module

```@docs
OpenMath
```

## Object model

```@docs
OMNode
OMLeaf
OMComposite
OMOrForeign
OMInteger
OMFloat
OMString
OMBytes
OMVariable
OMSymbol
OMApplication
OMBinding
OMError
OMAttribution
OMForeign
OMReference
isinternal
reference_target
OMAttributePair
OMBoundVariable
OMObject
@OMS_str
@om_str
@omxml_str
@omjson_str
CD_BASE
XML_NS
```

## Traversal

```@docs
kind
children
walk
collect_nodes
count_nodes
depth
map_openmath
```

## Equality

```@docs
isequal_with_ids
```

## Validation

```@docs
validate
isvalid_openmath
OMValidationIssue
```

## Normalisation passes

```@docs
resolve_cdbase
minimize_cdbase
collapse_attributions
expand_references
share_structure
strip_ids
canonicalize
```

## Limits

```@docs
OMLimits
limits
with_limits
```

## Conversion

```@docs
to_openmath
from_openmath
```

## Encodings

```@docs
OpenMath.parse
OpenMath.parsefile
OpenMath.sniff_format
read_xml
OpenMath.xml
write_xml
read_json
OpenMath.json
write_json
read_mathml
OpenMath.mathml
write_mathml
MATHML_NS
read_binary
OpenMath.binary
write_binary
```

## Phrasebooks

```@docs
Phrasebook
define!
define_variable!
define_leaf!
interpret
express
symbols
base_vocabulary
with_phrasebook
current_phrasebook
OpenMath.symbolics_phrasebook
```

## Content Dictionaries

```@docs
ContentDictionary
CDDefinition
STSSignatures
CDRegistry
OpenMath.parse_cd
OpenMath.parse_sts
OpenMath.sts_arity
OpenMath.register!
OpenMath.isempty_registry
load_cd_directory
load_sts_directory!
lookup
describe
signature
arity
validate_against_cds
```

## Errors

```@docs
OpenMathError
OpenMathNameError
OpenMathLimitError
OpenMathReferenceError
OpenMathConversionError
OpenMathParseError
```

## Names

```@docs
isvalidname
isvalidcdbase
checkname
is_name_start_char
is_name_char
```
