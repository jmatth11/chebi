const std = @import("std");
const chebi = @import("chebi");
const server = chebi.server;

var s: server.Server = undefined;
const empty_sig: [16]c_ulong = @splat(0);

export fn shutdown(_: i32) void {
   s.stop();
   s.deinit();
}

pub fn main() !void {
    s = try server.Server.init(std.heap.smp_allocator, 3000);
    _ = std.c.sigaction(std.c.SIG.INT, &.{
        .handler = .{ .handler = shutdown },
        .mask = empty_sig,
        .flags = 0,
    }, null);
    s.listen() catch |err| {
        const errno = std.posix.errno(-1);
        std.debug.print("errno: {any}\n", .{errno});
        std.debug.print("err = {any}\n", .{err});
    };
    std.debug.print("--- SERVER CLOSED ---", .{});
}
