const std = @import("std");
const builtin = @import("builtin");
const chebi = @import("chebi");
const server = chebi.server;

const name = "SERVER";
var s: server.Server = undefined;
const empty_sig: [16]c_ulong = @splat(0);
var debug: std.heap.DebugAllocator(.{}) = .init;
fn get_alloc() std.mem.Allocator {
    if (builtin.mode == .Debug) {
        return debug.allocator();
    } else {
        return std.heap.smp_allocator;
    }
}
const alloc = get_alloc();
fn alloc_deinit() void {
    if (builtin.mode == .Debug) {
        const check = debug.deinit();
        if (check == .leak) {
            std.log.err("{s}:main: leak detected.\n", .{name});
        }
    }
}

export fn shutdown(_: i32) void {
   s.stop();
}

pub fn main() !void {
    defer alloc_deinit();
    s = try server.Server.init(alloc, 3000);
    defer s.deinit();
    _ = std.c.sigaction(std.c.SIG.INT, &.{
        .handler = .{ .handler = shutdown },
        .mask = empty_sig,
        .flags = 0,
    }, null);
    std.debug.print("--- {s} BEGIN ---", .{name});
    s.listen() catch |err| {
        const errno = std.posix.errno(-1);
        std.debug.print("{s} [ERROR] errno: {any}\n", .{name, errno});
        std.debug.print("{s} [ERROR] err = {any}\n", .{name, err});
    };
    std.debug.print("--- {s} CLOSED ---", .{name});
}
