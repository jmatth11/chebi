const std = @import("std");
const chebi = @import("chebi");
const client = chebi.client;

pub fn main() !void {
    const addr = std.net.Address.initIp4([4]u8 {127,0,0,1}, 3000);
    var c = try client.Client.init(std.heap.smp_allocator, addr);
    defer c.deinit();
    try c.connect();
    try c.subscribe("test");
    const msg = try c.next_msg();
    std.debug.print("topic: {s}\n", .{msg.topic.?});
    std.debug.print("msg: {s}\n", .{msg.payload.?});
}
