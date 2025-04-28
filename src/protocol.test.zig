const std = @import("std");
const proto = @import("protocol.zig");

test "Flags.unpack with byte" {
    const input: u8 = 0b10100001;
    var f: proto.Flags = proto.Flags{};
    f.unpack(input);
    try std.testing.expectEqual(true, f.fin);
    try std.testing.expectEqual(2, f.version);
    try std.testing.expectEqual(proto.OpCode.nc_text, f.opcode);
}

test "Flags.pack get byte" {
    const expected: u8 = 0b10100001;
    var f: proto.Flags = proto.Flags{
        .fin = true,
        .version = 2,
        .opcode = .nc_text,
    };
    const new_b: u8 = f.pack();
    try std.testing.expectEqual(expected, new_b);
}

test "Info.unpack with byte" {
    const input: u8 = 0b10000101;
    var val: proto.Info = proto.Info{};
    val.unpack(input);
    try std.testing.expectEqual(true, val.compressed);
    try std.testing.expectEqual(5, val.channel);
}

test "Info.pack get byte" {
    const expected: u8 = 0b10000101;
    var val: proto.Info = proto.Info{
        .compressed = true,
        .channel = 5,
    };
    const new_b: u8 = val.pack();
    try std.testing.expectEqual(expected, new_b);
}

test "Protocol.parse_flags sanity check" {
    const input: u8 = 0b10100001;
    var p: proto.Protocol = .{};
    p.parse_flags(input);
    try std.testing.expectEqual(true, p.flags.fin);
    try std.testing.expectEqual(2, p.flags.version);
    try std.testing.expectEqual(proto.OpCode.nc_text, p.flags.opcode);
}

test "Protocol.parse_info sanity check" {
    const input: u8 = 0b10000101;
    var p: proto.Protocol = .{};
    p.parse_info(input);
    try std.testing.expectEqual(true, p.info.compressed);
    try std.testing.expectEqual(5, p.info.channel);
}

test "Protocol.parse_body_info happy path" {
    const input: [4]u8 = [_]u8 {
        // topic len
        0b10000000,
        0b00000000,
        // payload len
        0b00000001,
        0b00000010,
    };
    var p: proto.Protocol = .{};
    const result = try p.parse_body_info(&input);

    try std.testing.expectEqual(4, result);
    try std.testing.expectEqual(128, p.topic_len);
    try std.testing.expectEqual(513, p.payload_len);
}

test "Protocol.parse_body_info invalid payload length" {
    const input: [2]u8 = [_]u8 {
        // topic len
        0b10000000,
        0b00000000,
    };
    var p: proto.Protocol = .{};
    try std.testing.expectError(proto.Errors.invalid_payload_len, p.parse_body_info(&input));
}

test "Protocol.parse_body_info invalid topic length and missing payload length" {
    const input: [0]u8 = [_]u8 {};
    var p: proto.Protocol = .{};
    try std.testing.expectError(proto.Errors.invalid_topic_len, p.parse_body_info(&input));
}
