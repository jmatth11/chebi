const std = @import("std");
const packet = @import("packet.zig");

pub const PacketHandler = struct {
    alloc: std.mem.Allocator,
    collection: packet.PacketCollection,

    pub fn init(alloc: std.mem.Allocator) PacketHandler {
        return .{
            .alloc = alloc,
            .collection = packet.PacketCollection.init(alloc),
        };
    }

    pub fn deinit(self: *PacketHandler) void {
        self.collection.deinit();
    }
};
