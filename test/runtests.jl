# SPDX-License-Identifier: MIT
using TestItemRunner
using OpenMath: OpenMath

# Tag selection is driven by the harness (`just verify --tier …`).
# OPENMATH_TEST_TAGS is a comma-separated list; empty means "everything but :slow".
const _RAW = get(ENV, "OPENMATH_TEST_TAGS", "")
const _TAGS = Symbol.(filter(!isempty, strip.(split(_RAW, ','))))

# Items tagged `:own_tokenizer` test the hand-written tokenizer's internals and
# are meaningless when the `XML.jl` backend is selected (decision D1).
const _OWN = OpenMath.XML_BACKEND === :own
_backend_ok(ti) = _OWN || !(:own_tokenizer in ti.tags)

if isempty(_TAGS)
    @run_package_tests filter = ti -> !(:slow in ti.tags) && _backend_ok(ti)
else
    @run_package_tests filter = ti -> any(t -> t in ti.tags, _TAGS) &&
                                      (:slow in _TAGS || !(:slow in ti.tags)) &&
                                      _backend_ok(ti)
end
