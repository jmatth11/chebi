const std = @import("std");
const manager = @import("manager.zig");
const poll = @import("poll.zig");

const poll_ctx = poll.Poll(100);

pub const Error = error {
    listener_setup,
    listener_bind,
    listener_set_nonblock,
    listener_failed,
};

pub const Server = struct {
    alloc: std.mem.Allocator,
    manager: manager.Manager,
    poll: poll_ctx,
    listener: std.c.fd_t,
    srv_addr: std.net.Address,
    errno: usize,
    running: bool,

    pub fn init(alloc: std.mem.Allocator, port: u16) !Server {
        const result: Server = .{
            .alloc = alloc,
            .manager = manager.Manager.init(alloc),
            .poll = try poll_ctx.init(),
            .srv_addr = std.net.Address.initIp4([4]u8{0,0,0,0}, port),
            .listener = std.c.socket(
                std.c.AF.INET,
                std.c.SOCK.STREAM,
                std.c.IPPROTO.TCP,
            ),
            .errno = std.c.E.SUCCESS,
        };
        if (result.listener == -1) {
            // we use libc flag which will allow this function to figure it out
            result.errno = std.posix.errno(-1);
            return Error.listener_setup;
        }
        const bind_res: c_int = std.c.bind(
            result.listener,
            &result.srv_addr.any,
            result.srv_addr.getOsSockLen(),
        );
        if (bind_res == -1) {
            result.errno = std.posix.errno(-1);
            return Error.listener_bind;
        }
        const fcntl_res: c_int = std.c.fcntl(
            result.listener,
            std.c.F.SETFL,
            std.c.fcntl(result.listener, std.c.F.GETFL, 0) | std.posix.SOCK.NONBLOCK
        );
        if (fcntl_res == -1) {
            result.errno = std.posix.errno(-1);
            return Error.listener_set_nonblock;
        }
        return result;
    }

    pub fn listen(self: *Server) !void {
        if (std.c.listen(self.listener, std.c.SOMAXCONN) == -1) {
            self.errno = std.posix.errno(-1);
            return Error.listener_failed;
        }
        self.running = true;
        var cli_addr: std.net.Address = std.net.Address.initIp4([4]u8{0,0,0,0}, self.srv_addr.getPort());
        while (self.running) {
            const n: usize = try self.poll.wait();
            var i: usize = 0;
            while (i < n) : (i += 1) {
                const evt: std.c.epoll_event = self.poll.events[i];
                switch (evt.data.fd) {
                    self.listener => {
                        const conn_sock: std.c.fd_t = std.c.accept4(
                            self.listener,
                            &cli_addr.any, &cli_addr.getOsSockLen(),
                            std.c.SOCK.NONBLOCK,
                        );
                        // TODO implement
                    },
                }
            }
        }
    }
};
