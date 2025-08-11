const std = @import("std");
const packet = @import("packet.zig");
const protocol = @import("protocol.zig");
const writer = @import("write.zig");
const message = @import("message.zig");
const reader = @import("reader.zig");

/// Errors related to the Client.
pub const Error = error{
    /// The operation would have blocked.
    would_block,

    /// Error with the listener setup.
    listener_setup,
    /// Error with connecting to the server.
    server_connection,
    /// The topic name was empty.
    topic_name_empty,
};

/// Simple Client to interact with the Server.
pub const Client = struct {
    alloc: std.mem.Allocator,
    listener: std.c.fd_t = -1,
    srv_addr: std.net.Address,
    packetManager: packet.PacketManager,
    errno: std.c.E = std.c.E.SUCCESS,
    channel: std.atomic.Value(u8),

    /// Initialize Client with allocator and Address.
    pub fn init(alloc: std.mem.Allocator, srv_addr: std.net.Address) !Client {
        var result: Client = .{
            .alloc = alloc,
            .srv_addr = srv_addr,
            .listener = std.c.socket(
                std.c.AF.INET,
                std.c.SOCK.STREAM,
                std.c.IPPROTO.TCP,
            ),
            .packetManager = packet.PacketManager.init(alloc),
            .channel = std.atomic.Value(u8).init(0),
        };
        if (result.listener == -1) {
            result.errno = std.posix.errno(-1);
            return Error.listener_setup;
        }
        return result;
    }

    /// Deinit Client internals.
    pub fn deinit(self: *Client) void {
        if (self.listener == -1) {
            return;
        }
        self.close() catch |err| {
            std.debug.print("error closing client: {any}\n", .{err});
        };
        self.packetManager.deinit();
    }

    /// Connect to the server.
    pub fn connect(self: *Client) !void {
        // TODO add ability to pass connection options like max_msg_size
        try self.connect_to_server();
    }

    /// Subscribe to a topic.
    pub fn subscribe(self: *Client, topic_name: []const u8) !void {
        var pack = packet.Packet.init(self.alloc);
        defer pack.deinit();
        _ = try pack.set_topic(topic_name);
        pack.header.flags.fin = true;
        pack.header.flags.opcode = protocol.OpCode.c_subscribe;
        pack.header.info.channel = self.get_channel();
        pack.header.info.compressed = false;
        writer.write_packet(self.alloc, self.listener, pack) catch |err| {
            if (err == writer.Error.would_block) {
                return Error.would_block;
            }
            return err;
        };
    }

    /// Unsubscribe from a topic.
    pub fn unsubscribe(self: *Client, topic_name: []const u8) !void {
        var pack = packet.Packet.init(self.alloc);
        defer pack.deinit();
        _ = try pack.set_topic(topic_name);
        pack.header.flags.fin = true;
        pack.header.flags.opcode = protocol.OpCode.c_unsubscribe;
        pack.header.info.channel = self.get_channel();
        pack.header.info.compressed = false;
        writer.write_packet(self.alloc, self.listener, pack) catch |err| {
            if (err == writer.Error.would_block) {
                return Error.would_block;
            }
            return err;
        };
    }

    /// Send a ping to the server.
    pub fn ping(self: *Client) !void {
        var pack = packet.Packet.init(self.alloc);
        defer pack.deinit();
        pack.header.flags.fin = true;
        pack.header.flags.opcode = protocol.OpCode.c_ping;
        pack.header.info.channel = self.get_channel();
        pack.header.info.compressed = false;
        writer.write_packet(self.alloc, self.listener, pack) catch |err| {
            if (err == writer.Error.would_block) {
                return Error.would_block;
            }
            return err;
        };
    }

    /// Write a given payload to the topic.
    pub fn write(self: *Client, topic_name: []const u8, payload: []const u8, msg_type: message.Type) !void {
        // use arena for message allocator
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        // TODO switch to use a no-copy version of Message
        const msg = try message.Message.init_with_body(arena.allocator(), topic_name, payload, msg_type);
        try self.write_msg(msg);
    }

    /// Write a Message structure to the server.
    pub fn write_msg(self: *Client, msg: message.Message) !void {
        const channel = self.get_channel();
        var pc = try msg.packet_collection(channel);
        defer pc.deinit();
        for (pc.packets.items) |pack| {
            writer.write_packet(self.alloc, self.listener, pack) catch |err| {
                if (err == writer.Error.would_block) {
                    return Error.would_block;
                }
                return err;
            };
        }
    }

    /// Read the next complete message from the server.
    pub fn next_msg(self: *Client) !message.Message {
        var received: bool = false;
        var msg = message.Message.init(self.alloc);
        while (!received) {
            const pack = try self.read_packet();
            const col = try self.packetManager.store_or_pop(self.listener, pack);
            if (col) |c| {
                received = true;
                try msg.from_packet_collection(c);
            }
        }
        return msg;
    }

    fn read_packet(self: *Client) !packet.Packet {
        return try reader.next_packet(self.alloc, self.listener);
    }

    /// Close the connection.
    pub fn close(self: *Client) !void {
        var pack = packet.Packet.init(self.alloc);
        defer pack.deinit();
        pack.header.flags.fin = true;
        pack.header.flags.opcode = protocol.OpCode.c_close;
        pack.header.info.channel = self.get_channel();
        pack.header.info.compressed = false;
        writer.write_packet(self.alloc, self.listener, pack) catch |err| {
            if (err == writer.Error.would_block) {
                return Error.would_block;
            }
            return err;
        };
        _ = std.c.close(self.listener);
        self.listener = -1;
    }

    fn connect_to_server(self: *Client) !void {
        const c_err = std.c.connect(
            self.listener,
            &self.srv_addr.any,
            self.srv_addr.getOsSockLen(),
        );
        if (c_err == -1) {
            self.errno = std.posix.errno(-1);
            return Error.server_connection;
        }
    }

    fn get_channel(self: *Client) u7 {
        const a_val = self.channel.fetchAdd(1, .acq_rel);
        // use mask to reset value once it overflows
        const masked = a_val & 0b01111111;
        const result: u7 = @intCast(masked);
        if (a_val > 127) {
            _ = self.channel.cmpxchgStrong(a_val, 0, .acq_rel, .monotonic);
        }
        return result;
    }
};
