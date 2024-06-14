_TOOLCHAIN = "//compatibility/breaking:toolchain_type"

def _protoc_plugin_test(ctx, proto_infos, protoc, plugin, config, files_to_include):
    deps = depset(
        [pi.direct_descriptor_set for pi in proto_infos],
        transitive = [pi.transitive_descriptor_sets for pi in proto_infos],
    )

    sources = []
    source_files = []

    for pi in proto_infos:
        for f in pi.direct_sources:
            source_files.append(f)

            # source is the argument passed to protoc. This is the import path "foo/foo.proto"
            # We have to trim the prefix if strip_import_prefix attr is used in proto_library.
            sources.append(
                f.path[len(pi.proto_source_root) + 1:] if f.path.startswith(pi.proto_source_root) else f.path,
            )

    args = ctx.actions.args()
    args = args.set_param_file_format("multiline")
    args.add_joined(["--plugin", "protoc-gen-buf-plugin", plugin.short_path], join_with = "=")
    args.add_joined(["--buf-plugin_opt", config], join_with = "=")
    args.add_joined("--descriptor_set_in", deps, join_with = ":", map_each = _short_path)
    args.add_joined(["--buf-plugin_out", "."], join_with = "=")
    args.add_all(sources)

    args_file = ctx.actions.declare_file("{}-args".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
        is_executable = True,
    )

    ctx.actions.write(
        output = ctx.outputs.executable,
        content = "{} @{}".format(protoc.short_path, args_file.short_path),
        is_executable = True,
    )

    files = [protoc, plugin, args_file] + source_files + files_to_include
    runfiles = ctx.runfiles(
        files = files,
        transitive_files = deps,
    )

    return [
        DefaultInfo(
            runfiles = runfiles,
        ),
    ]

def _breaking_test_impl(ctx):
    proto_infos = [t[ProtoInfo] for t in ctx.attr.targets]
    config_map = {
        "against_input": ctx.file.against.short_path,
        "input_config": ctx.file.config.short_path,
        "exclude_imports": True,
    }
    config = json.encode(config_map)
    files_to_include = [ctx.file.against]
    if ctx.file.config != None:
        files_to_include.append(ctx.file.config)
    return _protoc_plugin_test(
        ctx,
        proto_infos,
        ctx.executable._protoc,
        ctx.toolchains[_TOOLCHAIN].plugin,
        config,
        files_to_include,
    )

_breaking_test = rule(
    implementation = _breaking_test_impl,
    attrs = {
        "_protoc": attr.label(
            default = "//:protoc",
            executable = True,
            cfg = "exec",
        ),
        "targets": attr.label_list(
            providers = [ProtoInfo],
            doc = "`proto_library` targets to check for breaking changes.",
        ),
        "against": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Descriptor set to check against.",
        ),
        "config": attr.label(
            allow_single_file = True,
            doc = "The `buf.yaml` configuration file.",
        ),
    },
    toolchains = [_TOOLCHAIN],
    test = True,
)

def proto_breaking_test(name, against_version, targets, config):
    for target in targets:
        _breaking_test(
            name = name + "_" + target,
            targets = ["//:" + target],
            config = config,
            against = "@com_google_protobuf_v{version}//:{target}".format(
                version = against_version,
                target = target,
            )
        )

    native.test_suite(
        name = name,
        tests = [name + "_" + target for target in targets],
    )

def _short_path(file, dir_exp):
    return file.short_path
