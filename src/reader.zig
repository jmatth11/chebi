const std = @import("std");
const packet = @import("packet.zig");

/// Reading related errors.
pub const Error = error {
    /// Header is invalid
    header_invalid,
    /// Error occurred when parsing the header.
    header_parsing_error,
    /// The payload length is invalid.
    payload_len_invalid,
};

/// Read the next packet from the given socket.
pub fn read_packet(alloc: std.mem.Allocator, socket: std.c.fd_t) !packet.Packet {
    // create a packet.
    var result: packet.Packet = packet.Packet.init(alloc);
    // peek header info
    var header_info: [2]u8 = [_]u8{0,0};
    var recv_len: usize = std.c.recv(socket, &header_info, 2, std.c.MSG.PEEK);
    if (recv_len < 2) {
        return Error.invalid_header;
    }
    result.peek_header(header_info);
    // get true size of header to read.
    const header_size: usize = result.header.header_size();
    // read in full header
    var header: []u8 = try alloc.alloc(u8, header_size);
    recv_len = std.c.recv(socket, header.ptr, header_size, 0);
    if (recv_len < header_size) {
        return Error.header_invalid;
    }
    // parse the rest of the header.
    recv_len = result.header.parse_body_info(header[2..]) + 2;
    if (recv_len < header_size) {
        return Error.header_parsing_error;
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
