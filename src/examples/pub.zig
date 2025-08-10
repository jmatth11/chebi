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
    std.time.sleep(std.time.ms_per_s * 5);
}
