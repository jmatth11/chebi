const std = @import("std");
const proto = @import("protocol.zig");

/// Packet specific errors.
pub const Error = error {
    /// Invalid header length.
    invalid_header_len,
    /// Invalid payload length. This can apply to both topic name and payload.
    invalid_payload_len,
    /// Missing topic name for packet.
    missing_topic_name,
};

/// Packet structure to store header and payload contents.
pub const Packet = struct {
    alloc: std.mem.Allocator,
    header: proto.Protocol = .{},
    topic: ?[]u8 = null,
    payload: ?[]u8 = null,

    /// Initialize a packet.
    pub fn init(alloc: std.mem.Allocator) Packet {
        var p: Packet = .{};
        p.alloc = alloc;
        return p;
    }

    /// Initialize a packet with a given header.
    pub fn init_with_header(alloc: std.mem.Allocator, header: proto.Protocol) Packet {
        var p: Packet = .{};
        p.alloc = alloc;
        p.header = header;
        return p;
    }

    /// Parse header information from the given buffer.
    pub fn parse_header(self: *Packet, buf: []u8) !usize {
        if (buf.len < 6) {
            return Error.invalid_header_len;
        }
        self.header.parse_flags(buf[0]);
        self.header.parse_info(buf[1]);
        if (self.header.info.mask){
            if (buf.len < 10) {
                return Error.invalid_header_len;
            }
        }
        // plus 2 for the 2 bytes above.
        return self.header.parse_body_info(buf[2..]) + 2;
    }

    /// Read the topic name and body of the given buffer.
    pub fn read(self: *Packet, buf: []u8) !usize {
        if (buf.len < (self.header.topic_len + self.header.payload_len)) {
            return Error.invalid_payload_len;
        }
        self.topic = try self.alloc.alloc(u8, self.header.topic_len);
        @memcpy(self.topic, buf);
        self.payload = try self.alloc.alloc(u8, self.header.payload_len);
        @memcpy(self.payload, buf[self.header.topic_len..]);
        return self.topic.?.len + self.payload.?.len;
    }

    /// Deinitialize internals.
    pub fn deinit(self: *Packet) void {
        if (self.topic) |topic| {
            self.alloc.free(topic);
        }
        if (self.payload) |payload| {
            self.alloc.free(payload);
        }
    }
};

/// Packet Collection structure to hold multiple packets of a large message.
pub const PacketCollection = struct {
    alloc: std.mem.Allocator,
    opcode: proto.OpCode = proto.OpCode.nc_continue,
    version: u8 = 0,
    channel: u8 = 0,
    topic: []u8,
    packets: std.ArrayList(Packet) = undefined,

    pub fn init(alloc: std.mem.Allocator) !PacketCollection {
        var pc: PacketCollection = .{};
        pc.alloc = alloc;
        pc.packets = std.ArrayList(Packet).init(alloc);
        return pc;
    }

    pub fn init_with_entry(alloc: std.mem.Allocator, entry: Packet) !PacketCollection {
        var pc: PacketCollection = .{};
        pc.alloc = alloc;
        pc.packets = std.ArrayList(Packet).init(alloc);
        try pc.add(entry);
        return pc;
    }

    pub fn add(self: *PacketCollection, entry: Packet) !void {
        // if it's the first message, pull out metadata.
        if (self.packets.items.len == 0) {
            self.version = entry.header.flags.version;
            self.channel = entry.header.info.channel;
            if (entry.topic) |topic| {
                self.topic = topic;
            } else {
                return Error.missing_topic_name;
            }
        }
        // if it's the final message grab the opcode info.
        if (entry.header.flags.fin) {
            self.opcode = entry.header.flags.opcode;
        }
        try self.packets.append(entry);
    }

    pub fn deinit(self: *PacketCollection) void {
        for (self.packets.items) |*item| {
            item.deinit();
        }
        self.packets.deinit();
    }
};
