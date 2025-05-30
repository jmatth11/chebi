const std = @import("std");
const proto = @import("protocol.zig");

/// Packet specific errors.
pub const Error = error{
    /// Invalid header length.
    invalid_header_len,
    /// Invalid body length. This can apply to both topic name and payload.
    invalid_body_len,
    /// Missing topic name for packet.
    missing_topic_name,
    /// Missing Body.
    missing_body,

    /// The topic of the packet being added to the Packet Collection does not match
    /// the topic already assigned.
    topic_mismatch,
    /// The channel of the packet being added to the Packet Collection does not
    /// match the channel already assigned.
    channel_mismatch,
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
        const topic = try entry.get_topic_name();
        const channel: u8 = @intCast(entry.header.info.channel);
        // if it's the first message, pull out metadata.
        if (self.packets.items.len == 0) {
            self.version = entry.header.flags.version;
            self.channel = channel;
            self.topic = topic;
        } else {
            if (!std.mem.eql(u8, self.topic, topic)) {
                return Error.topic_mismatch;
            }
            if (self.channel != channel) {
                return Error.channel_mismatch;
            }
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

pub const ChannelCollection = struct {
    alloc: std.mem.Allocator,
    channels: std.AutoHashMap(u7, PacketCollection),

    pub fn init(alloc: std.mem.Allocator) ChannelCollection {
        return .{
            .alloc = alloc,
            .channels = std.AutoHashMap(u7, PacketCollection).init(alloc),
        };
    }

    /// Store the given Packet based on channel value.
    /// If the PacketCollection is finished it is popped and returned, otherwise
    /// null is returned.
    pub fn store_or_pop(self: *ChannelCollection, entry: Packet) !?PacketCollection {
        var result: ?PacketCollection = null;
        const channel = entry.header.info.channel;
        const mapping: ?*PacketCollection = self.channels.getPtr(channel);
        if (mapping) |coll| {
            coll.add(entry) catch |err| {
                if (err == Error.topic_mismatch) {
                    std.debug.print("received packet not associated with previous topic.\n", .{});
                    std.debug.print("replacing packet collector to not hold on to partial messages.\n", .{});
                    coll.deinit();
                    return try self.new_or_pop(channel, entry);
                } else if (err == Error.channel_mismatch) {
                    std.debug.print("received packet not associated with previous channel.\n", .{});
                    std.debug.print("replacing packet collector to not hold on to partial messages.\n", .{});
                    coll.deinit();
                    return try self.new_or_pop(channel, entry);
                } else {
                    return err;
                }
            };
            if (entry.header.flags.fin) {
                result = coll.*;
                if (!self.channels.remove(channel)) {
                    std.debug.print("channel({d}) could not be removed.", .{channel});
                }
            }
        } else {
            result = try self.new_or_pop(channel, entry);
        }
        return result;
    }

    fn new_or_pop(self: *ChannelCollection, channel: u7, entry: Packet) !?PacketCollection {
        var result: ?PacketCollection = null;
        const pc = try PacketCollection.init_with_entry(self.alloc, entry);
        if (entry.header.flags.fin) {
            result = pc;
        } else {
            try self.channels.put(channel, pc);
        }
        return result;
    }

    /// Returns if the Channel Collection is empty or not.
    pub fn is_empty(self: *const ChannelCollection) bool {
        return self.channels.count() == 0;
    }

    pub fn deinit(self: *ChannelCollection) void {
        var vi = self.channels.valueIterator();
        while (vi.next()) |chan| {
            chan.deinit();
        }
        self.channels.deinit();
    }
};

pub const PacketManager = struct {
    alloc: std.mem.Allocator,
    collector: std.StringHashMap(std.AutoHashMap(std.c.fd_t, ChannelCollection)),

    pub fn init(alloc: std.mem.Allocator) PacketManager {
        return .{
            .alloc = alloc,
            .collector = std.StringHashMap(
                std.AutoHashMap(std.c.fd_t, ChannelCollection),
            ).init(alloc),
        };
    }

    /// Store the incoming packet for a client.
    /// If this packet is the final packet, the PacketCollection object is popped
    /// from this structure.
    /// If this packet is not the final packet, a null is returned
    pub fn store_or_pop(self: *PacketManager, client: std.c.fd_t, entry: Packet) !?PacketCollection {
        const topic = try entry.get_topic_name();
        const mapping: ?*std.AutoHashMap(std.c.fd_t, ChannelCollection) = self.collector.getPtr(topic);
        var result: ?PacketCollection = null;
        if (mapping) |cm| {
            const collector: ?*ChannelCollection = cm.getPtr(client);
            if (collector) |col| {
                result = try self.handle_packet_collection(cm, col, topic, client, entry);
            } else {
                // handling new packet collection
                if (entry.header.flags.fin) {
                    const pc = try PacketCollection.init_with_entry(self.alloc, entry);
                    result = pc;
                } else {
                    var chan = ChannelCollection.init(self.alloc);
                    _ = try chan.store_or_pop(entry);
                    try cm.put(client, chan);
                }
            }
        } else {
            result = try self.new_or_pop(topic, client, entry);
        }
        return result;
    }

    fn new_or_pop(self: *PacketManager, topic: []const u8, client: std.c.fd_t, entry: Packet) !?PacketCollection {
        var result: ?PacketCollection = null;
        if (entry.header.flags.fin) {
            const pc = try PacketCollection.init_with_entry(self.alloc, entry);
            result = pc;
        } else {
            var map = std.AutoHashMap(std.c.fd_t, ChannelCollection).init(self.alloc);
            var chan = ChannelCollection.init(self.alloc);
            _ = try chan.store_or_pop(entry);
            try map.put(client, chan);
            try self.collector.put(topic, map);
        }
        return result;
    }

    fn handle_packet_collection(
        self: *PacketManager,
        cm: *std.AutoHashMap(std.c.fd_t, ChannelCollection),
        col: *ChannelCollection,
        topic: []const u8,
        client: std.c.fd_t,
        entry: Packet,
    ) !?PacketCollection {
        var result: ?PacketCollection = null;
        result = try col.store_or_pop(entry);
        if (entry.header.flags.fin) {
            if (col.is_empty()) {
                col.deinit();
                // remove the client entry since the packet collector is finished
                if (!cm.remove(client)) {
                    std.debug.print("client({d}) could not be removed", .{client});
                }
            }
            // remove topic if it has no pending packet collectors
            if (cm.count() == 0) {
                cm.deinit();
                if (!self.collector.remove(topic)) {
                    std.debug.print("topic({s}) could not be removed", .{topic});
                }
            }
        }
        return result;
    }

    pub fn deinit(self: *PacketManager) void{
        var vi = self.collector.valueIterator();
        while (vi.next()) |client_map| {
            var cm_vi = client_map.valueIterator();
            while (cm_vi.next()) |chan_collector| {
                chan_collector.deinit();
            }
            client_map.deinit();
        }
        self.collector.deinit();
    }
};
