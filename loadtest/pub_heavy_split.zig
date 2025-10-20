const std = @import("std");
const builtin = @import("builtin");
const chebi = @import("chebi");
const client = chebi.client;

const name = "PUB-2";
const n: comptime_int = 100;
var running: bool = true;
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
    running = false;
}

// Send simple message.
// Sending to topic "test 1"
fn write_simple(c: *client.Client) !void {
    const wait_info: std.c.timespec = .{
        .sec = 1,
        .nsec = 0,
    };

    std.debug.print("{s} sending {} small buffers.\n", .{ name, n });
    for (0..n) |_| {
        if (running) {
            _ = std.c.nanosleep(&wait_info, null);
            c.*.write("test 1", "hello from pub2", chebi.message.Type.text) catch |err| {
                if (err == client.Error.errno) {
                    std.debug.print("{s} [ERROR] posix.errno: {}\n", .{ name, std.posix.errno(-1) });
                } else {
                    std.debug.print("{s} [ERROR] simple write err: {any}.\n", .{ name, err });
                }
                return;
            };
        }
    }
    std.debug.print("{s} finished small buffer.\n", .{name});
}

// Send 1GB of the letter E.
// Sending to topic "test 2"
fn bulk_write(c: *client.Client) !void {
    const wait_info: std.c.timespec = .{
        .sec = 1,
        .nsec = std.time.ms_per_s * 500,
    };
    var topic_name: []u8 = try alloc.alloc(u8, 6);
    topic_name[0] = 't';
    topic_name[1] = 'e';
    topic_name[2] = 's';
    topic_name[3] = 't';
    topic_name[4] = ' ';
    topic_name[5] = '2';
    const large_buffer: []u8 = try alloc.alloc(u8, 1_000_000);
    @memset(large_buffer, 'E');

    var msg = chebi.message.Message.init_with_body_no_copy(
        alloc,
        topic_name,
        large_buffer,
        chebi.message.Type.text,
    );
    defer msg.deinit();

    std.debug.print("{s} sending 1GB buffer.\n", .{name});
    for (0..n) |_| {
        if (running) {
            _ = std.c.nanosleep(&wait_info, null);
            c.*.write_msg(&msg) catch |err| {
                if (err == client.Error.errno) {
                    std.debug.print("{s} [ERROR] posix.errno: {}\n", .{ name, std.posix.errno(-1) });
                } else {
                    std.debug.print("{s} [ERROR] bulk writer err: {any}.\n", .{ name, err });
                }
                return;
            };
        }
    }
    std.debug.print("PUB-2 finished 1GB buffer.\n", .{});
}

pub fn main() !void {
    defer alloc_deinit();
    _ = std.c.sigaction(std.c.SIG.INT, &.{
        .handler = .{ .handler = shutdown },
        .mask = empty_sig,
        .flags = 0,
    }, null);
    const addr = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 3000);
    var c = try client.Client.init(alloc, addr);
    defer c.deinit();
    c.id = 2;
    try c.connect();
    const simple_thread = try std.Thread.spawn(
        .{ .allocator = alloc },
        write_simple,
        .{&c},
    );
    const bulk_thread = try std.Thread.spawn(
        .{ .allocator = alloc },
        bulk_write,
        .{&c},
    );
    simple_thread.join();
    bulk_thread.join();
    // allow messages to fully send before closing the connection.
    const wait_info: std.c.timespec = .{
        .sec = 5,
        .nsec = 0,
    };
    _ = std.c.nanosleep(&wait_info, null);
    try c.close();
    std.debug.print("{s} has finished\n", .{name});
}
