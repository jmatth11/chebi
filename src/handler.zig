const std = @import("std");
const packet = @import("packet.zig");
const writer = @import("write.zig");
const manager = @import("manager.zig");

const TryAgainInfo = struct {
    attempts: usize = 0,
    from: std.c.fd_t,
    collection: packet.PacketCollection,
    to: std.c.fd_t,

    pub fn deinit(self: *TryAgainInfo) void {
        self.collection.deinit();
    }
};

const HandlerInfoList = std.array_list.Managed(PacketHandlerInfo);
const TryAgainList = std.array_list.Managed(TryAgainInfo);
pub const RecipientList = std.array_list.Managed(std.c.fd_t);

/// Errors with the packet handler.
pub const Error = error{
    /// This is issued if a would_block occurs.
    try_again,
    errno,
    process_failed,
};

pub const PacketHandlerInfo = struct {
    from: std.c.fd_t,
    collection: packet.PacketCollection,
    recipients: RecipientList,

    pub fn deinit(self: *PacketHandlerInfo) void {
        self.collection.deinit();
        self.recipients.deinit();
    }
};

const MAX_ATTEMPTS: comptime_int = 5;

pub const PacketHandler = struct {
    alloc: std.mem.Allocator,
    collection: HandlerInfoList,
    try_again_list: TryAgainList,
    pool: *std.Thread.Pool,
    try_again_mutex: std.Thread.Mutex = .{},
    pool_error: bool = false,

    pub fn init(alloc: std.mem.Allocator) !PacketHandler {
        var result: PacketHandler = .{
            .alloc = alloc,
            .collection = HandlerInfoList.init(alloc),
            .try_again_list = TryAgainList.init(alloc),
            .pool = try alloc.create(std.Thread.Pool),
        };
        try result.pool.init(.{
            .allocator = alloc,
        });
        return result;
    }

    /// Push the structure onto the processing queue.
    pub fn push(self: *PacketHandler, entry: PacketHandlerInfo) !void {
        try self.collection.append(entry);
    }

    /// Process the message, related to the given ID, that failed in it's initial send.
    /// This function increments the retry counter on the message. Once
    /// the message reaches MAX_ATTEMPTS on the retry counter, it is dropped.
    pub fn process_eagain(self: *PacketHandler, id: std.c.fd_t) !void {
        self.try_again_mutex.lock();
        defer self.try_again_mutex.unlock();
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
                    item.*.deinit();
                    _ = self.try_again_list.swapRemove(idx);
                }
                return;
            }
        }
    }

    /// Process all pending messages that are ready to send.
    pub fn process(self: *PacketHandler) !void {
        var wg: std.Thread.WaitGroup = .{};
        for (self.collection.items) |*info| {
            self.pool.spawnWg(&wg, PacketHandler.process_threaded, .{ self, info });
        }
        if (!wg.isDone()) {
            self.pool.waitAndWork(&wg);
        }
        if (self.pool_error) {
            return Error.process_failed;
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
        self.pool.deinit();
        self.alloc.destroy(self.pool);
    }

    fn process_threaded(self: *PacketHandler, info: *PacketHandlerInfo) void {
        for (info.recipients.items) |id| {
            self.process_single(info.from, &info.collection, id) catch |err| {
                if (err == Error.try_again) {
                    if (info.collection.dupe()) |col_dupe| {
                        const entry: TryAgainInfo = .{
                            .to = id,
                            .from = info.from,
                            .collection = col_dupe,
                        };
                        self.append_try_again(entry) catch |append_err| {
                            std.log.err("Process handler appending to try again failed: {any}\n", .{append_err});
                            self.pool_error = true;
                        };
                    } else |dupe_err| {
                        std.log.err("collection dupe failed: {any}\n", .{dupe_err});
                        self.pool_error = true;
                    }
                } else {
                    std.log.err("process_threaded failed: {any}\n", .{err});
                    self.pool_error = true;
                }
            };
        }
        // free collection once done
        info.*.deinit();
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

    fn append_try_again(self: *PacketHandler, entry: TryAgainInfo) !void {
        self.try_again_mutex.lock();
        defer self.try_again_mutex.unlock();
        try self.try_again_list.append(entry);
    }
};
