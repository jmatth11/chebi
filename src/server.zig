const std = @import("std");
const manager = @import("manager.zig");
const poll = @import("poll.zig");

const poll_ctx = poll.Poll(100);

pub const Server = struct {
    alloc: std.mem.Allocator,
    manager: manager.Manager,
    poll: poll_ctx,

    pub fn init(alloc: std.mem.Allocator) !Server {
        const result: Server = .{
            .alloc = alloc,
            .manager = manager.Manager.init(alloc),
            .poll = try poll_ctx.init(),
        };
        return result;
    }

    pub fn listen(self: *Server) !void {
        // TODO
    }
};
