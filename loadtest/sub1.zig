const std = @import("std");
const chebi = @import("chebi");
const client = chebi.client;

var running: bool = true;

export fn shutdown(_: i32) void {
    running = false;
}
pub fn main() !void {
    const addr = std.net.Address.initIp4([4]u8 {127,0,0,1}, 3000);
    var c = try client.Client.init(std.heap.smp_allocator, addr);
    defer c.deinit();
    try c.connect();
    try c.subscribe("test");
    while (running) {
        var msg = try c.next_msg();
        defer msg.deinit();
        std.debug.print("topic: {s}\n", .{msg.topic.?});
        if (msg.payload.?.len < 50) {
            std.debug.print("msg: {s}\n", .{msg.payload.?});
        } else {
            if (msg.payload) |payload| {
                std.debug.print("large file: size({}).\n", .{payload.len});
                const f = try std.fs.cwd().createFile("sub.out", .{});
                defer f.close();
                try f.writeAll(payload);
                std.debug.print("written to sub.out.\n", .{});
            }
        }
    }
}
