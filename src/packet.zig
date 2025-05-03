const std = @import("std");
const proto = @import("protocol.zig");

/// Packet specific errors.
pub const Error = error {
    /// Invalid header length.
    invalid_header_len,
    /// Invalid body length. This can apply to both topic name and payload.
    invalid_body_len,
    /// Missing topic name for packet.
    missing_topic_name,
    /// Missing Body.
    missing_body,
};

/// Packet structure to store header and payload contents.
pub const Packet = struct {
    alloc: std.mem.Allocator,
    header: proto.Protocol = .{},
    body: ?[]u8 = null,

    /// Initialize a packet.
    pub fn init(alloc: std.mem.Allocator) Packet {
        return .{
            .alloc = alloc,
        };
    }

    /// Initialize a packet with a given header.
    pub fn init_with_header(alloc: std.mem.Allocator, header: proto.Protocol) Packet {
        var p: Packet = Packet.init(alloc);
        p.header = header;
        return p;
    }

    /// Peek header information.
    pub fn peek_header(self: *Packet, buf: [2]u8) void {
        self.header.parse_flags(buf[0]);
        self.header.parse_info(buf[1]);
    }

    /// Parse header information from the given buffer.
    pub fn parse_header(self: *Packet, buf: []const u8) !usize {
        if (buf.len < 6) {
            return Error.invalid_header_len;
        }
        self.header.parse_flags(buf[0]);
        self.header.parse_info(buf[1]);
        const body_size: usize = try self.header.parse_body_info(buf[2..]);
        // plus 2 for the 2 bytes above.
        return body_size + 2;
    }

    /// Get the topic name from the body.
    pub fn get_topic_name(self: *const Packet) Error![]const u8 {
        if (self.body) |body| {
            if (body.len < self.header.topic_len) {
                return Error.invalid_body_len;
            }
            return body[0..self.header.topic_len];
        }
        return Error.missing_body;
    }

    /// Get the payload from the body.
    pub fn get_payload(self: *const Packet) Error![]const u8 {
        if (self.body) |body| {
            if (body.len < (self.header.topic_len + self.header.payload_len)) {
                return Error.invalid_body_len;
            }
            return body[self.header.topic_len..];
        }
        return Error.missing_body;
    }

    /// Deinitialize internals.
    pub fn deinit(self: *Packet) void {
        if (self.body) |body| {
            self.alloc.free(body);
            self.body = null;
        }
    }
};

/// Packet Collection structure to hold multiple packets of a large message.
pub const PacketCollection = struct {
    alloc: std.mem.Allocator,
    opcode: proto.OpCode = proto.OpCode.nc_continue,
    version: u8 = 0,
    channel: u8 = 0,
    topic: []const u8 = undefined,
    packets: std.ArrayList(Packet) = undefined,

    /// Init an empty packet collection.
    pub fn init(alloc: std.mem.Allocator) PacketCollection {
        var pc: PacketCollection = .{
            .alloc = alloc,
        };
        pc.packets = std.ArrayList(Packet).init(alloc);
        return pc;
    }

    /// Init with a given entry.
    pub fn init_with_entry(alloc: std.mem.Allocator, entry: Packet) !PacketCollection {
        var pc: PacketCollection = PacketCollection.init(alloc);
        try pc.add(entry);
        return pc;
    }

    /// Add the given entry to the collection, pulling out relevant information.
    pub fn add(self: *PacketCollection, entry: Packet) !void {
        // if it's the first message, pull out metadata.
        if (self.packets.items.len == 0) {
            self.version = entry.header.flags.version;
            self.channel = entry.header.info.channel;
            self.topic = try entry.get_topic_name();
        }
        // if it's the final message grab the opcode info.
        if (entry.header.flags.fin) {
            self.opcode = entry.header.flags.opcode;
        }
        try self.packets.append(entry);
    }

    /// Get the entire payload size of all packets.
    pub fn payload_size(self: *const PacketCollection) usize {
        var result: usize = 0;
        for (self.packets.items) |item| {
            result += item.header.payload_len;
        }
        return result;
    }

    /// Deinitialize internals.
    pub fn deinit(self: *PacketCollection) void {
        for (self.packets.items) |*item| {
            item.deinit();
        }
        self.packets.deinit();
    }
};
