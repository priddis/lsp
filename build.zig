const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Precompilation step to generate treesitter constants
    const generate_consts = b.addExecutable(.{
        .name = "generate_ts_constants",
        .root_source_file = .{ .path = "tools/generate_ts_constants.zig" },
        .target = b.host,
    });
    generate_consts.addObjectFile(b.path("lib/libtree-sitter.a"));
    generate_consts.addObjectFile(b.path("lib/libtree-sitter-java.a"));
    generate_consts.addIncludePath(b.path("include"));
    generate_consts.linkLibC();

    const generate_consts_step = b.addRunArtifact(generate_consts);
    const output = generate_consts_step.addOutputFileArg("ts_constants.zig");

    const write_file = b.addWriteFiles();
    write_file.addCopyFileToSource(output, "src/ts_constants.zig");
    const generate = b.step("gen", "generate ts constants");
    generate.dependOn(&write_file.step);

    // Compilation step
    const exe = b.addExecutable(.{
        .name = "lsp",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addObjectFile(b.path("lib/libtree-sitter.a"));
    exe.addObjectFile(b.path("lib/libtree-sitter-java.a"));
    exe.addIncludePath(b.path("include"));
    exe.linkLibC();

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // Test step
    const filter = b.option([]const u8, "f", "Test filter");
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .filter = filter,
    });
    unit_tests.addObjectFile(b.path("lib/libtree-sitter.a"));
    unit_tests.addObjectFile(b.path("lib/libtree-sitter-java.a"));
    unit_tests.addIncludePath(b.path("include"));
    unit_tests.linkLibC();
    unit_tests.step.dependOn(b.getInstallStep());

    const run_unit_tests = b.addRunArtifact(unit_tests);
    run_unit_tests.has_side_effects = true;

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
