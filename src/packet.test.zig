const std = @import("std");
const packet = @import("packet.zig");
const proto = @import("protocol.zig");

// --------- Packet ---------

test "Packet.init sanity check" {
    const p = packet.Packet.init(std.testing.allocator);
    try std.testing.expectEqual(std.testing.allocator, p.alloc);
}

test "Packet.init_with_header sanity check" {
    const header: proto.Protocol = .{};
    const p = packet.Packet.init_with_header(
        std.testing.allocator,
        header,
    );
    try std.testing.expectEqual(header, p.header);
    try std.testing.expectEqual(std.testing.allocator, p.alloc);
}

test "Packet.peek_header success" {
    const header: proto.Protocol = .{};
    var p = packet.Packet.init_with_header(
        std.testing.allocator,
        header,
    );
    const buf: [2]u8 = [_]u8 {
        0b10100001,
        0b10000101,
    };
    p.peek_header(buf);
    try std.testing.expectEqual(true, p.header.flags.fin);
    try std.testing.expectEqual(2, p.header.flags.version);
    try std.testing.expectEqual(proto.OpCode.nc_text, p.header.flags.opcode);
    try std.testing.expectEqual(true, p.header.info.compressed);
    try std.testing.expectEqual(5, p.header.info.channel);
}

test "Packet.parse_header success" {
    const header: proto.Protocol = .{};
    var p = packet.Packet.init_with_header(
        std.testing.allocator,
        header,
    );
    const buf: [6]u8 = [_]u8 {
        0b10100001,
        0b10000101,
        // topic len
        0b10000000,
        0b00000000,
        // payload len
        0b00000001,
        0b00000010,
    };
    const result: usize = try p.parse_header(&buf);
    try std.testing.expectEqual(6, result);
    try std.testing.expectEqual(true, p.header.flags.fin);
    try std.testing.expectEqual(2, p.header.flags.version);
    try std.testing.expectEqual(proto.OpCode.nc_text, p.header.flags.opcode);
    try std.testing.expectEqual(true, p.header.info.compressed);
    try std.testing.expectEqual(5, p.header.info.channel);
    try std.testing.expectEqual(128, p.header.topic_len);
    try std.testing.expectEqual(513, p.header.payload_len);
}

test "Packet.parse_header empty header" {
    const header: proto.Protocol = .{};
    var p = packet.Packet.init_with_header(
        std.testing.allocator,
        header,
    );
    const buf: [0]u8 = [_]u8 {};
    try std.testing.expectError(
        packet.Error.invalid_header_len,
        p.parse_header(&buf)
    );
}

test "Packet.parse_header header length is shorter than standard length" {
    const header: proto.Protocol = .{};
    var p = packet.Packet.init_with_header(
        std.testing.allocator,
        header,
    );
    const buf: [5]u8 = [_]u8 {0,0,0,0,0};
    try std.testing.expectError(
        packet.Error.invalid_header_len,
        p.parse_header(&buf)
    );
}

test "Packet.get_topic_name success" {
    var p = packet.Packet.init(
        std.testing.allocator,
    );
    const topic = "test";
    const body = "hello, world!";
    const payload = "testhello, world!";
    p.header.topic_len = topic.len;
    p.header.payload_len = body.len;
    p.body = try std.testing.allocator.alloc(u8, topic.len + body.len);
    defer std.testing.allocator.free(p.body.?);
    @memcpy(p.body.?, payload);
    const result = try p.get_topic_name();
    const topic_cast: [*:0]const u8 = topic;
    const expected_topic: []const u8 = std.mem.span(topic_cast);
    try std.testing.expectEqualSlices(u8, expected_topic, result);
}

test "Packet.get_topic_name invalid body length" {
    var p = packet.Packet.init(
        std.testing.allocator,
    );
    const topic = "test";
    const body = "hello, world!";
    p.header.topic_len = topic.len;
    p.header.payload_len = body.len;
    p.body = try std.testing.allocator.alloc(u8, 1);
    defer std.testing.allocator.free(p.body.?);
    @memcpy(p.body.?, "a");
    try std.testing.expectError(packet.Error.invalid_body_len, p.get_topic_name());
}

test "Packet.get_topic_name null body" {
    var p = packet.Packet.init(
        std.testing.allocator,
    );
    const topic = "test";
    const body = "hello, world!";
    p.header.topic_len = topic.len;
    p.header.payload_len = body.len;
    try std.testing.expectError(packet.Error.missing_body, p.get_topic_name());
}

test "Packet.get_payload success" {
    var p = packet.Packet.init(
        std.testing.allocator,
    );
    const topic = "test";
    const body = "hello, world!";
    const payload = "testhello, world!";
    p.header.topic_len = topic.len;
    p.header.payload_len = body.len;
    p.body = try std.testing.allocator.alloc(u8, topic.len + body.len);
    defer std.testing.allocator.free(p.body.?);
    @memcpy(p.body.?, payload);
    const result = try p.get_payload();
    const payload_cast: [*:0]const u8 = body;
    const expected_payload: []const u8 = std.mem.span(payload_cast);
    try std.testing.expectEqualSlices(u8, expected_payload, result);
}

test "Packet.get_payload invalid body length" {
    var p = packet.Packet.init(
        std.testing.allocator,
    );
    const topic = "test";
    const body = "hello, world!";
    p.header.topic_len = topic.len;
    p.header.payload_len = body.len;
    p.body = try std.testing.allocator.alloc(u8, topic.len);
    defer std.testing.allocator.free(p.body.?);
    @memcpy(p.body.?, topic);
    try std.testing.expectError(packet.Error.invalid_body_len, p.get_payload());
}


test "Packet.get_payload null body" {
    var p = packet.Packet.init(
        std.testing.allocator,
    );
    const topic = "test";
    const body = "hello, world!";
    p.header.topic_len = topic.len;
    p.header.payload_len = body.len;
    try std.testing.expectError(packet.Error.missing_body, p.get_payload());
}

test "Packet.deinit sanity check" {
    var p = packet.Packet.init(
        std.testing.allocator,
    );
    const payload = "testhello, world!";
    p.body = try std.testing.allocator.alloc(u8, payload.len);
    @memcpy(p.body.?, payload);
    p.deinit();
    try std.testing.expect(p.body == null);
}

// --------- Packet Collection ---------

test "PacketCollection.init sanity check" {
    const pc = packet.PacketCollection.init(std.testing.allocator);
    try std.testing.expectEqual(std.testing.allocator, pc.alloc);
    try std.testing.expectEqual(
        std.testing.allocator,
        pc.packets.allocator,
    );
}

test "PacketCollection.init_with_entry success" {
    var entry = packet.Packet.init(std.testing.allocator);
    const buf: [2]u8 = [_]u8 {
        0b10100001,
        0b10000101,
    };
    entry.peek_header(buf);
    const topic = "test";
    const payload = "hello, world!";
    const body = "testhello, world!";
    entry.header.topic_len = topic.len;
    entry.header.payload_len = payload.len;
    entry.body = try std.testing.allocator.alloc(u8, body.len);
    @memcpy(entry.body.?, body);
    var pc = try packet.PacketCollection.init_with_entry(
        std.testing.allocator,
        entry,
    );
    defer pc.deinit();
    try std.testing.expectEqual(std.testing.allocator, pc.alloc);
    try std.testing.expectEqual(
        std.testing.allocator,
        pc.packets.allocator,
    );
    try std.testing.expectEqual(1, pc.packets.items.len);

    try std.testing.expectEqual(entry.header.flags.opcode, pc.opcode);
    try std.testing.expectEqual(entry.header.flags.version, pc.version);
    try std.testing.expectEqual(entry.header.info.channel, pc.channel);
    try std.testing.expectEqual(try entry.get_topic_name(), pc.topic);
}

test "PacketCollection.add success -- one entry" {
    var entry = packet.Packet.init(std.testing.allocator);
    const buf: [2]u8 = [_]u8 {
        0b10100001,
        0b10000101,
    };
    entry.peek_header(buf);
    const topic = "test";
    const payload = "hello, world!";
    const body = "testhello, world!";
    entry.header.topic_len = topic.len;
    entry.header.payload_len = payload.len;
    entry.body = try std.testing.allocator.alloc(u8, body.len);
    @memcpy(entry.body.?, body);
    var pc = packet.PacketCollection.init(
        std.testing.allocator,
    );
    defer pc.deinit();

    try pc.add(entry);

    try std.testing.expectEqual(std.testing.allocator, pc.alloc);
    try std.testing.expectEqual(
        std.testing.allocator,
        pc.packets.allocator,
    );
    try std.testing.expectEqual(1, pc.packets.items.len);

    try std.testing.expectEqual(entry.header.flags.opcode, pc.opcode);
    try std.testing.expectEqual(entry.header.flags.version, pc.version);
    try std.testing.expectEqual(entry.header.info.channel, pc.channel);
    try std.testing.expectEqual(try entry.get_topic_name(), pc.topic);
}

test "PacketCollection.add success -- two entries" {
    var entry1 = packet.Packet.init(std.testing.allocator);
    const buf: [2]u8 = [_]u8 {
        0b00100000,
        0b10000101,
    };
    entry1.peek_header(buf);
    const topic = "test";
    const payload = "hello, world!";
    const body = "testhello, world!";
    entry1.header.topic_len = topic.len;
    entry1.header.payload_len = payload.len;
    entry1.body = try std.testing.allocator.alloc(u8, body.len);
    @memcpy(entry1.body.?, body);

    var entry2 = packet.Packet.init(std.testing.allocator);
    const buf2: [2]u8 = [_]u8 {
        0b10100001,
        0b10000101,
    };
    entry2.peek_header(buf2);
    entry2.header.topic_len = topic.len;
    entry2.header.payload_len = payload.len;
    entry2.body = try std.testing.allocator.alloc(u8, body.len);
    @memcpy(entry2.body.?, body);
    var pc = packet.PacketCollection.init(
        std.testing.allocator,
    );
    defer pc.deinit();

    try pc.add(entry1);

    try std.testing.expectEqual(1, pc.packets.items.len);
    try std.testing.expectEqual(proto.OpCode.nc_continue, pc.opcode);
    try std.testing.expectEqual(entry1.header.flags.version, pc.version);
    try std.testing.expectEqual(entry1.header.info.channel, pc.channel);
    try std.testing.expectEqual(try entry1.get_topic_name(), pc.topic);

    try pc.add(entry2);

    try std.testing.expectEqual(2, pc.packets.items.len);

    try std.testing.expectEqual(proto.OpCode.nc_text, pc.opcode);
    try std.testing.expectEqual(entry2.header.flags.opcode, pc.opcode);
    try std.testing.expectEqual(entry1.header.flags.version, pc.version);
    try std.testing.expectEqual(entry1.header.info.channel, pc.channel);
    try std.testing.expectEqual(try entry1.get_topic_name(), pc.topic);
}

test "PacketCollection.payload_size multiple entries" {
    var entry1 = packet.Packet.init(std.testing.allocator);
    const buf: [2]u8 = [_]u8 {
        0b00100000,
        0b10000101,
    };
    entry1.peek_header(buf);
    const topic = "test";
    const payload = "hello, world!";
    const body = "testhello, world!";
    entry1.header.topic_len = topic.len;
    entry1.header.payload_len = payload.len;
    entry1.body = try std.testing.allocator.alloc(u8, body.len);
    @memcpy(entry1.body.?, body);

    var entry2 = packet.Packet.init(std.testing.allocator);
    const buf2: [2]u8 = [_]u8 {
        0b10100001,
        0b10000101,
    };
    entry2.peek_header(buf2);
    entry2.header.topic_len = topic.len;
    entry2.header.payload_len = payload.len;
    entry2.body = try std.testing.allocator.alloc(u8, body.len);
    @memcpy(entry2.body.?, body);
    var pc = packet.PacketCollection.init(
        std.testing.allocator,
    );
    defer pc.deinit();

    try pc.add(entry1);
    try pc.add(entry2);

    try std.testing.expectEqual(2, pc.packets.items.len);
    try std.testing.expectEqual(payload.len * 2, pc.payload_size());
}

test "PacketCollection.payload_size one entry" {
    var entry1 = packet.Packet.init(std.testing.allocator);
    const buf: [2]u8 = [_]u8 {
        0b00100000,
        0b10000101,
    };
    entry1.peek_header(buf);
    const topic = "test";
    const payload = "hello, world!";
    const body = "testhello, world!";
    entry1.header.topic_len = topic.len;
    entry1.header.payload_len = payload.len;
    entry1.body = try std.testing.allocator.alloc(u8, body.len);
    @memcpy(entry1.body.?, body);

    var pc = packet.PacketCollection.init(
        std.testing.allocator,
    );
    defer pc.deinit();

    try pc.add(entry1);

    try std.testing.expectEqual(1, pc.packets.items.len);
    try std.testing.expectEqual(payload.len, pc.payload_size());
}

test "PacketCollection.payload_size empty" {
    var pc = packet.PacketCollection.init(
        std.testing.allocator,
    );
    defer pc.deinit();
    try std.testing.expectEqual(0, pc.packets.items.len);
    try std.testing.expectEqual(0, pc.payload_size());
}
