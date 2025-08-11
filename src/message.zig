const std = @import("std");
const proto = @import("protocol.zig");
const packet = @import("packet.zig");

// The TCP MTU is 1500 so we stay within a safe limit.
const max_msg_size: u16 = 1024;

pub const Error = error{
    topic_name_dne,
    topic_name_empty,
    packet_collection_len_mismatch,
};

/// Type enum for messages.
pub const Type = enum {
    /// Plain text format.
    text,
    /// Binary format.
    bin,
};

/// Message structure.
/// Contains type, topic name, and payload.
pub const Message = struct {
    alloc: std.mem.Allocator,
    msg_type: Type = .text,
    topic: ?[]u8 = null,
    payload: ?[]u8 = null,

    pub fn init(alloc: std.mem.Allocator) Message {
        const m: Message = .{
            .alloc = alloc,
        };
        return m;
    }

    pub fn init_with_body(alloc: std.mem.Allocator, topic_name: []const u8, payload: []const u8, msg_type: Type) !Message {
        var result = Message.init(alloc);
        try result.set_body(topic_name, payload);
        result.msg_type = msg_type;
        return result;
    }

    pub fn init_with_body_no_copy(alloc: std.mem.Allocator, topic_name: []u8, payload: []u8, msg_type: Type) Message {
        var result = Message.init(alloc);
        result.topic = topic_name;
        result.payload = payload;
        result.msg_type = msg_type;
        return result;
    }

    pub fn set_body(self: *Message, topic_name: []const u8, payload: []const u8) !void {
        if (topic_name.len == 0) {
            return Error.topic_name_empty;
        }
        if (self.topic) |t| {
            self.alloc.free(t);
        }
        if (self.payload) |p| {
            self.alloc.free(p);
        }
        self.topic = try self.alloc.dupe(u8, topic_name);
        self.payload = try self.alloc.dupe(u8, payload);
    }

    pub fn from_packet_collection(self: *Message, pc: packet.PacketCollection) !void {
        const topic_name = pc.topic;
        if (topic_name.len == 0) {
            return Error.topic_name_empty;
        }
        if (self.topic) |t| {
            self.alloc.free(t);
        }
        if (self.payload) |p| {
            self.alloc.free(p);
        }
        const full_size: usize = pc.payload_size();
        self.payload = try self.alloc.alloc(u8, full_size);
        var offset: usize = 0;
        for (pc.packets.items) |pack| {
            const len = pack.header.payload_len;
            const offset_len: usize = offset + len;
            if (offset_len > full_size) {
                return Error.packet_collection_len_mismatch;
            }
            @memcpy(self.payload.?[offset..offset_len], try pack.get_payload());
            offset += len;
        }
        errdefer self.alloc.free(self.payload.?);
        self.topic = try self.alloc.dupe(u8, topic_name);
        self.msg_type = switch (pc.opcode) {
            proto.OpCode.nc_bin => Type.bin,
            else => Type.text,
        };
    }

    pub fn packet_collection(self: *const Message, channel: u7) !packet.PacketCollection {
        if (self.topic == null) {
            return Error.topic_name_dne;
        }
        const topic_name = self.topic.?;
        var result = packet.PacketCollection.init(self.alloc);
        var is_single_pack: bool = true;
        if (self.payload) |body| {
            if (body.len > max_msg_size) {
                try self.generate_multi_packet(topic_name, body, channel, &result);
                is_single_pack = false;
            }
        }
        if (is_single_pack) {
            const pack = try self.generate_single_packet(topic_name, self.payload, channel);
            try result.add(pack);
        }
        return result;
    }

    pub fn deinit(self: *Message) void {
        if (self.topic) |topic| {
            self.alloc.free(topic);
        }
        if (self.payload) |payload| {
            self.alloc.free(payload);
        }
    }

    fn generate_single_packet(self: *const Message, topic_name: []const u8, body: ?[]const u8, channel: u7) !packet.Packet {
        var pack = packet.Packet.init(self.alloc);
        pack.header.flags.fin = true;
        pack.header.flags.opcode = switch (self.msg_type) {
            Type.bin => proto.OpCode.nc_bin,
            Type.text => proto.OpCode.nc_text,
        };
        pack.header.info.channel = channel;
        if (body) |b| {
            _ = try pack.set_body(topic_name, b);
        } else {
            _ = try pack.set_topic(topic_name);
        }
        return pack;
    }

    fn generate_multi_packet(self: *const Message, topic_name: []const u8, body: []const u8, channel: u7, result: *packet.PacketCollection) !void {
        const body_len = body.len;
        var offset: usize = 0;
        var offset_len: usize = max_msg_size;
        while (offset < body_len) {
            var pack = packet.Packet.init(self.alloc);
            if (offset_len >= body_len) {
                pack.header.flags.fin = true;
                pack.header.flags.opcode = switch (self.msg_type) {
                    Type.bin => proto.OpCode.nc_bin,
                    Type.text => proto.OpCode.nc_text,
                };
                offset_len = body_len;
            } else {
                pack.header.flags.fin = false;
                pack.header.flags.opcode = proto.OpCode.nc_continue;
            }
            pack.header.info.channel = channel;
            _ = try pack.set_body(topic_name, body[offset..offset_len]);
            try result.add(pack);
            offset += max_msg_size;
            offset_len += max_msg_size;
        }
    }
};
