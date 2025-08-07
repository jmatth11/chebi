const std = @import("std");
const packet = @import("packet.zig");
const writer = @import("write.zig");

/// Errors with the packet handler.
pub const Error = error {
    /// This is issued if a would_block occurs.
    try_again,
};

pub const PacketHandler = struct {
    alloc: std.mem.Allocator,
    collection: packet.PacketCollection,

    pub fn init(alloc: std.mem.Allocator) PacketHandler {
        return .{
            .alloc = alloc,
            .collection = packet.PacketCollection.init(alloc),
        };
    }

    pub fn add(self: *PacketHandler, payload: packet.Packet) !void {
        // TODO figure out best way to handle this.
        // need a callback function to allow this to signal a packet being ready
        // for either the server or the client.
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
        self.collection.deinit();
    }
};
