const std = @import("std");
const packet = @import("packet.zig");
const protocol = @import("protocol.zig");
const writer = @import("write.zig");

pub const Error = error{
    listener_setup,
    server_connection,
    topic_name_empty,
};

const max_msg_size: u16 = 1450;

pub const Client = struct {
    alloc: std.mem.Allocator,
    listener: std.c.fd_t = -1,
    srv_addr: std.net.Address,
    errno: i32 = 0,
    channel: u8 = 0,

    pub fn init(alloc: std.mem.Allocator, srv_addr: std.net.Address) !Client {
        const result: Client = .{
            .alloc = alloc,
            .srv_addr = srv_addr,
            .listener = std.c.socket(
                std.c.AF.INET,
                std.c.SOCK.STREAM,
                std.c.IPPROTO.TCP,
            ),
        };
        if (result.listener == -1) {
            result.errno = std.posix.errno(-1);
            return Error.listener_setup;
        }
        return result;
    }

    pub fn deinit(self: *Client) void {
        if (self.listener == -1) {
            return;
        }
        self.close() catch |err| {
            std.debug.print("error closing client: {}\n", .{err});
        };
    }

    pub fn connect(self: *Client) !void {
        try self.connect_to_server();
    }

    pub fn subscribe(self: *Client, topic_name: []const u8) !void {
        const pack = packet.Packet.init(self.alloc);
        defer pack.deinit();
        _ = try pack.set_topic(topic_name);
        pack.header.flags.fin = true;
        pack.header.flags.opcode = protocol.OpCode.c_subscribe;
        pack.header.info.channel = self.get_channel();
        pack.header.info.compressed = false;
        writer.write_packet(self.listener, pack) catch |err| {
            if (err == writer.Error.would_block) {
                std.debug.print("writer would block\n", .{});
            }
            return err;
        };
    }

    pub fn unsubscribe(self: *Client, topic_name: []const u8) !void {
        const pack = packet.Packet.init(self.alloc);
        defer pack.deinit();
        _ = try pack.set_topic(topic_name);
        pack.header.flags.fin = true;
        pack.header.flags.opcode = protocol.OpCode.c_unsubscribe;
        pack.header.info.channel = self.get_channel();
        pack.header.info.compressed = false;
        writer.write_packet(self.listener, pack) catch |err| {
            if (err == writer.Error.would_block) {
                std.debug.print("writer would block\n", .{});
            }
            return err;
        };
    }

    pub fn ping(self: *Client) !void {
        const pack = packet.Packet.init(self.alloc);
        defer pack.deinit();
        pack.header.flags.fin = true;
        pack.header.flags.opcode = protocol.OpCode.c_ping;
        pack.header.info.channel = self.get_channel();
        pack.header.info.compressed = false;
        writer.write_packet(self.listener, pack) catch |err| {
            if (err == writer.Error.would_block) {
                std.debug.print("writer would block\n", .{});
            }
            return err;
        };
    }

    pub fn write(self: *Client, topic_name: []const u8, payload: []const u8) !void {
        if (topic_name.len == 0) {
            return Error.topic_name_empty;
        }
    }

    pub fn close(self: *Client, topic_name: []const u8) !void {
        const pack = packet.Packet.init(self.alloc);
        defer pack.deinit();
        _ = try pack.set_topic(topic_name);
        pack.header.flags.fin = true;
        pack.header.flags.opcode = protocol.OpCode.c_unsubscribe;
        pack.header.info.channel = self.get_channel();
        pack.header.info.compressed = false;
        writer.write_packet(self.listener, pack) catch |err| {
            if (err == writer.Error.would_block) {
                std.debug.print("writer would block\n", .{});
            }
            return err;
        };
        std.c.close(self.listener);
    }

    fn connect_to_server(self: *Client) !void {
        self.errno = std.c.connect(self.listener, self.srv_addr.any, self.srv_addr.getOsSockLen());
        if (self.errno == -1) {
            self.errno = std.posix.errno(-1);
            return Error.server_connection;
        }
    }

    fn get_channel(self: *Client) u8 {
        const result = self.channel;
        self.channel = self.channel + 1;
        // use mask to reset value once it overflows
        self.channel = self.channel & 0b01111111;
        return result;
    }
};
