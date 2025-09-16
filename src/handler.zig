const std = @import("std");
const packet = @import("packet.zig");
const writer = @import("write.zig");
const manager = @import("manager.zig");

const TryAgainInfo = struct {
    attempts: usize = 0,
    packet: PacketHandlerInfo,
};

const HandlerInfoList = std.array_list.Managed(PacketHandlerInfo);
const TryAgainList = std.array_list.Managed(TryAgainInfo);

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
    collection: HandlerInfoList,
    try_again_list: TryAgainList,
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
            .collection = HandlerInfoList.init(alloc),
            .try_again_list = TryAgainList.init(alloc),
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

    fn process_single(self: *PacketHandler, info: *const PacketHandlerInfo, clients: manager.SocketList) !void {
        const collection = info.collection;
        const from = info.from;
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

    pub fn process(self: *PacketHandler, mapping: manager.TopicMapping) !void {
        var try_again_list_idx: usize = self.try_again_list.items.len;
        while (try_again_list_idx > 0) : (try_again_list_idx -= 1) {
            const index = try_again_list_idx - 1;
            var tmp_item: *TryAgainInfo = &self.try_again_list.items[index];
            tmp_item.attempts += 1;
            const collection = tmp_item.packet.collection;
            const topic = collection.topic;
            const clients_opt: ?manager.SocketList = mapping.get(topic);
            var remove: bool = true;
            if (clients_opt) |clients| {
                self.process_single(&tmp_item.packet, clients) catch |err| {
                    if (err == Error.try_again) {
                        remove = false;
                    } else {
                        return err;
                    }
                };
            }
            // remove if processed or if it's the N attempt
            if (remove or tmp_item.attempts == 5) {
                if (tmp_item.attempts == 3) {
                    std.log.err("dropping message from {}\n", .{tmp_item.packet.from});
                }
                tmp_item.packet.collection.deinit();
                _ = self.try_again_list.swapRemove(index);
            }
        }
        // TODO this is MVP approach, revisit to parallelize
        for (self.collection.items) |*info| {
            const collection = info.collection;
            const topic = collection.topic;
            const clients_opt: ?manager.SocketList = mapping.get(topic);
            var should_deinit: bool = true;
            if (clients_opt) |clients| {
                self.process_single(info, clients) catch |err| {
                    if (err == Error.try_again) {
                        try self.try_again_list.append(.{ .packet = info.* });
                        should_deinit = false;
                    } else {
                        return err;
                    }
                };
            }
            if (should_deinit) {
                // free collection once done
                info.*.collection.deinit();
            }
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
        if (self.try_again_list.items.len > 0) {
            for (self.try_again_list.items) |*item| {
                item.*.packet.collection.deinit();
            }
        }
        self.collection.deinit();
    }
};
