# SPDX-License-Identifier: MIT
#
# runs under --project=refs/invalidations-env, set up by `just invalidations-setup`
#
# The invalidation audit (roadmap Phase 8).
#
# Loading a package can invalidate compiled code that other packages already
# hold, and every invalidated method instance is latency a downstream user pays
# without asking. `SnoopCompile` measures it; this turns the measurement into a
# gate, because `.github/workflows/Invalidations.yml` printed two numbers and
# compared them with a human eye, which is the same as not comparing them.
#
# Opt-in, like the oracles: `SnoopCompile` is a large dependency with a compiled
# artefact, and the package under test has one dependency on purpose.

using SnoopCompileCore
invalidations = @snoop_invalidations using OpenMath
using SnoopCompile
using TOML

const BASELINE = normpath(joinpath(@__DIR__, "baseline.toml"))

# The ceiling is recorded rather than inferred, so raising it is an edit someone
# makes on purpose and a reviewer can see.
const RECORDED = let b = TOML.parsefile(BASELINE)
    get(get(b, "invalidations", Dict{String, Any}()), "total", nothing)
end

trees = invalidation_trees(invalidations)
total = length(uinvalidated(invalidations))

# The question that matters is not "how many", it is "whose". An invalidation
# caused by a method *we* insert is ours to fix — usually a signature wider than
# the argument it means, or an outright piracy. One caused by two stdlibs
# meeting on the way in is not, and conflating the two would make the gate
# unactionable.
ours = filter(t -> occursin("OpenMath", string(t.method.module)), trees)
foreign = filter(t -> !occursin("OpenMath", string(t.method.module)), trees)

println()
println("  invalidations — loading OpenMath")
println()
println("  method instances invalidated   ", total,
    RECORDED === nothing ? "" : "   (recorded: $(RECORDED))")
println("  trees whose method is ours     ", length(ours))
println("  trees from elsewhere           ", length(foreign))
println()

for t in foreign
    println("  · ", t.method.module, ": ", t.method.name, "  (",
        SnoopCompile.countchildren(t), " children)")
end
for t in ours
    println("  ✗ ", t.method)
end

failed = false
if !isempty(ours)
    println()
    println("  OpenMath's own methods invalidate existing code. That is a")
    println("  signature wider than what it means, or a piracy: narrow it.")
    failed = true
end
if RECORDED !== nothing && total > RECORDED
    println()
    println("  total rose from ", RECORDED, " to ", total,
        " — if that is intended, update [invalidations] in")
    println("  test/harness/baseline.toml in the same commit.")
    failed = true
end

if "--save" in ARGS
    text = read(BASELINE, String)
    body = "\n[invalidations]\n" *
           "# Loading OpenMath invalidates this many method instances. None of\n" *
           "# them is caused by a method this package inserts; they come from\n" *
           "# Dates superseding Base.TOML.Printer.is_valid_toml_value(::Any),\n" *
           "# reached by OpenMath -> PrecompileTools -> Preferences -> TOML -> Dates.\n" *
           "total = $(total)\n" *
           "ours = $(length(ours))\n"
    text = replace(text, r"\n\[invalidations\][\s\S]*$" => "")
    write(BASELINE, rstrip(text) * "\n" * body)
    println("  wrote [invalidations] to ", BASELINE)
    failed = false
end

println()
println(failed ? "  FAILED" : "  OK")
exit(failed ? 1 : 0)
