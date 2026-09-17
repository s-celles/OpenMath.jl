# SPDX-License-Identifier: MIT

@testitem "Aqua quality assurance" tags = [:quality] begin
    using Aqua, OpenMath
    Aqua.test_all(OpenMath)
end

@testitem "every source file carries an SPDX header (REQ-PRJ-003)" tags = [:quality] begin
    using OpenMath
    root = joinpath(pkgdir(OpenMath), "src")
    offenders = String[]
    for (dir, _, files) in walkdir(root), f in files

        endswith(f, ".jl") || continue
        p = joinpath(dir, f)
        startswith(readline(p), "# SPDX-License-Identifier: MIT") ||
            push!(offenders, relpath(p, pkgdir(OpenMath)))
    end
    @test isempty(offenders)
end

@testitem "the core drags in no binary artifact (REQ-PRJ-002)" tags = [:quality] begin
    using OpenMath, TOML, Pkg
    project = TOML.parsefile(joinpath(pkgdir(OpenMath), "Project.toml"))

    # This gate used to assert `isempty(deps)`. That was a proxy — exact while
    # there were no dependencies at all, and stricter than the requirement, which
    # is "no mandatory dependency requiring a **compiled binary artifact**"
    # (REQ-PRJ-002, spec G7). Phase 8 added `PrecompileTools`, pure Julia with no
    # artifact, for a measured 20× improvement in time to first parse, and the
    # proxy fired on a dependency the requirement permits.
    #
    # So the gate now checks the requirement rather than the proxy: walk the
    # resolved dependency graph from this package and fail on any `_jll`, which
    # is how a binary artifact reaches a Julia package. That is strictly stronger
    # than counting direct dependencies, because it sees transitive ones too.
    deps = Pkg.dependencies()
    root = findfirst(p -> p.name == "OpenMath", deps)
    @test root !== nothing

    seen = Set{Base.UUID}()
    binary = String[]
    stack = Base.UUID[root]
    while !isempty(stack)
        uuid = pop!(stack)
        uuid in seen && continue
        push!(seen, uuid)
        info = get(deps, uuid, nothing)
        info === nothing && continue
        endswith(info.name, "_jll") && push!(binary, info.name)
        for (_, child) in info.dependencies
            push!(stack, child)
        end
    end
    isempty(binary) || println("  binary artifacts reachable: ", join(binary, ", "))
    @test isempty(binary)

    # Direct dependencies stay few and are named here, so that adding one is a
    # deliberate edit to this list rather than a quiet resolve.
    direct = sort(collect(keys(get(project, "deps", Dict{String, Any}()))))
    @test direct == ["PrecompileTools"]
end

@testitem "parsed content is never evaluated (REQ-SEC-005)" tags = [:quality] begin
    using OpenMath
    root = joinpath(pkgdir(OpenMath), "src")
    banned = ("eval(", "include_string", "Meta.parse", "@eval")
    offenders = String[]
    for (dir, _, files) in walkdir(root), f in files

        endswith(f, ".jl") || continue
        src = read(joinpath(dir, f), String)
        for b in banned
            occursin(b, src) && push!(offenders, "$(relpath(joinpath(dir, f), root)): $b")
        end
    end
    @test isempty(offenders)
end

@testitem "no third-party reference source is tracked (REQ-PRJ-003, REQ-PRJ-011)" tags = [:quality] begin
    using OpenMath
    root = pkgdir(OpenMath)
    # refs/ holds local clones consulted during development — among them the
    # GPL-3 reference crate. They are clones, never vendored code: committing one
    # would put GPL-3 sources into an MIT repository. A comment saying so is a
    # preference; this is the guarantee.
    tracked = try
        readlines(pipeline(`git -C $root ls-files refs/`; stderr = devnull))
    catch
        String[]   # not a git checkout, e.g. installed from the registry
    end
    @test isempty(tracked)

    ignored = try
        success(pipeline(`git -C $root check-ignore -q refs`; stderr = devnull))
    catch
        false
    end
    # Either refs/ does not exist yet, or it is ignored. It is never tracked.
    @test !isdir(joinpath(root, "refs")) || ignored
end

@testitem "JET finds no error in our own code" tags = [:quality] begin
    using JET, OpenMath
    reports = JET.get_reports(JET.report_package(OpenMath; toplevel_logger = nothing))

    # JET analyses a package inside a virtual module whose load path does not
    # resolve that package's own dependencies, so `src/precompile.jl` — which
    # needs `PrecompileTools` — cannot be analysed at all and comes back as an
    # analysis *error* rather than an inference finding. Those reports have no
    # `vst`, so they are separated rather than filtered blindly: an analysis
    # error from anywhere else still fails this gate, which is the difference
    # between an exception and an exemption.
    inference = filter(r -> hasproperty(r, :vst), reports)
    failures = filter(r -> !hasproperty(r, :vst), reports)
    unexplained = filter(failures) do r
        !occursin(joinpath("src", "precompile.jl"), string(r.file))
    end
    isempty(unexplained) || foreach(
        r -> println(r.file, ":", r.line, "  ",
            first(sprint(showerror, r.err), 200)), unexplained)
    @test isempty(unexplained)

    # The gate proper is on findings whose *failure point* is in our source. JET
    # also reports method errors deep inside Base's generic array machinery,
    # reached because our constructors accept `AbstractVector` and Base must then
    # consider range-like inputs: those branches need `one`, `isless` and
    # `convert(T, ::Bool)` on our node types, are unreachable for every argument
    # this package passes, and are not provably dead to a static analyser. They
    # say nothing about our code, and narrowing the signatures to silence them
    # would make the API worse.
    ours = filter(inference) do r
        !isempty(r.vst) &&
            occursin(joinpath("OpenMath.jl", "src"), string(last(r.vst).file))
    end
    isempty(ours) || foreach(r -> println(sprint(show, r)), ours)
    @test isempty(ours)
end

@testitem "imports are explicit" tags = [:quality] begin
    using ExplicitImports, OpenMath
    # `ExplicitImports` can only inspect modules that are loaded, so an extension
    # is invisible to this gate unless something has pulled its trigger package
    # in. Loading it here rather than relying on another test item having run
    # first is the difference between a gate and a coincidence: without this the
    # extension was checked in `--tier full` and not in `--tier standard`.
    using Symbolics

    # `OpenMathSymbolicsExt` takes five names from `Symbolics` that `Symbolics`
    # itself re-exports from `SymbolicUtils` and `TermInterface`, and reaches
    # `BasicSymbolic` the same way. Importing them from their owners instead
    # would mean declaring and version-bounding two more packages — the
    # substrate of the Symbolics stack — to reach an API Symbolics already
    # offers. That is more coupling, not less, so these names are named here
    # rather than the gate being relaxed: anything else still fails.
    resold = (:unwrap, :issym, :iscall, :operation, :arguments)
    @test check_no_implicit_imports(OpenMath) === nothing
    @test check_all_explicit_imports_via_owners(OpenMath; ignore = resold) === nothing
    @test check_no_stale_explicit_imports(OpenMath) === nothing
    @test check_all_qualified_accesses_via_owners(OpenMath;
        ignore = (:BasicSymbolic,)) === nothing
end

@testitem "the source is formatted (SciML style)" tags = [:quality] begin
    using JuliaFormatter, OpenMath
    root = pkgdir(OpenMath)
    # `.JuliaFormatter.toml` carries the style, so this gate and `just format`
    # cannot drift apart. Markdown is excluded there deliberately: formatting it
    # rewrote the LICENSE's copyright line into a markdown link.
    unformatted = String[]
    for dir in ("src", "test", "docs")
        for (d, _, files) in walkdir(joinpath(root, dir)), f in files

            endswith(f, ".jl") || continue
            p = joinpath(d, f)
            format(p; overwrite = false) || push!(unformatted, relpath(p, root))
        end
    end
    isempty(unformatted) || println("unformatted: ", join(unformatted, ", "))
    @test isempty(unformatted)
end
