const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const gen_def = b.option(bool, "gen_def", "Generate definitions") orelse false;

    const extrapacked_module = b.dependency(
        "extrapacked",
        .{}, //.{ .target = target, .optimize = optimize },
    ).module("extrapacked");

    const optimize = b.standardOptimizeOption(.{});

    if (gen_def) {
        const target = b.standardTargetOptions(.{});

        const exe = b.addExecutable(.{
            .name = "chineseassistant-gendef",
            .root_source_file = .{ .path = "generate_definitions.zig" },
            .target = target,
            .optimize = optimize,
        });
        exe.addModule("extrapacked", extrapacked_module);
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);
        const run_step = b.step("run", "Generate definitions");
        run_step.dependOn(&run_cmd.step);
    } else {
        const target: std.zig.CrossTarget = .{ .cpu_arch = .wasm32, .os_tag = .freestanding };

        const lib = b.addSharedLibrary(.{
            .name = "chinesereader",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        lib.linkage = .dynamic;
        //lib.strip = true;

        lib.addModule("extrapacked", extrapacked_module);

        lib.export_symbol_names = &[_][]const u8{
            "launch_export",
            "receiveInputBuffer",
            "retrieveDefinitions",
            "getBuffer",
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
}
