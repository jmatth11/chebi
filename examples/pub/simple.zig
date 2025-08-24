const std = @import("std");
const chebi = @import("chebi");
const client = chebi.client;

pub fn main() !void {
    const addr = std.net.Address.initIp4([4]u8 {127,0,0,1}, 3000);
    var c = try client.Client.init(std.heap.smp_allocator, addr);
    defer c.deinit();
    try c.connect();
    try c.subscribe("test");
    try c.write("test", "hello from pub", chebi.message.Type.text);
    const wait_info: std.c.timespec = .{
        .sec = 1,
        .nsec = 0,
    };
    _ = std.c.nanosleep(&wait_info, null);
    try c.close();
}
