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

const PartialPackets = std.AutoHashMap(std.c.fd_t, packet.Packet);

var partialPacketCollection = PartialPackets.init(std.heap.smp_allocator);

fn process_partial(socket: std.c.fd_t, pack: *packet.Packet) !void {
    var full_size: usize = @intCast(pack.header.topic_len);
    full_size += @intCast(pack.header.payload_len);
    var buf = try pack.alloc.alloc(u8, full_size);
    var diff: usize = full_size;
    var offset: usize = 0;
    if (pack.body) |body| {
        diff = diff - body.len;
        @memmove(buf.ptr, body);
        offset = body.len;
    }

    const recv_len: isize = std.c.recv(socket, buf[offset..full_size].ptr, diff, 0);
    if (recv_len == -1) {
        const errno = std.posix.errno(-1);
        if (errno == std.c.E.AGAIN) {
            return Error.would_block;
        }
        // dealloc packet
        pack.deinit();
        _ = partialPacketCollection.remove(socket);
        return Error.errno;
    }
    if (pack.body) |body| {
        pack.alloc.free(body);
        pack.body = null;
    }
    pack.body = buf;
    if (recv_len < diff) {
        const new_size: usize = @as(usize, @intCast(recv_len)) + diff;
        const new_body = try pack.alloc.realloc(pack.body.?, new_size);
        pack.body = new_body;
        // store partial packets to try and grab the rest later.
        partialPacketCollection.put(socket, pack.*) catch  |err| {
            pack.deinit();
            return err;
        };
        std.log.debug("recv_len = {}; body.len = {}; diff = {}\n", .{recv_len, buf.len, diff});
        return Error.payload_len_invalid;
    }
}

/// Grab the next packet from the given socket
pub fn next_packet(alloc: std.mem.Allocator, socket: std.c.fd_t) !packet.Packet {
    // create a packet.
    var result: packet.Packet = undefined;
    // TODO clean this up into tidy functions
    if (partialPacketCollection.get(socket)) |entry| {
        result = entry;
        try process_partial(socket, &result);
        _ = partialPacketCollection.remove(socket);
        return result;
    } else {
        result = packet.Packet.init(alloc);
    }
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
        // dealloc packet
        result.deinit();
        return Error.errno;
    }
    if (recv_len < result.body.?.len) {
        const old_len = result.body.?.len;
        const new_body = try alloc.realloc(result.body.?, @intCast(recv_len));
        result.body = new_body;
        // store partial packets to try and grab the rest later.
        partialPacketCollection.put(socket, result) catch  |err| {
            result.deinit();
            return err;
        };
        std.log.debug("recv_len = {}; body.len = {}\n", .{recv_len, old_len});
        return Error.payload_len_invalid;
    }
    return result;
}
