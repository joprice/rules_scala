load("@rules_scala_annex//rules/scala:provider.bzl", "ScalaConfiguration", "ScalaInfo")
load(":private/import.bzl", "create_intellij_info")

def _filesArg(files):
    return ([str(len(files))] + [file.path for file in files])

runner_common_attributes = {
    "_java_toolchain": attr.label(
        default = Label("@bazel_tools//tools/jdk:current_java_toolchain"),
    ),
    "_host_javabase": attr.label(
        default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
        cfg = "host",
    ),
}

def runner_common(ctx):
    runner = ctx.toolchains["@rules_scala_annex//rules/scala:runner_toolchain_type"].runner

    configuration = ctx.attr.scala[ScalaConfiguration]

    splugin = java_common.merge([plugin[JavaInfo] for plugin in ctx.attr.plugins])

    deps = [dep[JavaInfo] for dep in configuration.runtime_classpath + ctx.attr.deps]
    sdep = java_common.merge([dep[JavaInfo] for dep in ctx.attr.deps])

    exports = [export[JavaInfo] for export in ctx.attr.exports]
    sexport = java_common.merge(exports)

    #annex_scala_format_test"%s : %s" % (ctx.label.name, splugin.transitive_runtime_jars))
    #annex_scala_format_test"%s : %s" % (ctx.label.name, sdep.compile_jars))
    #annex_scala_format_test"%s : %s" % (ctx.label.name, sexport.compile_jars))

    classes_directory = ctx.actions.declare_directory(
        "%s/classes/%s" % (ctx.label.name, configuration.version),
    )
    output = ctx.actions.declare_file(
        "%s/bin/%s.jar" % (ctx.label.name, configuration.version),
    )
    mains_file = ctx.actions.declare_file(
        "%s/bin/%s.jar.mains.txt" % (ctx.label.name, configuration.version),
    )

    if len(ctx.attr.srcs) == 0:
        java_info = java_common.merge([sdep, sexport])
    else:
        java_info = JavaInfo(
            output_jar = output,
            use_ijar = ctx.attr.use_ijar,
            sources = ctx.files.srcs,
            deps = deps,
            exports = exports,
            actions = ctx.actions,
            java_toolchain = ctx.attr._java_toolchain,
            host_javabase = ctx.attr._host_javabase,
        )

    analysis = ctx.actions.declare_file("{}/analysis/{}.proto.gz".format(ctx.label.name, configuration.version))

    runner_inputs, _, input_manifests = ctx.resolve_command(tools = [runner])

    args = ctx.actions.args()
    args.add(False)  # verbose
    args.add("")  # persistenceDir
    args.add(output.path)  # outputJar
    args.add(classes_directory.path)  # outputDir
    args.add(configuration.version)  # scalaVersion
    args.add(_filesArg(configuration.compiler_classpath))  # compilerClasspath
    args.add(configuration.compiler_bridge.path)  # compilerBridge
    args.add(_filesArg(splugin.transitive_runtime_deps))  # pluginsClasspath
    args.add(_filesArg(ctx.files.srcs))  # sources
    args.add(_filesArg(sdep.transitive_deps))  # compilationClasspath
    args.add(_filesArg(sdep.compile_jars))  # allowedClasspath
    args.add("_{}".format(ctx.label))  # label
    args.add(analysis.path)  # analysisPath
    args.set_param_file_format("multiline")
    args_file = ctx.actions.declare_file(
        "%s/bin/%s.args" % (ctx.label.name, configuration.version),
    )
    ctx.actions.write(args_file, args)

    runner_inputs, _, input_manifests = ctx.resolve_command(tools = [runner])

    inputs = depset()
    inputs += runner_inputs
    inputs += [configuration.compiler_bridge]
    inputs += configuration.compiler_classpath
    inputs += sdep.transitive_deps
    inputs += ctx.files.srcs
    inputs += splugin.transitive_runtime_deps
    inputs += [args_file]

    outputs = [output, mains_file, classes_directory, analysis]

    # todo: different execution path for nosrc jar?
    ctx.actions.run(
        mnemonic = "ScalaCompile",
        inputs = inputs,
        outputs = outputs,
        executable = runner.files_to_run.executable,
        input_manifests = input_manifests,
        execution_requirements = {"supports-workers": "1"},
        arguments = ["@%s" % args_file.path],
    )

    return struct(
        analysis = analysis,
        java_info = java_info,
        scala_info = ScalaInfo(analysis = analysis),
        intellij_info = create_intellij_info(ctx.label, ctx.attr.deps, java_info),
        files = depset([output]),
        mains_files = depset([mains_file]),
    )

annex_scala_library_private_attributes = runner_common_attributes

def annex_scala_library_implementation(ctx):
    res = runner_common(ctx)
    return struct(
        providers = [
            res.java_info,
            res.scala_info,
            res.intellij_info,
            DefaultInfo(
                files = res.files,
            ),
        ],
        java = res.intellij_info,
    )
