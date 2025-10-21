const std = @import("std");
const EPOLL = std.os.linux.EPOLL;

/// Error constants for Poll structure.
pub const Error = error{
    creation_failed,
    sig_mask_failure,
    sig_mask_set_failure,
    add_failed,
    wait_failed,
    wake_failed,
    delete_failed,
};

/// Poll structure to handle polling events.
pub fn Poll(comptime max_events: comptime_int) type {
    return struct {
        fd: std.c.fd_t,
        events: [max_events]std.c.epoll_event,
        sig_mask: std.c.sigset_t,
        const Self = @This();

        /// Initialize Poll structure with the max amount of events to handle at a time.
        pub fn init() Error!Self {
            var result: Self = .{
                .fd = std.c.epoll_create1(0),
                .events = undefined,
                .sig_mask = undefined,
            };
            if (result.fd == -1) {
                return Error.creation_failed;
            }
            try result.sigmask_clear();
            return result;
        }

        fn add_event(self: *Self, event: *std.c.epoll_event) Error!void {
            const result = std.c.epoll_ctl(
                self.fd,
                EPOLL.CTL_ADD,
                event.data.fd,
                event,
            );
            if (result == -1) {
                return Error.add_failed;
            }
        }

        /// Add signal for the poll to be aware of.
        /// This allows the poll to respond to things like SIGINT or any other signal you want.
        pub fn sigmask_add(self: *Self, signal: c_int) Error!void {
            const sig_result = std.c.sigaddset(&self.sig_mask, signal);
            if (sig_result == -1) {
                return Error.sig_mask_set_failure;
            }
        }

        /// Clear out the sigmask of any set signals.
        pub fn sigmask_clear(self: *Self) Error!void {
            const sig_result = std.c.sigemptyset(&self.sig_mask);
            if (sig_result == -1) {
                return Error.sig_mask_set_failure;
            }
        }

        /// Add a listener for the Polling operations.
        pub fn add_listener(self: *Self, listener: std.c.fd_t) Error!void {
            var event: std.c.epoll_event = .{
                .data = .{
                    .fd = listener,
                },
                .events = EPOLL.IN | EPOLL.OUT | EPOLL.ET,
            };
            try self.add_event(&event);
        }

        /// Add a connection to monitor events on.
        pub fn add_connection(self: *Self, conn: std.c.fd_t) Error!void {
            var event: std.c.epoll_event = .{
                .data = .{
                    .fd = conn,
                },
                .events = EPOLL.IN | EPOLL.OUT | EPOLL.ET | EPOLL.RDHUP | EPOLL.HUP,
            };
            try self.add_event(&event);
        }

        /// Wait for events.
        /// Return the number of events the Poll has received.
        pub fn wait(self: *Self) Error!usize {
            const c_result = std.c.epoll_pwait(
                self.fd,
                &self.events,
                self.events.len,
                -1,
                &self.sig_mask,
            );
            if (c_result == -1) {
                return Error.wait_failed;
            }
            return @intCast(c_result);
        }

        /// Delete file descriptor from poll.
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
