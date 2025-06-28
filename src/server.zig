const std = @import("std");
const manager = @import("manager.zig");

pub const Server = struct {
    alloc: std.mem.Allocator,
    manager: manager.Manager,

    pub fn init(alloc: std.mem.Allocator) Server {
        const result: Server = .{
            .alloc = alloc,
            .manager = manager.Manager.init(alloc),
        };
        return result;
    }

    pub fn listen(self: *Server) !void {
        // TODO
    }
};
