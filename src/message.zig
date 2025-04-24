const std = @import("std");
const proto = @import("protocol.zig");

pub const Message = struct {
    alloc: std.mem.Allocator,
    topic: ?[]u8,
    payload: ?[]u8,

    pub fn init(alloc: std.mem.Allocator) Message {
        return Message{
            .alloc = alloc,
            .header = null,
            .payload = null,
        };
    }

    pub fn deinit(self: *Message) void {
        if (self.topic != null) {
            self.alloc.free(self.topic);
        }
        if (self.payload != null) {
            self.alloc.free(self.payload);
        }
    }
};
