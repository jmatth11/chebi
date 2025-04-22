const std = @import("std");
const proto = @import("protocol.zig");

pub const Message = struct {
    alloc: std.mem.Allocator,
    header: proto.Protocol,
    payload: []u8,

    pub fn init(alloc: std.mem.Allocator) Message {
        return Message{
            .alloc = alloc,
            .header = proto.Protocol{},
            .payload = undefined,
        };
    }

    pub fn deinit(self: *Message) void {
        self.alloc.free(self.payload);
    }
};
