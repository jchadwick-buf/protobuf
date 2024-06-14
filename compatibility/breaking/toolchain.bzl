load(
    "@bazel_tools//tools/build_defs/repo:utils.bzl",
    "update_attrs",
)

_WORKSPACE_FILE = """
workspace(name = "{name}")
"""

_BUILD_FILE = """
load("//:toolchain.bzl", "declare_toolchain")
package(default_visibility = ["//visibility:public"])
declare_toolchain(
    os = "{os}",
    cpu = "{cpu}",
    bin = "{bin}",
)
"""

_TOOLCHAIN_FILE = """
def _toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        plugin = ctx.executable.bin,
    )
    return [toolchain_info]

_toolchain = rule(
    implementation = _toolchain_impl,
    attrs = {
        "bin": attr.label(
            doc = "protoc plugin for detecting breaking changes",
            executable = True,
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
        ),
    },
)

def declare_toolchain(os, cpu, bin):
    _toolchain(
        name = "toolchain_impl",
        bin = bin,
    )
    native.toolchain(
        name = "toolchain",
        toolchain = ":toolchain_impl",
        toolchain_type = "@com_google_protobuf//compatibility/breaking:toolchain_type",
        exec_compatible_with = [
            "@platforms//os:" + os,
            "@platforms//cpu:" + cpu,
        ],
    )
"""

def _buf_breaking_release_impl(ctx):
    version = ctx.attr.version
    repository_url = ctx.attr.repository_url
    sha256 = ctx.attr.sha256

    os = ctx.os.name
    if os == "mac os x":
        os = "darwin"
    elif os.startswith("windows"):
        os = "windows"

    arch = ctx.os.arch
    if arch == "aarch64" and os != "linux":
        arch = "arm64"

    bin_suffix = ""
    if os == "windows":
        bin_suffix = ".exe"

    if os not in ["linux", "darwin", "windows"] or arch not in ["arm64", "amd64"]:
        fail("Unsupported operating system or CPU architecture")

    ctx.report_progress("Downloading buf SHA256 hashes")
    url = "{}/{}/sha256.txt".format(repository_url, version)
    sha256 = ctx.download(
        url = url,
        sha256 = sha256,
        canonical_id = url,
        output = "sha256.txt",
    ).sha256
    hashes = {
        line[66:]: line[:64]
        for line in ctx.read("sha256.txt").splitlines()
        if len(line) > 0
    }

    ctx.report_progress("Downloading protoc-gen-buf-breaking")
    bin = "protoc-gen-buf-breaking-{os}-{arch}{suffix}".format(
        os = os.title(),
        arch = arch,
        suffix = bin_suffix
    )
    output = "protoc-gen-buf-breaking" + bin_suffix
    url = "{}/{}/{}".format(repository_url, version, bin)
    ctx.download(
        url = url,
        sha256 = hashes[bin],
        executable = True,
        canonical_id = url,
        output = output,
    )

    if os == "darwin":
        os = "osx"

    ctx.file("WORKSPACE", _WORKSPACE_FILE.format(name = ctx.name))
    ctx.file("BUILD", _BUILD_FILE.format(os = os, cpu = arch, bin = output))
    ctx.file("toolchain.bzl", _TOOLCHAIN_FILE)

    return update_attrs(ctx.attr, ["version", "sha256"], {
        "version": version,
        "sha256": sha256,
    })

_buf_breaking_release = repository_rule(
    implementation = _buf_breaking_release_impl,
    attrs = {
        "version": attr.string(
            doc = "Buf release version.",
        ),
        "sha256": attr.string(
            doc = "Buf release sha256.txt checksum.",
        ),
        "repository_url": attr.string(
            doc = "Repository url base used for downloads.",
            default = "https://github.com/bufbuild/buf/releases/download",
        ),
    },
)

def breaking_toolchain(name = "protoc_gen_buf_breaking", version = None, sha256 = None, repository_url = None):
    """
    Fetches and registers the protoc-gen-buf-breaking tool by pulling it from a Buf GitHub release.
    """
    _buf_breaking_release(name = name, version = version, sha256 = sha256, repository_url = repository_url)
    native.register_toolchains("@{repo}//:toolchain".format(repo = name))
