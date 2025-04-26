const std = @import("std");

/// Errors related to Protocols
pub const Errors = error {
    invalid_mask,
    invalid_topic_len,
    invalid_payload_len,

    not_supported_type,
};

/// OpCodes for the Protocol.
/// Non-Control codes are for messages between clients.
/// Control codes are for messages to/from the server.
pub const OpCode = enum(u4) {
    // non-control codes

    nc_continue = 0,
    nc_text,
    nc_bin,
    nc_res1,
    nc_res2,
    nc_res3,
    nc_res4,
    nc_res5,

    // control codes

    c_connection = 8,
    c_close,
    c_ping,
    c_pong,
    c_subscribe,
    c_unsubscribe,
    c_res3,
    c_res4,
};

/// Top Level Flags of the protocol.
pub const Flags = packed struct(u8) {
    /// The operation code of the protocol message.
    opcode: OpCode = .nc_continue,
    /// The version of the protocol being used.
    version: u3 = 0,
    /// The "final" flag. Signaling this is the final message.
    fin: bool = false,

    /// Unpack the given byte into this structures properties.
    pub fn unpack(self: *Flags, b: u8) void {
        self.* = @bitCast(b);
    }

    /// Pack this structure into a byte form.
    pub fn pack(self: Flags) u8 {
        return @bitCast(self);
    }
};

/// Info about the specific protocol message.
pub const Info = packed struct(u8) {
    /// The message channel ID.
    channel: u7 = 0,
    /// The mask flag.
    /// If this is true a mask field is populated to unmask the message.
    mask: bool = false,

    /// Unpack the given byte into this structures properties.
    pub fn unpack(self: *Info, b: u8) void {
        self.* = @bitCast(b);
    }

    /// Pack this structure into a byte form.
    pub fn pack(self: Info) u8 {
        return @bitCast(self);
    }
};

/// The Protocol for messages within this system.
pub const Protocol = struct {
    /// Top-Level flags.
    flags: Flags = Flags{},
    /// Info about the message.
    info: Info = Info{},
    /// Mask used for un/masking message, if mask flag is true.
    mask: [4]u8 = [_]u8{0,0,0,0},
    /// The Topic String Length
    topic_len: u16 = 0,
    /// The payload length.
    payload_len: u16 = 0,

    /// Get the header size in bytes.
    pub fn header_size(self: *Protocol) usize {
        if (self.info.mask) {
            return 10;
        }
        return 6;
    }

    /// Parse the flags from the given byte.
    pub fn parse_flags(self: *Protocol, b: u8) void {
        self.flags.unpack(b);
    }

    /// Parse the Message info from the given byte.
    pub fn parse_info(self: *Protocol, b: u8) void {
        self.info.unpack(b);
    }

    /// Parse the body info from the given buffer.
    pub fn parse_body_info(self: *Protocol, buf: []const u8) Errors!usize {
        var offset: usize = 0;
        if (self.info.mask) {
            if (buf.len < 4) {
                return Errors.invalid_mask;
            }
            self.mask = buf[0..4].*;
            offset += 4;
        }
        if (buf.len < (offset + 2)) {
            return Errors.invalid_topic_len;
        }
        self.topic_len = std.mem.readVarInt(
            u16,
            buf[offset..(offset+2)],
            .little,
        );
        offset += 2;
        if (buf.len < (offset + 2)) {
            return Errors.invalid_payload_len;
        }
        self.payload_len = std.mem.readVarInt(
            u16,
            buf[offset..(offset+2)],
            .little,
        );
        offset += 2;
        return offset;
    }
};

