const std = @import("std");
const builtin = @import("builtin");
const chebi = @import("chebi");
const client = chebi.client;

const name = "SUB-2";
var running: bool = true;
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
    running = false;
}
pub fn main() !void {
    const addr = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 3000);
    defer alloc_deinit();
    var c = try client.Client.init(alloc, addr);
    defer c.deinit();
    var msg_count: usize = 0;

    try c.connect();
    try c.subscribe("test 2");

    while (running) {
        var msg = try c.next_msg();
        defer msg.deinit();
        msg_count = msg_count + 1;
        std.debug.print("{s} topic: {s} -- ", .{ name, msg.topic.? });
        if (msg.payload.?.len < 50) {
            std.debug.print("{s} msg: \"{s}\"\n", .{ name, msg.payload.? });
        } else {
            if (msg.payload) |payload| {
                std.debug.print("{s} large file recv: size({}).\n", .{ name, payload.len });
            }
        }
        if (msg_count >= 100) {
            running = false;
        }
    }
    std.debug.print("{s} has finished\n", .{name});
}
