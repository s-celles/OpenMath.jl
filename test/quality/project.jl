# SPDX-License-Identifier: MIT

@testitem "Aqua quality assurance" tags = [:quality] begin
    using Aqua, OpenMath
    # `XML` is loaded only when the `xml_backend` preference selects the
    # `XML.jl` tokenizer (decision D1), and the default is the hand-written one —
    # so on a default build it is a declared dependency nothing imports, which is
    # exactly what `stale_deps` is for. The conditional dependency is the
    # experiment; the exemption goes away with whichever backend loses.
    Aqua.test_all(OpenMath; stale_deps = (; ignore = [:XML]))
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
    # `XML` arrives with the re-opened decision D1 and is imported only when the
    # `xmljl` backend is selected. It is pure Julia, which is what REQ-PRJ-002 is
    # about; the count is not.
    @test direct == ["PrecompileTools", "XML"]
end

@testitem "parsed content is never evaluated (REQ-SEC-005)" tags = [:quality] begin
    using OpenMath
    # `src` *and* `ext`. The gate walked `src` alone, so the Symbolics extension —
    # which is the one place in this package that turns an OpenMath symbol into a
    # call — was outside it. It is clean, and it was clean unwatched, which is the
    # same shape as E3 and E7: a check green on what it could not reach.
    roots = [joinpath(pkgdir(OpenMath), d) for d in ("src", "ext")]
    banned = ("eval(", "include_string", "Meta.parse", "@eval")
    offenders = String[]
    for root in roots, (dir, _, files) in walkdir(root), f in files
        endswith(f, ".jl") || continue
        source = read(joinpath(dir, f), String)
        for b in banned
            occursin(b, source) &&
                push!(offenders, "$(relpath(joinpath(dir, f), pkgdir(OpenMath))): $b")
        end
    end
    isempty(offenders) || foreach(println, offenders)
    @test isempty(offenders)
    @test length(roots) == 2 && all(isdir, roots)
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

@testitem "every module the tests use is a declared dependency" tags = [:quality] begin
    using OpenMath, TOML
    # `just verify` runs against a manifest that has accumulated transitive
    # dependencies, so `using Random` in a test file works locally whether or not
    # anything declared it — and fails on a clean checkout. That is exactly what
    # happened: the first CI run on Julia 1.10 failed on `Pkg` and `Random`,
    # both undeclared, both invisible here.
    #
    # This is a *static* check rather than a clean resolve, because it is cheap
    # enough to run every time and points at the file rather than at a stack.
    root = pkgdir(OpenMath)
    declared = Set(keys(TOML.parsefile(joinpath(root, "test", "Project.toml"))["deps"]))
    push!(declared, "Test", "OpenMath")         # always available under test
    always = Set(["Base", "Core", "Main"])

    offenders = Tuple{String, String}[]
    for (dir, _, files) in walkdir(joinpath(root, "test")), f in files

        endswith(f, ".jl") || continue
        path = joinpath(dir, f)
        # An opt-in oracle runs under its own environment — `oracle-mathml`, for
        # one, because MathML.jl pins Symbolics to an exact version and must not
        # pin ours. Such a file says so in a marker line and is exempt; the
        # exemption is declared in the file rather than listed here, so adding
        # one is visible where it applies.
        occursin("# runs under --project=", read(path, String)) && continue
        for (i, line) in enumerate(eachline(path))
            m = match(r"^\s*using\s+([A-Za-z_][A-Za-z0-9_.]*)", line)
            m === nothing && continue
            mod = String(first(split(m.captures[1], '.')))
            (mod in declared || mod in always || startswith(mod, "_")) && continue
            push!(offenders, (relpath(joinpath(dir, f), root) * ":" * string(i), mod))
        end
    end
    isempty(offenders) ||
        foreach(o -> println("  ", o[1], "  uses undeclared ", o[2]), offenders)
    @test isempty(offenders)
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

@testitem "the corpus matches its manifest (harness spec §4.2)" tags = [:quality] begin
    using OpenMath, SHA
    # The corpus is the verifier's ground truth, so an agent that can edit it can
    # make any test pass. `MANIFEST.sha256` hashes every item and `just
    # corpus-check` compares — but nothing ran it: not `just verify`, not CI. It
    # drifted, and the drift shipped in the first published commit.
    #
    # A gate nobody runs is a gate that is green because it is asleep, which is
    # the third time this project has learned that. So the comparison lives here,
    # where `just verify` and CI both reach it, and `just corpus-check` remains
    # for the `--update` path.
    root = joinpath(pkgdir(OpenMath), "test", "corpus")
    manifest = Dict{String, String}()
    for line in eachline(joinpath(root, "MANIFEST.sha256"))
        parts = split(line, "  ", limit = 2)
        length(parts) == 2 && (manifest[String(strip(parts[2]))] = String(parts[1]))
    end

    changed = String[]
    for (dir, _, files) in walkdir(root), f in files

        f == "MANIFEST.sha256" && continue
        rel = replace(relpath(joinpath(dir, f), root), '\\' => '/')
        recorded = get(manifest, rel, nothing)
        recorded === nothing && continue          # additions are free
        bytes2hex(sha256(read(joinpath(dir, f)))) == recorded || push!(changed, rel)
    end
    missing_items = [k for k in keys(manifest) if !isfile(joinpath(root, k))]

    isempty(changed) ||
        println("  modified since the manifest: ", join(sort(changed), ", "))
    isempty(missing_items) ||
        println("  deleted since the manifest: ", join(sort(missing_items), ", "))
    @test isempty(changed)
    @test isempty(missing_items)
end

@testitem "every exported symbol carries a runnable example (REQ-DOC-002)" tags = [
    :quality] begin
    using OpenMath
    # A docstring is a claim; a doctest is a claim the build checks. `checkdocs =
    # :exports` already fails on a *missing* docstring, and every one of the 81
    # exported symbols had one — while only 24 carried an example. The rest were
    # prose that nothing executed, which is the failure mode this whole project
    # is built against.
    #
    # Documenter runs every `jldoctest` on each build, so this gate only has to
    # assert the blocks exist; their correctness is the docs build's job.
    exceptions = Dict(
    # Lives in the Symbolics extension. A `jldoctest` would need Symbolics in
    # the documentation environment, which would pull the whole SciML stack
    # into every docs build to check one example. Its block is marked
    # ```julia and is exercised by `test/unit/symbolics.jl` instead.
        :symbolics_phrasebook => "extension; tested in test/unit/symbolics.jl")

    without = String[]
    for n in names(OpenMath)
        n === :OpenMath && continue
        haskey(exceptions, n) && continue
        text = try
            string(eval(Meta.parse("@doc OpenMath.$(n)")))
        catch
            ""
        end
        occursin("jldoctest", text) || push!(without, string(n))
    end
    isempty(without) || println("  no runnable example: ", join(sort(without), ", "))
    @test isempty(without)

    # The exception list is not a drawer: every name in it must still be exported,
    # or it is describing a symbol that no longer exists.
    for n in keys(exceptions)
        @test n in names(OpenMath)
    end
end

@testitem "the changelog is Keep a Changelog, and its links resolve" tags = [:quality] begin
    using OpenMath
    # CLAUDE.md requires Keep a Changelog. Nothing checked it, and it drifted
    # three ways at once: `### Added` and `### Fixed` each appeared three times
    # under one release, because every commit prepended its own; the `[0.0.1]`
    # section described itself as "Phase 0 and Phase 1" while listing Phase 3
    # work; and it linked to a GitHub release tag that was never created.
    #
    # The last one is the interesting one. A changelog that announces a release
    # nobody can download is worse than one that says nothing, and no amount of
    # care prevents it — only a check that resolves the claim against `git tag`.
    root = pkgdir(OpenMath)
    lines = readlines(joinpath(root, "CHANGELOG.md"))

    ORDER = ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"]
    # Parsed inside a `let`: a bare `for` at the top level of a test item is soft
    # scope, so assigning to an outer local from inside it is an error.
    releases, seen, unknown = let releases = String[],
        seen = Dict{String, Vector{String}}(), unknown = String[], current = ""

        for line in lines
            if startswith(line, "## [")
                current = String(match(r"^## \[([^\]]+)\]", line).captures[1])
                push!(releases, current)
                seen[current] = String[]
            elseif startswith(line, "### ")
                name = String(strip(line[5:end]))
                name in ORDER || push!(unknown, "$(current)/$(name)")
                push!(seen[current], name)
            end
        end
        (releases, seen, unknown)
    end

    isempty(unknown) || println("  unknown sections: ", join(unknown, ", "))
    @test isempty(unknown)

    @test !isempty(releases)
    for r in releases
        names = seen[r]
        # One of each, and in the canonical order.
        @test "$(r): no repeated section" ==
              "$(r): $(length(names) == length(unique(names)) ? "no repeated section" :
                       "repeats " * join(unique([n for n in names
                                                 if count(==(n), names) > 1]), ", "))"
        ranks = [findfirst(==(n), ORDER) for n in names if n in ORDER]
        @test "$(r): sections in order" ==
              "$(r): $(issorted(ranks) ? "sections in order" : "out of order: " *
                       join(names, ", "))"
    end

    # A version section must correspond to a tag that exists. `Unreleased` is the
    # one name that may not.
    tags = try
        Set(readlines(pipeline(`git -C $root tag`; stderr = devnull)))
    catch
        nothing
    end
    if tags === nothing
        @test_skip "not a git checkout"
    else
        for r in releases
            r == "Unreleased" && continue
            @test "$(r): tagged" ==
                  "$(r): $(("v" * r) in tags || r in tags ? "tagged" :
                           "no such tag — the release was never cut")"
        end
    end

    # And no link definition may point at a tag that does not exist either.
    for line in lines
        m = match(r"^\[([^\]]+)\]:\s*(\S+)", line)
        m === nothing && continue
        url = m.captures[2]
        occursin("/releases/tag/", url) || occursin("/compare/", url) || continue
        tags === nothing && continue
        for t in eachmatch(r"v\d+\.\d+\.\d+", url)
            @test "$(t.match): tagged" ==
                  "$(t.match): $(t.match in tags ? "tagged" : "no such tag")"
        end
    end
end

@testitem "no prose claims a version the package is not" tags = [:quality] begin
    using OpenMath, TOML
    # The README said "early development (v0.0.1)" and "the XML, JSON and binary
    # encodings are next" for as long as all four had been implemented. Prose
    # about the state of the package rots exactly as fast as the package moves,
    # and nothing was reading it.
    #
    # First written for `README.md` alone, which was too narrow by one file: the
    # published front page still pointed at "what 0.9.0 requires" after the
    # roadmap's phase milestones were renumbered away from it, and a reader
    # found that before this gate did. It walks the documentation sources too.
    root = pkgdir(OpenMath)
    version = TOML.parsefile(joinpath(root, "Project.toml"))["version"]
    readme = read(joinpath(root, "README.md"), String)

    prose = Tuple{String, String}[("README.md", readme)]
    for (dir, _, files) in walkdir(joinpath(root, "docs", "src")), f in files

        endswith(f, ".md") || continue
        # `compat.md` illustrates the versioning rules with invented numbers —
        # "0.4.1 to 0.4.2" — which are examples, not claims about this package.
        f == "compat.md" && continue
        push!(prose, (relpath(joinpath(dir, f), root), read(joinpath(dir, f), String)))
    end

    stale = String[]
    for (name, text) in prose, m in eachmatch(r"\b(?:v|version )(\d+\.\d+\.\d+)", text)

        m.captures[1] == version && continue
        # A version attached to something else — Julia, a dependency, an
        # upstream tool — is not a claim about this package.
        before = text[max(1, m.offset - 40):(m.offset - 1)]
        occursin(r"(?i)julia|crate|mathml|xml\.jl|gap|openmath 2", before) && continue
        push!(stale, "$(name): $(m.match)")
    end
    isempty(stale) ||
        println("  Project.toml says $(version); found ", join(unique(stale), ", "))
    @test isempty(unique(stale))

    # Asserted as a short string rather than `occursin(...)`, which on a failure
    # prints the whole README into the test log.
    @test "README states v$(version)" ==
          (occursin("v" * version, readme) ? "README states v$(version)" :
           "README names no version at all")
end
