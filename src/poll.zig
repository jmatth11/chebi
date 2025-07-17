const std = @import("std");
const EPOLL = std.os.linux.EPOLL;

/// Error constants for Poll structure.
pub const Error = error{
    creation_failed,
    add_failed,
    wait_failed,
    delete_failed,
};

/// Poll structure to handle polling events.
pub fn Poll(comptime max_events: comptime_int) type {
    return struct {
        fd: std.c.fd_t,
        events: [max_events]std.c.epoll_event,
        const Self = @This();

        /// Initialize Poll structure with the max amount of events to handle at a time.
        pub fn init() Error!Self {
            const result: Self = .{
                .fd = std.c.epoll_create1(0),
                .events = undefined,
            };
            if (result.fd == -1) {
                return Error.creation_failed;
            }
            return result;
        }

        fn add_event(self: *Self, event: *std.c.epoll_event) Error!void {
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

        /// Add a listener for the Polling operations.
        pub fn add_listener(self: *Self, listener: std.c.fd_t) Error!void {
            const event: std.c.epoll_event = .{
                .data = .{
                    .fd = listener,
                },
                .events = EPOLL.IN | EPOLL.OUT | EPOLL.ET,
            };
            try self.add_event(&event);
        }

        /// Add a connection to monitor events on.
        pub fn add_connection(self: *Self, conn: std.c.fd_t) Error!void {
            const event: std.c.epoll_event = .{
                .data = .{
                    .fd = conn,
                },
                .events = EPOLL.IN | EPOLL.ET | EPOLL.RDHUP | EPOLL.HUP,
            };
            try self.add_event(&event);
        }

        /// Wait for events.
        /// Return the number of events the Poll has received.
        pub fn wait(self: *Self) Error!usize {
            const result = std.c.epoll_wait(self.fd, self.events, self.events.len, 0);
            if (result == -1) {
                return Error.wait_failed;
            }
            return result;
        }

        pub fn delete(self: *Self, conn: std.c.fd_t) !void {
            const result = std.c.epoll_ctl(
                self.fd,
                EPOLL.CTL_DEL,
                conn,
                null,
            );
            if (result == -1) {
                return Error.delete_failed;
            }
        }
    };
}
