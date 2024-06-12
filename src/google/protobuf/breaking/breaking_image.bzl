"""Defines buf_breaking_image rule"""

_DOC = """
`buf_breaking_image` is a rule that builds an image for breaking change detection.
"""

_TOOLCHAIN = str(Label("@rules_buf//tools/buf:toolchain_type"))

def _buf_breaking_image_impl(ctx):
    args = ctx.actions.args()

    # Set option arguments
    if ctx.attr.config != "":
        args.add("--config", args)
    for path in ctx.attr.paths:
        args.add("--path", path)
    output_file = ctx.actions.declare_file(ctx.label.name + "_buf-image.binpb")
    args.add("-o", output_file)

    # Construct input specification
    input_file = ctx.file.input.path
    input_opts = [k + "=" + v for k, v in ctx.attr.input_opts.items()]
    if len(input_opts) > 0:
        input_file += "#" + ",".join(input_opts)

    args.add("build", input_file)

    ctx.actions.run(
        outputs = [output_file],
        inputs = [ctx.file.input],
        executable = ctx.toolchains[_TOOLCHAIN].cli,
        arguments = [args],
    )

    return DefaultInfo(
        files = depset([output_file]),
    )

buf_breaking_image = rule(
    implementation = _buf_breaking_image_impl,
    doc = _DOC,
    attrs = {
        "config": attr.string(
            doc = "Buf configuration to use",
        ),
	"input": attr.label(
	    allow_single_file = True,
	    doc = "File to use as input",
	),
	"input_opts": attr.string_dict(
	    doc = "Options to use for input file",
	),
	"paths": attr.string_list(
	    doc = "Paths to limit the built image to",
	),
    },
    toolchains = [_TOOLCHAIN],
)

