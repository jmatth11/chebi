const std = @import("std");
const packet = @import("packet.zig");
const writer = @import("write.zig");
const manager = @import("manager.zig");

/// Errors with the packet handler.
pub const Error = error{
    /// This is issued if a would_block occurs.
    try_again,
    errno,
};

pub const PacketHandlerInfo = struct {
    from: std.c.fd_t,
    collection: packet.PacketCollection,
};

pub const PacketHandler = struct {
    alloc: std.mem.Allocator,
    collection: std.ArrayList(PacketHandlerInfo),
    //mutex: std.Thread.Mutex,
    //pool: std.Thread.Pool,

    pub fn init(alloc: std.mem.Allocator) !PacketHandler {
        //const options: std.Thread.Pool.Options = .{
        //    .allocator = alloc,
        //};
        //var pool: std.Thread.Pool = .{
        //    .allocator = undefined,
        //    .threads = undefined,
        //    .ids = undefined,
        //};
        //try std.Thread.Pool.init(&pool, options);
        return .{
            .alloc = alloc,
            .collection = std.ArrayList(PacketHandlerInfo).init(alloc),
            //.pool = pool,
            //.mutex = .{},
        };
    }

    pub fn push(self: *PacketHandler, entry: PacketHandlerInfo) !void {
        // TODO this approach was when it's parallelized
        // we also insert at the beginning to treat it like a Queue.
        // But this approach might change
        //self.mutex.lock();
        //defer self.mutex.unlock();
        //try self.collection.insert(0, entry);
        try self.collection.append(entry);
    }

    pub fn process(self: *PacketHandler, mapping: manager.TopicMapping) !void {
        // TODO this is MVP approach, revisit to parallelize
        for (self.collection.items) |*info| {
            const collection = info.collection;
            const from = info.from;
            const topic = collection.topic;
            const clients_opt: ?std.ArrayList(std.c.fd_t) = mapping.get(topic);
            if (clients_opt) |clients| {
                for (collection.packets.items) |payload| {
                    for (clients.items) |socket| {
                        // skip ourselves
                        if (from == socket) {
                            continue;
                        }
                        try self.send(socket, payload);
                    }
                }
            }
            // free collection once done
            info.*.collection.deinit();
        }
        // reset collection after processing
        try self.collection.resize(0);
    }

    /// Send the packet to the given socket.
    pub fn send(self: *PacketHandler, socket: std.c.fd_t, payload: packet.Packet) !void {
        writer.write_packet(self.alloc, socket, payload) catch |err| {
            if (err == writer.Error.would_block) {
                return Error.try_again;
            } else if (err == writer.Error.errno) {
                return Error.errno;
            }
            return err;
        };
    }

    pub fn deinit(self: *PacketHandler) void {
        if (self.collection.items.len > 0) {
            for (self.collection.items) |*item| {
                item.*.collection.deinit();
            }
        }
        self.collection.deinit();
    }
};
