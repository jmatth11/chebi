const std = @import("std");
const proto = @import("protocol.zig");

pub const Packet = struct {
    alloc: std.mem.Allocator,
    header: proto.Protocol = .{},
    payload: ?[]u8 = null,

    pub fn init(alloc: std.mem.Allocator) Packet {
        var p: Packet = .{};
        p.alloc = alloc;
        return p;
    }

    pub fn deinit(self: *Packet) void {
        if (self.payload) |payload| {
            self.alloc.free(payload);
        }
    }
};
