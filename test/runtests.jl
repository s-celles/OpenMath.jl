# SPDX-License-Identifier: MIT
using TestItemRunner

# Tag selection is driven by the harness (`just verify --tier …`).
# OPENMATH_TEST_TAGS is a comma-separated list; empty means "everything but :slow".
const _RAW = get(ENV, "OPENMATH_TEST_TAGS", "")
const _TAGS = Symbol.(filter(!isempty, strip.(split(_RAW, ','))))

if isempty(_TAGS)
    @run_package_tests filter = ti -> !(:slow in ti.tags)
else
    @run_package_tests filter = ti -> any(t -> t in ti.tags, _TAGS) &&
                                      (:slow in _TAGS || !(:slow in ti.tags))
end
