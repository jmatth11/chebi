const std = @import("std");
const proto = @import("protocol.zig");

/// Type enum for messages.
pub const Type = enum {
    /// Plain text format.
    text,
    /// Binary format.
    bin,
};

/// Message structure.
/// Contains type, topic name, and payload.
pub const Message = struct {
    alloc: std.mem.Allocator,
    msg_type: Type = .text,
    topic: ?[]u8 = null,
    payload: ?[]u8 = null,

    pub fn init(alloc: std.mem.Allocator) Message {
        var m: Message = .{};
        m.alloc = alloc;
        return m;
    }

    pub fn deinit(self: *Message) void {
        if (self.topic) |topic| {
            self.alloc.free(topic);
        }
        if (self.payload) |payload| {
            self.alloc.free(payload);
        }
    }
};
