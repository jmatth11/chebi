const std = @import("std");
const proto = @import("protocol.zig");

test "Flags.unpack with byte" {
    const input: u8 = 0b10100001;
    var f: proto.Flags = proto.Flags{};
    f.unpack(input);
    try std.testing.expectEqual(true, f.fin);
    try std.testing.expectEqual(2, f.version);
    try std.testing.expectEqual(1, f.opcode);
}

test "Flags.pack get byte" {
    const expected: u8 = 0b10100001;
    var f: proto.Flags = proto.Flags{
        .fin = true,
        .version = 2,
        .opcode = 1,
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
    try std.testing.expectEqual(1, p.flags.opcode);
}

test "Protocol.parse_info sanity check" {
    const input: u8 = 0b10000101;
    var p: proto.Protocol = .{};
    p.parse_info(input);
    try std.testing.expectEqual(true, p.info.mask);
    try std.testing.expectEqual(5, p.info.channel);
}

test "Protocol.parse_user_info sanity check" {
    //const input: u8 = 0b00000010;
    //var p: proto.Protocol = .{};
    //p.parse_user_info(input);
    //try std.testing.expectEqual(proto.UserIDSize.bit32, p.user_info.id_size);
    //try std.testing.expectEqual(0, p.user_info.reserved);
}


