const std = @import("std");
const packet = @import("packet.zig");

/// Errors for writing to socket.
pub const Error = error {
    would_block,
    errno,
};

/// Grab the next packet from the given socket
pub fn write_packet(alloc: std.mem.Allocator, socket: std.c.fd_t, payload: packet.Packet) !void {
    const out: []u8 = try alloc.alloc(u8, payload.get_packet_size());
    try payload.write(out);
    const recv_len: isize = std.c.send(socket, out.ptr, out.len, 0);
    if (recv_len == -1) {
        const errno = std.posix.errno(-1);
        if (errno == std.c.E.AGAIN) {
            return Error.would_block;
        }
        return Error.errno;
    }
}
