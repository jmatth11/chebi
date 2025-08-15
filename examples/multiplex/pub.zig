const std = @import("std");
const chebi = @import("chebi");
const client = chebi.client;

var cond: std.Thread.Condition = .{};
var mutex: std.Thread.Mutex = .{};

// Send simple message.
fn write_simple(c: *client.Client) !void {
    mutex.lock();
    defer mutex.unlock();
    cond.wait(&mutex);
    //std.time.sleep(std.time.s_per_min * 1);
    std.debug.print("sending small buffer.\n", .{});
    c.*.write("test", "hello from pub", chebi.message.Type.text) catch |err| {
        std.debug.print("simple write err: {any}.\n", .{err});
    };
    std.debug.print("finished small buffer.\n", .{});
}

// Send 1GB of the letter E.
fn bulk_write(c: *client.Client) !void {
    var alloc = std.heap.smp_allocator;
    var topic_name: []u8 = try alloc.alloc(u8, 4);
    topic_name[0] = 't';
    topic_name[1] = 'e';
    topic_name[2] = 's';
    topic_name[3] = 't';
    const large_buffer: []u8 = try alloc.alloc(u8, 1_000_000);
    @memset(large_buffer, 'E');
    var msg = chebi.message.Message.init_with_body_no_copy(
        alloc,
        topic_name,
        large_buffer,
        chebi.message.Type.text,
    );
    defer msg.deinit();
    std.debug.print("sending 1GB buffer.\n", .{});

    // signal small message to start
    cond.signal();
    c.*.write_msg(&msg) catch |err| {
        std.debug.print("bulk writer err: {any}.\n", .{err});
    };
    std.debug.print("finished 1GB buffer.\n", .{});
}

pub fn main() !void {
    const addr = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 3000);
    var c = try client.Client.init(std.heap.smp_allocator, addr);
    defer c.deinit();
    try c.connect();
    try c.subscribe("test");
    const simple_thread = try std.Thread.spawn(
        .{ .allocator = std.heap.smp_allocator },
        write_simple,
        .{&c},
    );
    const bulk_thread = try std.Thread.spawn(
        .{ .allocator = std.heap.smp_allocator },
        bulk_write,
        .{&c},
    );
    simple_thread.join();
    bulk_thread.join();
    // allow messages to fully send before closing the connection.
    std.time.sleep(std.time.s_per_min * 10);
    try c.close();
}
