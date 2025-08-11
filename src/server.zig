const std = @import("std");
const manager = @import("manager.zig");
const poll = @import("poll.zig");
const reader = @import("reader.zig");
const protocol = @import("protocol.zig");
const packet = @import("packet.zig");
const handler = @import("handler.zig");
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
    packetManager: packet.PacketManager,
    packetHandler: handler.PacketHandler,
    poll: poll_ctx,
    listener: std.c.fd_t,
    srv_addr: std.net.Address,
    errno: std.c.E,
    running: bool = false,

    pub fn init(alloc: std.mem.Allocator, port: u16) !Server {
        var result: Server = .{
            .alloc = alloc,
            .manager = manager.Manager.init(alloc),
            .packetManager = packet.PacketManager.init(alloc),
            .packetHandler = try handler.PacketHandler.init(alloc),
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
            std.c.fcntl(result.listener, std.c.F.GETFL, @as(c_int, 0)) | std.posix.SOCK.NONBLOCK,
        );
        if (fcntl_res == -1) {
            result.errno = std.posix.errno(-1);
            return Error.listener_set_nonblock;
        }
        try result.poll.add_listener(result.listener);
        return result;
    }

    pub fn deinit(self: *Server) void {
        self.packetManager.deinit();
        self.manager.deinit();
        // TODO probably need to handle closing all connections and epoll
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
                } else if ((evt.events & EPOLL.IN) > 0) {
                    try self.event(evt.data.fd);
                }
                if ((evt.events & (EPOLL.RDHUP | EPOLL.HUP)) > 0) {
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
                @constCast(&cli_addr.getOsSockLen()),
                std.c.SOCK.NONBLOCK,
            );
            if (conn == -1) {
                const accept_errno = std.posix.errno(-1);
                // ignore these errors because they are from setting NONBLOCK
                if (accept_errno != std.c.E.AGAIN) {
                    std.debug.print("Server accept error: {any}\n", .{accept_errno});
                    self.errno = accept_errno;
                }
                accept_running = false;
            } else {
                try self.manager.add_client(conn);
                errdefer self.manager.unsubscribe_all(conn);
                try self.poll.add_connection(conn);
                std.debug.print("adding connection {any}\n", .{conn});
            }
        }
    }

    fn remove(self: *Server, fd: std.c.fd_t) void {
        self.manager.unsubscribe_all(fd);
        std.debug.print("closing connection for {any}.\n", .{fd});
        self.poll.delete(fd) catch {
            const errno = std.posix.errno(-1);
            if (errno != std.c.E.BADF) {
                std.debug.print("poll delete failed with errno: {any}\n", .{errno});
            }
        };
        _ = std.c.close(fd);
    }

    fn event(self: *Server, fd: std.c.fd_t) !void {
        var read_running = true;
        while (read_running) {
            var packet_entry: packet.Packet = undefined;
            if (reader.next_packet(self.alloc, fd)) |pack| {
                packet_entry = pack;
            } else |err| {
                read_running = false;
                if (err == reader.Error.errno) {
                    const errno = std.posix.errno(-1);
                    if (errno == std.c.E.BADF) {
                        std.debug.print("file descriptor bad or closed abruptly: {}\n", .{fd});
                    } else {
                        std.debug.print("errno: {any}\n", .{errno});
                    }
                }
                continue;
            }
            errdefer packet_entry.deinit();
            var release_packet_entry = true;
            switch (packet_entry.header.flags.opcode) {
                protocol.OpCode.c_subscribe => {
                    const topic = try packet_entry.get_topic_name();
                    try self.manager.subscribe(
                        fd,
                        topic,
                    );
                },
                protocol.OpCode.c_unsubscribe => {
                    const topic = try packet_entry.get_topic_name();
                    std.debug.print("unsubscribe {any} from {any}.\n", .{fd, topic});
                    self.manager.unsubscribe(
                        fd,
                        topic,
                    );
                },
                protocol.OpCode.c_close => {
                    self.remove(fd);
                },
                protocol.OpCode.c_pong => {
                    std.debug.print("pong received: {any}\n", .{fd});
                    try self.manager.update_client_timestamp(fd);
                },
                protocol.OpCode.nc_continue, protocol.OpCode.nc_bin, protocol.OpCode.nc_text => {
                    release_packet_entry = false;
                    const ready_packet = try self.packetManager.store_or_pop(fd, packet_entry);
                    if (ready_packet) |p| {
                        try self.packetHandler.push(.{
                            .from = fd,
                            .collection = p,
                        });
                    }
                },
                else => {
                    std.debug.print("unsupported opcode: {any}\n", .{packet_entry.header.flags.opcode});
                },
            }
            if (release_packet_entry) {
                packet_entry.deinit();
            }
        }
        self.packetHandler.process(self.manager.topics) catch |err| {
            if (err == handler.Error.errno) {
                const errno = std.posix.errno(-1);
                std.debug.print("server errno: {any}\n", .{errno});
            }
            return err;
        };
    }
};
