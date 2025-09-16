const std = @import("std");

/// Create executable function.
fn create_exe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    path: []const u8,
    name: []const u8,
    lib_mod: *std.Build.Module,
) !void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("chebi", lib_mod);
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = exe_mod,
    });
    exe.linkLibC();
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step(name, "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn gen_load_test(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_mod: *std.Build.Module,
) !void {
    create_exe(b, target, optimize, "loadtest/server.zig", "loadtest_server", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "loadtest/sub1.zig", "loadtest_sub1", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "loadtest/sub2.zig", "loadtest_sub2", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "loadtest/pub_heavy.zig", "loadtest_pub1", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "loadtest/pub_heavy_split.zig", "loadtest_pub2", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
}

fn gen_examples(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_mod: *std.Build.Module,
) !void {
    // creating example apps
    create_exe(b, target, optimize, "examples/server/simple.zig", "simple_server", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "examples/pub/simple.zig", "simple_pub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "examples/pub/multiplex.zig", "multiplex_pub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "examples/pub/compression.zig", "compression_pub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "examples/sub/simple.zig", "simple_sub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "examples/sub/loop.zig", "loop_sub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compile_examples = b.option(bool, "examples", "Compile the Example programs.") orelse true;
    const compile_loadtest = b.option(bool, "loadtest", "Compile the load test programs.") orelse false;
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Link mode for utf8-zig library") orelse .static;

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // create static lib
    const lib = b.addLibrary(.{
        .linkage = linkage,
        .name = "chebi",
        .root_module = lib_mod,
    });
    // we use LibC stuff currently
    lib.linkLibC();

    b.installArtifact(lib);

    if (compile_examples) {
        try gen_examples(b, target, optimize, lib_mod);
    }
    if (compile_loadtest) {
        try gen_load_test(b, target, optimize, lib_mod);
    }

    const lib_test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib_unit_tests = b.addTest(.{
        .name = "test",
        .root_module = lib_test_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
