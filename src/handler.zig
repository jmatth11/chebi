const std = @import("std");
const packet = @import("packet.zig");
const writer = @import("write.zig");

/// Errors with the packet handler.
pub const Error = error{
    /// This is issued if a would_block occurs.
    try_again,
};

pub const PacketHandler = struct {
    alloc: std.mem.Allocator,
    collection: std.ArrayList(packet.PacketCollection),
    mutex: std.Thread.Mutex,
    pool: std.Thread.Pool,
    thread_count: usize,

    pub fn init(alloc: std.mem.Allocator) PacketHandler {
        const thread_count: usize = (try std.Thread.getCpuCount()) * 2;
        const options: std.Thread.Pool.Options = .{
            .allocator = alloc,
            .n_jobs = thread_count,
        };
        return .{
            .alloc = alloc,
            .collection = std.ArrayList(packet.PacketCollection).init(alloc),
            .pool = std.Thread.Pool.init(options),
            .mutex = .{},
            .thread_count = thread_count,
        };
    }

    pub fn push(self: *PacketHandler, entry: packet.PacketCollection) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.collection.insert(0, entry);
    }



    /// Send the packet to the given socket.
    pub fn send(self: *PacketHandler, socket: std.c.fd_t, payload: packet.Packet) !void {
        writer.write_packet(self.alloc, socket, payload) catch |err| {
            if (err == writer.Error.would_block) {
                return Error.try_again;
            }
            return err;
        };
    }

    pub fn deinit(self: *PacketHandler) void {
        if (self.collection.items.len > 0) {
            for (self.collection.items) |item| {
                item.deinit();
            }
        }
        self.collection.deinit();
    }
};
