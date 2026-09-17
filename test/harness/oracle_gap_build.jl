# SPDX-License-Identifier: MIT
#
# Install GAP and its `openmath` package into refs/, for `just oracle-gap`.
#
# GAP is the only other implementation of the binary encoding, so it is the only
# differential oracle §3.2 can have. The licence boundary is the same one this
# repository already keeps with the Rust crate: GPL code run as a subprocess,
# never linked, no source read, nothing committed.
#
# It goes into a conda prefix under refs/ rather than a system package, so that
# `just oracle-gap-clean` really removes it and CI never sees it. On this machine
# the Debian packages were not an option anyway — apt refused on pre-existing
# broken dependencies unrelated to GAP.

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const ENVDIR = joinpath(ROOT, "refs", "gap-env")
const PKGDIR = joinpath(ROOT, "refs", "gap-root", "pkg")

# `gap-defaults` brings GAP and GAPDoc but neither IO nor openmath, and openmath
# names IO in its NeededOtherPackages, so IO has to be built from source.
const IO_VERSION = "4.8.2"
const OM_VERSION = "11.5.5"

run_quiet(cmd) = run(pipeline(cmd; stdout = devnull, stderr = devnull))

function install_gap()
    isfile(joinpath(ENVDIR, "bin", "gap")) && return println("  gap-env: present")
    print("  installing GAP into refs/gap-env (this takes a few minutes) … ")
    run_quiet(`conda create -y -p $ENVDIR -c conda-forge --override-channels gap-defaults`)
    println("done")
end

# GAP records the compiler it was built with, and a conda build records a path
# inside the build container that does not exist here. `gac` reads it verbatim,
# so building any package with a C kernel extension needs it pointed at a real
# compiler — and at GAP's own headers, which the recorded flags also omit.
function patch_sysinfo()
    path = joinpath(ENVDIR, "lib", "gap", "sysinfo.gap")
    text = read(path, String)
    occursin("/usr/bin/gcc", text) && return println("  sysinfo.gap: already patched")
    text = replace(text, r"^GAP_CC=.*$"m => "GAP_CC=\"/usr/bin/gcc \"")
    text = replace(text, r"^GAP_CXX=.*$"m => "GAP_CXX=\"/usr/bin/g++ \"")
    text = replace(text, "GAP_CPPFLAGS=\"" =>
        "GAP_CPPFLAGS=\"-I" * joinpath(ENVDIR, "include", "gap") * " ")
    write(path, text)
    println("  sysinfo.gap: patched for the local compiler and headers")
end

function fetch_package(name, url, dest)
    isdir(dest) && return println("  ", name, ": present")
    print("  fetching ", name, " … ")
    mkpath(PKGDIR)
    tarball = joinpath(PKGDIR, name * ".tar.gz")
    download(url, tarball)
    before = readdir(PKGDIR)
    run_quiet(`tar xzf $tarball -C $PKGDIR`)
    rm(tarball; force = true)
    added = setdiff(readdir(PKGDIR), before)
    extracted = only(filter(d -> isdir(joinpath(PKGDIR, d)), added))
    mv(joinpath(PKGDIR, extracted), dest)
    println("done")
end

function build_io()
    dir = joinpath(PKGDIR, "io")
    isfile(joinpath(dir, "bin", "64", "io.so")) && return println("  io: already built")
    print("  building io … ")
    gaproot = joinpath(ENVDIR, "lib", "gap")
    cd(dir) do
        run_quiet(`./configure --with-gaproot=$gaproot`)
        run_quiet(`make -j4`)
    end
    println(isempty(filter(!isnothing,
        [findfirst(f -> f == "io.so", readdir(d))
         for
         d in [joinpath(dir, "bin", x) for x in readdir(joinpath(dir, "bin"))]])) ?
            "no io.so produced" : "done")
end

function check()
    gap = joinpath(ENVDIR, "bin", "gap")
    root = joinpath(ROOT, "refs", "gap-root")
    script = tempname() * ".g"
    write(script, """
    if LoadPackage("openmath") = true then
        Print("OK ", GAPInfo.PackagesInfo.openmath[1].Version, "\\n");
    else Print("FAILED\\n"); fi;
    QUIT;""")
    out = read(`$gap -l "$(root);" -q -b $script`, String)
    rm(script; force = true)
    if occursin("OK", out)
        println("\n  openmath ", strip(split(out, "OK")[2]), " loads. `just oracle-gap` is ready.\n")
        return 0
    end
    println("\n  the openmath package did not load:\n", out, "\n")
    return 1
end

function main()
    println("\n  oracle-gap-setup\n")
    install_gap()
    patch_sysinfo()
    fetch_package("io",
        "https://github.com/gap-packages/io/releases/download/v$(IO_VERSION)/io-$(IO_VERSION).tar.gz",
        joinpath(PKGDIR, "io"))
    fetch_package("openmath",
        "https://github.com/gap-packages/openmath/releases/download/v$(OM_VERSION)/openmath-$(OM_VERSION).tar.gz",
        joinpath(PKGDIR, "openmath"))
    build_io()
    return check()
end

exit(main())
