const std = @import("std");
const proto = @import("protocol.zig");
const packet = @import("packet.zig");
const compression = @import("compression.zig");

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
    /// Compressed format. Uses the compression_type value.
    /// Use this type to let the client assign the compression type properly.
    compressed,
};

/// Message structure.
/// Contains type, topic name, and payload.
pub const Message = struct {
    alloc: std.mem.Allocator,
    /// The message type.
    msg_type: Type = .text,
    /// The topic name.
    topic: ?[]const u8 = null,
    /// The payload.
    payload: ?[]const u8 = null,

    /// Compression type to use.
    /// This will typically be set by the client.
    compression_type: compression.CompressionType = .raw,

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

    pub fn init_with_body_no_copy(alloc: std.mem.Allocator, topic_name: []const u8, payload: []const u8, msg_type: Type) Message {
        var result = Message.init(alloc);
        result.topic = topic_name;
        result.payload = payload;
        result.msg_type = msg_type;
        return result;
    }

    /// Set the compression type.
    /// This method also sets the message type to compressed.
    /// This does not need to be called before sending to the client.
    /// Setting the message type to .compressed will tell the client to set the compression.
    pub fn set_compression(self: *Message, compression_type: compression.CompressionType) void {
        self.msg_type = .compressed;
        self.compression_type = compression_type;
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
        const payload = try self.alloc.alloc(u8, full_size);
        var offset: usize = 0;
        for (pc.packets.items) |pack| {
            const len = pack.header.payload_len;
            const offset_len: usize = offset + len;
            if (offset_len > full_size) {
                return Error.packet_collection_len_mismatch;
            }
            @memcpy(payload[offset..offset_len], try pack.get_payload());
            offset += len;
        }
        if (self.compression_type != .raw and pc.is_compressed()) {
            defer self.alloc.free(payload);
            self.payload = try compression.decompress(
                self.alloc,
                self.compression_type,
                payload,
            );
        } else {
            self.payload = payload;
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
        // TODO implement compression
        var is_single_pack: bool = true;
        if (self.payload) |body| {
            var local_body = body;
            if (self.compression_type != .raw) {
                local_body = try compression.compress(self.alloc, self.compression_type, local_body);
            }
            if (local_body.len > max_msg_size) {
                try self.generate_multi_packet(topic_name, local_body, channel, &result);
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
            Type.bin, Type.compressed => proto.OpCode.nc_bin,
            Type.text => proto.OpCode.nc_text,
        };
        pack.header.info.channel = channel;
        if (body) |b| {
            var local_body = b;
            if (self.compression_type != .raw) {
                pack.header.info.compressed = true;
                local_body = try compression.compress(self.alloc, self.compression_type, local_body);
            }
            _ = try pack.set_body(topic_name, local_body);
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
                    Type.bin, Type.compressed => proto.OpCode.nc_bin,
                    Type.text => proto.OpCode.nc_text,
                };
                offset_len = body_len;
            } else {
                pack.header.flags.fin = false;
                pack.header.flags.opcode = proto.OpCode.nc_continue;
            }
            pack.header.info.channel = channel;
            pack.header.info.compressed = self.compression_type != .raw;
            _ = try pack.set_body(topic_name, body[offset..offset_len]);
            try result.add(pack);
            offset += max_msg_size;
            offset_len += max_msg_size;
        }
    }
};
