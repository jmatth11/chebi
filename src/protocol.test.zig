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
    try std.testing.expectEqual(true, val.mask);
    try std.testing.expectEqual(5, val.channel);
}

test "Info.pack get byte" {
    const expected: u8 = 0b10000101;
    var val: proto.Info = proto.Info{
        .mask = true,
        .channel = 5,
    };
    const new_b: u8 = val.pack();
    try std.testing.expectEqual(expected, new_b);
}

test "UserInfo.unpack with byte" {
    const input: u8 = 0b00000010;
    var val: proto.UserInfo = .{};
    val.unpack(input);
    try std.testing.expectEqual(proto.UserIDSize.bit32, val.id_size);
    try std.testing.expectEqual(0, val.reserved);
}

test "UserInfo.pack get byte" {
    const input: u8 = 0b00000010;
    var val: proto.UserInfo = .{
        .id_size = .bit32,
        .reserved = 0,
    };
    const result: u8 = val.pack();
    try std.testing.expectEqual(input, result);
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
    try std.testing.expectEqual(true, p.info.mask);
    try std.testing.expectEqual(5, p.info.channel);
}

test "Protocol.parse_user_info happy path" {
    const input: [5]u8 = [_]u8 {
        0b00000010,
        // 147458
        0b00000010,
        0b01000000,
        0b00000010,
        0b00000000,
    };
    var p: proto.Protocol = .{};

    const result = try p.parse_user_info(&input);

    try std.testing.expectEqual(5, result);
    try std.testing.expectEqual(proto.UserIDSize.bit32, p.user_info.id_size);
    try std.testing.expectEqual(0, p.user_info.reserved);
    try std.testing.expectEqual(147458, p.id);
}

test "Protocol.parse_user_info empty buffer" {
    const input: [0]u8 = [_]u8{};
    var p: proto.Protocol = .{};

    try std.testing.expectError(
        proto.Errors.invalid_user_info,
        p.parse_user_info(&input)
    );
}

test "Protocol.parse_user_info missing ID" {
    const input: [1]u8 = [_]u8 {
        0b00000010,
    };
    var p: proto.Protocol = .{};

    try std.testing.expectError(
        proto.Errors.invalid_user_id,
        p.parse_user_info(&input)
    );
}

test "Protocol.parse_body_info happy path" {
    const input: [6]u8 = [_]u8 {
        0b00000001,
        0b00000010,
        0b00000100,
        0b00001000,
        0b00000001,
        0b00000010,
    };
    const expected_mask: [4]u8 = [_]u8 {
        0b00000001,
        0b00000010,
        0b00000100,
        0b00001000,
    };
    var p: proto.Protocol = .{
        .info = .{
            .mask = true,
        },
    };
    const result = try p.parse_body_info(&input);

    try std.testing.expectEqual(6, result);
    try std.testing.expectEqualSlices(u8, &expected_mask, &p.mask);
    try std.testing.expectEqual(513, p.payload_len);
}

test "Protocol.parse_body_info no mask" {
    const input: [2]u8 = [_]u8 {
        0b00000001,
        0b00000010,
    };
    const expected_mask: [4]u8 = [_]u8 {0,0,0,0};
    var p: proto.Protocol = .{};
    const result = try p.parse_body_info(&input);

    try std.testing.expectEqual(2, result);
    try std.testing.expectEqualSlices(u8, &expected_mask, &p.mask);
    try std.testing.expectEqual(513, p.payload_len);
}

test "Protocol.parse_body_info missing mask" {
    const input: [2]u8 = [_]u8 {
        0b00000001,
        0b00000010,
    };
    var p: proto.Protocol = .{
        .info = .{
            .mask = true,
        },
    };
    try std.testing.expectError(proto.Errors.invalid_mask, p.parse_body_info(&input));
}

test "Protocol.parse_body_info invalid payload length" {
    const input: [0]u8 = [_]u8 {};
    var p: proto.Protocol = .{};
    try std.testing.expectError(proto.Errors.invalid_payload_len, p.parse_body_info(&input));
}
