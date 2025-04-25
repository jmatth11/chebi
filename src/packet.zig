const std = @import("std");
const proto = @import("protocol.zig");

pub const Packet = struct {
    alloc: std.mem.Allocator,
    header: proto.Protocol = .{},
    payload: ?[]u8 = null,

    pub fn init(alloc: std.mem.Allocator) Packet {
        var p: Packet = .{};
        p.alloc = alloc;
        return p;
    }

    pub fn deinit(self: *Packet) void {
        if (self.payload) |payload| {
            self.alloc.free(payload);
        }
    }
};

pub const PacketCollection = struct {
    alloc: std.mem.Allocator,
    opcode: proto.OpCode = proto.OpCode.nc_continue,
    version: u8 = 0,
    channel: u8 = 0,
    id: u64 = 0,
    packets: std.ArrayList(Packet) = undefined,

    pub fn init(alloc: std.mem.Allocator) PacketCollection {
        var pc: PacketCollection = .{};
        pc.alloc = alloc;
        pc.packets = std.ArrayList(Packet).init(alloc);
        return pc;
    }

    pub fn add(self: *PacketCollection, entry: Packet) !void {
        // if it's the first entry record meta info
        if (self.packets.items.len == 0) {
            self.version = entry.header.flags.version;
            self.channel = entry.header.info.channel;
            self.id = entry.header.id;
        }
        // if it's the final message grab the opcode info.
        if (entry.header.flags.fin) {
            self.opcode = entry.header.flags.opcode;
        }
        try self.packets.append(entry);
    }

    pub fn deinit(self: *PacketCollection) void {
        self.packets.deinit();
    }
};
