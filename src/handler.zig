const std = @import("std");
const packet = @import("packet.zig");
const writer = @import("write.zig");
const manager = @import("manager.zig");

const TryAgainInfo = struct {
    attempts: usize = 0,
    from: std.c.fd_t,
    collection: packet.PacketCollection,
    to: std.c.fd_t,
};

const HandlerInfoList = std.array_list.Managed(PacketHandlerInfo);
const TryAgainList = std.array_list.Managed(TryAgainInfo);
pub const RecipientList = std.array_list.Managed(std.c.fd_t);

/// Errors with the packet handler.
pub const Error = error{
    /// This is issued if a would_block occurs.
    try_again,
    errno,
};

pub const PacketHandlerInfo = struct {
    from: std.c.fd_t,
    collection: packet.PacketCollection,
    recipients: RecipientList,
};

const MAX_ATTEMPTS: comptime_int = 5;

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

    fn process_single(self: *PacketHandler, from: std.c.fd_t, collection: *const packet.PacketCollection, to: std.c.fd_t) !void {
        for (collection.packets.items) |payload| {
            // skip ourselves
            if (from == to) {
                return;
            }
            try self.send(to, payload);
        }
    }

    pub fn process_eagain(self: *PacketHandler, id: std.c.fd_t) !void {
        for (self.try_again_list.items, 0..) |*item, idx| {
            if (item.to == id) {
                item.*.attempts += 1;
                var remove: bool = true;
                self.process_single(item.from, &item.collection, item.to) catch |err| {
                    if (err == Error.try_again) {
                        remove = false;
                    } else {
                        return err;
                    }
                };
                // remove if processed or if it's the N attempt
                if (remove or item.attempts == MAX_ATTEMPTS) {
                    if (item.attempts == MAX_ATTEMPTS) {
                        std.log.err("dropping message from {}\n", .{item.from});
                    }
                    item.*.collection.deinit();
                    _ = self.try_again_list.swapRemove(idx);
                }
                return;
            }
        }
    }

    pub fn process(self: *PacketHandler) !void {
        for (self.collection.items) |*info| {
            for (info.recipients.items) |id| {
                self.process_single(info.from, &info.collection, id) catch |err| {
                    if (err == Error.try_again) {
                        const entry: TryAgainInfo = .{
                            .to = id,
                            .from = info.from,
                            .collection = try info.collection.dupe(),
                        };
                        try self.try_again_list.append(entry);
                    } else {
                        return err;
                    }
                };
            }
            // free collection once done
            info.*.collection.deinit();
            info.recipients.deinit();
        }
        // reset collection.
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
                item.*.collection.deinit();
            }
        }
        self.collection.deinit();
    }
};
