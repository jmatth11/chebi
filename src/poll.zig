const std = @import("std");
const EPOLL = std.os.linux.EPOLL;

pub const Error = error{
    creation_failed,
    add_failed,
    wait_failed,
};

pub const Poll = struct {
    alloc: std.mem.Allocator,
    fd: std.c.fd_t,
    events: []std.c.epoll_event,

    pub fn init(alloc: std.mem.Allocator, max_events: usize) !Poll {
        const result: Poll = .{
            .alloc = alloc,
            .fd = std.c.epoll_create1(0),
            .events = try alloc.alloc(std.c.epoll_event, max_events),
        };

        if (result.fd == -1) {
            return Error.creation_failed;
        }

        return result;
    }

    fn add_event(self: *Poll, event: *std.c.epoll_event) Error!void {
        const result = std.c.epoll_ctl(
            self.fd,
            EPOLL.CTL_ADD,
            event.data.fd,
            &event,
        );
        if (result == -1) {
            return Error.add_failed;
        }
    }

    pub fn add_listener(self: *Poll, listener: std.c.fd_t) Error!void {
        const event: std.c.epoll_event = .{
            .data = .{
                .fd = listener,
            },
            .events = EPOLL.IN,
        };
        try self.add_event(&event);
    }

    pub fn add_connection(self: *Poll, conn: std.c.fd_t) Error!void {
        const event: std.c.epoll_event = .{
            .data = .{
                .fd = conn,
            },
            .events = EPOLL.IN | EPOLL.ET,
        };
        try self.add_event(&event);
    }

    pub fn wait(self: *Poll) Error!usize {
        const result = std.c.epoll_wait(self.fd, self.events, self.events.len, 0);
        if (result == -1) {
            return Error.wait_failed;
        }
        return result;
    }

    pub fn deinit(self: *Poll) void {
        // TODO implement
    }
};
