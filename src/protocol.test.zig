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

