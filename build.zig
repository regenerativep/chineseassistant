const std = @import("std");
const GitRepoStep = @import("GitRepoStep.zig");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addSharedLibrary("chinesereader", "src/main.zig", .unversioned);
    lib.setBuildMode(mode);
    lib.setTarget(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    lib.linkage = .dynamic;
    //lib.strip = true;

    const ep_repo = GitRepoStep.create(b, .{
        .url = "https://github.com/regenerativep/extrapacked.git",
        .branch = "main",
        .sha = "2e1a1d6034797caa58b608bf99aad5e74bb1cec7",
    });
    lib.step.dependOn(&ep_repo.step);
    lib.addPackagePath("extrapacked", std.fs.path.join(
        b.allocator,
        &[_][]const u8{ ep_repo.getPath(&lib.step), "extrapacked.zig" },
    ) catch unreachable);

    lib.export_symbol_names = &[_][]const u8{
        "launch_export",
        "receiveInputBuffer",
        "retrieveDefinitions",
    };

    lib.install();

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
