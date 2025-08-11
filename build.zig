const std = @import("std");

fn create_exe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, path: []const u8, name: []const u8, lib_mod: *std.Build.Module) !void {
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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "chebi",
        .root_module = lib_mod,
    });
    lib.linkLibC();

    b.installArtifact(lib);

    create_exe(b, target, optimize, "src/examples/simple/server.zig", "simple_server", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize,"src/examples/simple/pub.zig", "simple_pub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize,"src/examples/simple/sub.zig", "simple_sub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize, "src/examples/multiplex/server.zig", "multiplex_server", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize,"src/examples/multiplex/pub.zig", "multiplex_pub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };
    create_exe(b, target, optimize,"src/examples/multiplex/sub.zig", "multiplex_sub", lib_mod) catch |err| {
        std.debug.print("error: {s}\n", .{err});
    };

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
