const std = @import("std");
const manager = @import("manager.zig");
const poll = @import("poll.zig");
const reader = @import("reader.zig");
const protocol = @import("protocol.zig");
const EPOLL = std.os.linux.EPOLL;

const poll_ctx = poll.Poll(100);

pub const Error = error{
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
    errno: i32,
    running: bool,

    pub fn init(alloc: std.mem.Allocator, port: u16) !Server {
        const result: Server = .{
            .alloc = alloc,
            .manager = manager.Manager.init(alloc),
            .poll = try poll_ctx.init(),
            .srv_addr = std.net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, port),
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
            std.c.fcntl(result.listener, std.c.F.GETFL, 0) | std.posix.SOCK.NONBLOCK,
        );
        if (fcntl_res == -1) {
            result.errno = std.posix.errno(-1);
            return Error.listener_set_nonblock;
        }
        return result;
    }

    pub fn stop(self: *Server) void {
        self.running = false;
    }

    pub fn listen(self: *Server) !void {
        if (std.c.listen(self.listener, std.c.SOMAXCONN) == -1) {
            self.errno = std.posix.errno(-1);
            return Error.listener_failed;
        }
        self.running = true;
        while (self.running) {
            const n: usize = try self.poll.wait();
            var i: usize = 0;
            while (i < n) : (i += 1) {
                const evt: std.c.epoll_event = self.poll.events[i];
                if (evt.data.fd == self.listener) {
                    try self.accept();
                } else if (evt.events & EPOLL.IN) {
                    try self.event(evt.data.fd);
                }
                if (evt.events & (EPOLL.RDHUP | EPOLL.HUP)) {
                    self.remove(evt.data.fd);
                }
            }
        }
    }

    fn accept(self: *Server) !void {
        // keep accepting until we've accepted all connections.
        var cli_addr: std.net.Address = std.net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, self.srv_addr.getPort());
        var accept_running = true;
        while (accept_running) {
            const conn: std.c.fd_t = std.c.accept4(
                self.listener,
                &cli_addr.any,
                &cli_addr.getOsSockLen(),
                std.c.SOCK.NONBLOCK,
            );
            if (conn == -1) {
                const accept_errno = std.posix.errno(-1);
                // ignore these errors because they are from setting NONBLOCK
                if (accept_errno != std.c.E.AGAIN and accept_errno != std.c.E.WOULDBLOCK) {
                    std.debug.print("Server accept error: {}\n", .{accept_errno});
                    self.errno = accept_errno;
                }
                accept_running = false;
            } else {
                try self.manager.add_client(conn);
                errdefer self.manager.unsubscribe_all(conn);
                try self.poll.add_connection(conn);
                std.debug.print("adding connection {}\n", .{conn});
            }
        }
    }

    fn remove(self: *Server, fd: std.c.fd_t) void {
        self.manager.unsubscribe_all(fd);
        std.debug.print("closing connection for {}.\n", .{fd});
        self.poll.delete(fd) catch {
            std.debug.print("poll delete failed with errno: {}\n", .{std.posix.errno()});
        };
        std.c.close(fd);
    }

    fn event(self: *Server, fd: std.c.fd_t) !void {
        var read_running = true;
        while (read_running) {
            const packet = reader.next_packet(self.alloc, fd) catch |err| {
                read_running = false;
                if (err == reader.Error.errno) {
                    std.debug.print("errno: {}\n", .{std.posix.errno()});
                } else if (err == reader.Error.would_block) {
                    std.debug.print("packet error: {}\n", .{err});
                }
            };
            errdefer packet.deinit();
            var release_packet = true;
            switch (packet.header.flags.opcode) {
                protocol.OpCode.c_subscribe => {
                    try self.manager.subscribe(
                        fd,
                        try packet.get_topic_name(),
                    );
                },
                protocol.OpCode.c_unsubscribe => {
                    self.manager.unsubscribe(
                        fd,
                        try packet.get_topic_name(),
                    );
                },
                protocol.OpCode.c_close => {
                    self.manager.unsubscribe_all(fd);
                    std.debug.print("closing connection for {}.\n", .{fd});
                    self.poll.delete(fd);
                    std.c.close(fd);
                },
                protocol.OpCode.c_pong => {
                    std.debug.print("pong received: {}\n", .{fd});
                    // TODO implement timestamp to update
                },
                protocol.OpCode.nc_continue => {},
                protocol.OpCode.nc_bin, protocol.OpCode.nc_text => {
                    release_packet = true;
                },
                else => {
                    std.debug.print("unsupported opcode: {}\n", .{packet.header.flags.opcode});
                },
            }
            if (release_packet) {
                packet.deinit();
            }
        }
    }
};
