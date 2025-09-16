const std = @import("std");
const packet = @import("packet.zig");
const proto = @import("protocol.zig");

/// Reading related errors.
pub const Error = error {
    /// Empty message was received (likely connection closing)
    empty_message,
    /// Header is invalid
    header_invalid,
    /// The payload length is invalid.
    payload_len_invalid,
    /// Recv would have blocked
    would_block,
    /// Errno error (read errno)
    errno,
};

/// Grab the next packet from the given socket
pub fn next_packet(alloc: std.mem.Allocator, socket: std.c.fd_t) !packet.Packet {
    // create a packet.
    var result: packet.Packet = packet.Packet.init(alloc);
    // peek header info
    var header: [6]u8 = @splat(0);
    var recv_len: isize = std.c.recv(socket, &header, 6, 0);
    if (recv_len == -1) {
        const errno = std.posix.errno(-1);
        if (errno == std.c.E.AGAIN) {
            return Error.would_block;
        }
        return Error.errno;
    }
    if (recv_len == 0) {
        return Error.empty_message;
    }
    if (recv_len < 6) {
        return Error.header_invalid;
    }
    const parse_len = try result.parse_header(&header);
    if (parse_len < 6) {
        return Error.header_invalid;
    }
    if (result.header.topic_len == 0 and result.header.payload_len == 0) {
        return result;
    }
    try result.alloc_buffer();
    recv_len = std.c.recv(socket, result.body.?.ptr, result.body.?.len, 0);
    if (recv_len == -1) {
        const errno = std.posix.errno(-1);
        if (errno == std.c.E.AGAIN) {
            return Error.would_block;
        }
        return Error.errno;
    }
    // TODO need to reconstruct partially sent messages.
    if (recv_len < result.body.?.len) {
        std.debug.print("recv_len = {}; body.len = {}\n", .{recv_len, result.body.?.len});
        return Error.payload_len_invalid;
    }
    return result;
}
