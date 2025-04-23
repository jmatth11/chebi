const std = @import("std");

/// Errors related to Protocols
pub const Errors = error {
    invalid_user_info,
    invalid_user_id,
    invalid_mask,
    invalid_payload_len,

    not_supported_type,
};

/// User ID Size enumeration.
/// Used to inform which integer size the ID is.
pub const UserIDSize = enum(u2) {
    bit8 = 0,
    bit16 = 1,
    bit32 = 2,
    bit64 = 3,

    /// Get the byte count of the enumeration.
    pub fn byte_count(self: UserIDSize) usize {
        return switch (self) {
            .bit8 => 1,
            .bit16 => 2,
            .bit32 => 4,
            .bit64 => 8,
        };
    }

    /// Get the User ID Size enumeration from the given integer type.
    pub fn from_type(comptime T: type) Errors!UserIDSize {
        switch (T) {
            u64 => .bit64,
            i64 => .bit64,
            u32 => .bit32,
            i32 => .bit32,
            u16 => .bit16,
            i16 => .bit16,
            u8 => .bit8,
            i8 => .bit8,
            else => .not_supported_type,
        }
    }
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
    c_res1,
    c_res2,
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

pub const UserInfo = packed struct(u8) {
    /// Id Size.
    /// 0 -> 1 byte
    /// 1 -> 2 bytes
    /// 2 -> 4 bytes
    /// 3 -> 8 bytes
    id_size: UserIDSize = .bit8,
    /// Reserved bits
    reserved: u6 = 0,

    /// Unpack the given byte into this structures properties.
    pub fn unpack(self: *UserInfo, b: u8) void {
        self.* = @bitCast(b);
    }

    /// Pack this structure into a byte form.
    pub fn pack(self: UserInfo) u8 {
        return @bitCast(self);
    }
};

/// The Protocol for messages within this system.
pub const Protocol = struct {
    /// Top-Level flags.
    flags: Flags = Flags{},
    /// Info about the message.
    info: Info = Info{},
    /// User Info (i.e. ID length)
    user_info: UserInfo = UserInfo{},
    /// The ID of the client.
    id: u64 = 0,
    /// Mask used for un/masking message, if mask flag is true.
    mask: [4]u8 = [_]u8{0,0,0,0},
    /// The payload length.
    payload_len: u16 = 0,

    /// Parse the flags from the given byte.
    pub fn parse_flags(self: *Protocol, b: u8) void {
        self.flags.unpack(b);
    }

    /// Parse the Message info from the given byte.
    pub fn parse_info(self: *Protocol, b: u8) void {
        self.info.unpack(b);
    }

    /// Parse the user info from the given buffer.
    pub fn parse_user_info(self: *Protocol, buf: []const u8) Errors!usize {
        var offset: usize = 0;
        if (buf.len == 0) {
            return Errors.invalid_user_info;
        }
        self.user_info.unpack(buf[0]);
        offset += 1;
        const id_length: usize = offset + self.user_info.id_size.byte_count();
        if (buf.len  < id_length) {
            return Errors.invalid_user_id;
        }
        self.id = std.mem.readVarInt(
            u64,
            buf[offset..id_length],
            .little,
        );
        offset = id_length;
        return offset;
    }

    /// Parse the body info from the given buffer.
    pub fn parse_body_info(self: *Protocol, buf: []const u8) Errors!usize {
        var offset: usize = 0;
        if (self.info.mask) {
            if (buf.len < 4) {
                return Errors.invalid_mask;
            }
            self.mask = buf[0..4];
            offset += 4;
        }
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

