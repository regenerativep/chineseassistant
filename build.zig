const std = @import("std");

pub fn build(b: *std.Build) void {
    const extrapacked_module = b.dependency(
        "extrapacked",
        .{},
    ).module("extrapacked");

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "chineseassistant-gendef",
        .root_source_file = .{ .path = "src/generate_definitions.zig" },
        .target = b.host,
    });
    exe.root_module.addImport("extrapacked", extrapacked_module);
    const run_exe = b.addRunArtifact(exe);
    run_exe.addFileArg(.{ .path = "data/cedict_ts.u8" });
    const unmoved_generated_words_bin = run_exe.addOutputFileArg("words.bin");
    const unmoved_generated_dict_values = run_exe.addOutputFileArg("dict_values.zig");

    const dict_wf = b.addWriteFiles();
    _ = dict_wf.addCopyFile(unmoved_generated_words_bin, "words.bin");
    const generated_dict_values =
        dict_wf.addCopyFile(unmoved_generated_dict_values, "dict_values.zig");

    const dict_gen_mod = b.addModule(
        "chineseassistant-dictvalues",
        .{ .root_source_file = generated_dict_values },
    );

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Generate definitions");
    run_step.dependOn(&run_cmd.step);

    const lib = b.addExecutable(.{
        .name = "chinesereader",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = b.resolveTargetQuery(
            .{ .cpu_arch = .wasm32, .os_tag = .freestanding },
        ),
        .optimize = optimize,
    });
    lib.entry = .disabled;
    //lib.strip = true;

    lib.root_module.addImport("chineseassistant-dictvalues", dict_gen_mod);
    lib.root_module.addImport("extrapacked", extrapacked_module);

    lib.root_module.export_symbol_names = &[_][]const u8{
        "launch_export",
        "receiveInputBuffer",
        "retrieveDefinitions",
        "getBuffer",
        "freeBuffer",
        "longestCodepointLength",
    };

    b.installArtifact(lib);

    const cp_wasm_cmd = b.addSystemCommand(&[_][]const u8{"cp"});
    cp_wasm_cmd.addArtifactArg(lib);
    cp_wasm_cmd.addArg("public/chinesereader.wasm");

    const cp_chrejs_cmd = b.addSystemCommand(&[_][]const u8{
        "cp",
        "src/chinesereader.js",
        "public/chinesereader.js",
    });
    cp_chrejs_cmd.step.dependOn(&cp_wasm_cmd.step);

    b.getInstallStep().dependOn(&cp_chrejs_cmd.step);
}
