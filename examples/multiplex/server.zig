const std = @import("std");
const chebi = @import("chebi");
const server = chebi.server;

var s: server.Server = undefined;

export fn shutdown(_: i32) void {
   s.stop();
   s.deinit();
}

pub fn main() !void {
    s = try server.Server.init(std.heap.smp_allocator, 3000);
    std.posix.sigaction(std.posix.SIG.INT, &.{
        .handler = .{ .handler = shutdown },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);
    s.listen() catch |err| {
        const errno = std.posix.errno(-1);
        std.debug.print("errno: {any}\n", .{errno});
        std.debug.print("err = {any}\n", .{err});
    };
}
