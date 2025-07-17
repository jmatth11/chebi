const std = @import("std");
const packet = @import("packet.zig");

/// Reading related errors.
pub const Error = error {
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
    var recv_len: usize = std.c.recv(socket, &header, 6, 0);
    if (recv_len == -1) {
        const errno = std.posix.errno();
        if (errno == std.c.E.AGAIN or errno == std.c.E.WOULDBLOCK) {
            return Error.would_block;
        }
        return Error.errno;
    }
    if (recv_len < 6) {
        return Error.invalid_header;
    }
    recv_len = try result.parse_header(&header);
    if (recv_len < 6) {
        return Error.invalid_header;
    }
    // calculate the body size and read it in.
    const body_size: usize = result.header.topic_len + result.header.payload_len;
    result.body = try alloc.alloc(u8, body_size);
    recv_len = std.c.recv(socket, result.body.?.ptr, body_size, 0);
    if (recv_len < body_size) {
        return Error.payload_len_invalid;
    }
    return result;
}
