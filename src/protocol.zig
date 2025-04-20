const std = @import("std");

/// Top Level Flags of the protocol.
pub const Flags = packed struct(u8) {
    // The operation code of the protocol message.
    opcode: u4 = 0,
    // The version of the protocol being used.
    version: u3 = 0,
    // The "final" flag. Signaling this is the final message.
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
    id_size: u4 = 0,
    reserved: u4 = 0,

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
    /// The payload data.
    payload: []u8,

    pub fn parse_flags(self: *Protocol, b: u8) void {
        self.flags.unpack(b);
    }
    pub fn parse_info(self: *Protocol, b: u8) void {
        self.info.unpack(b);
    }
    pub fn parse_user_info(self: *Protocol, buf: []u8) !usize {
        var offset: usize = 0;
        // TODO check for buf size to be at least 1
        self.user_info.unpack(buf[0]);
        offset += 1;
        const id_length: usize = offset + self.user_info.id_size;
        // TODO check for size to be what we expect
        self.id = std.mem.readInt(u64, buf[offset..id_length], .little);
        offset = id_length;
        return offset;
    }
    pub fn parse_body_info(self: *Protocol, buf: []u8) !usize {
        var offset: usize = 0;
        if (self.info.mask) {
            self.mask = buf[0..4];
            offset += 4;
        }
        self.payload_len = std.mem.readInt(u16, buf[offset..(offset+2)], .little);
        offset += 2;
        // TODO need allocator here for payload
        // self.payload =
    }
};

