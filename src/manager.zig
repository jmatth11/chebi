const std = @import("std");

/// Errors specific to the manager.
pub const Error = error {
    /// Topic does not exist
    topic_dne,
};

pub const ClientInfo = struct {
    fd: std.c.fd_t,
    last_active: std.time.Instant,
};

/// Manager to handle topics and clients.
pub const Manager = struct {
    alloc: std.mem.Allocator,
    topics: std.StringHashMap(std.ArrayList(std.c.fd_t)),
    clients: std.AutoHashMap(std.c.fd_t, std.ArrayList([]const u8)),

    /// Initialize the manager with an allocator.
    pub fn init(alloc: std.mem.Allocator) Manager {
        const m: Manager = .{
            .alloc = alloc,
            .topics = std.StringHashMap(std.ArrayList(std.c.fd_t)).init(alloc),
            // TODO replace Value with ClientInfo
            .clients = std.AutoHashMap(std.c.fd_t, std.ArrayList([]const u8)).init(alloc),
        };
        return m;
    }

    /// Add a topic.
    /// This function duplicates the incoming topic name.
    pub fn add_topic(self: *Manager, topic: []const u8) !void {
        if (self.topics.contains(topic)) {
            return;
        }
        const dup_key: []const u8 = try self.alloc.dupe(u8, topic);
        try self.topics.put(dup_key, std.ArrayList(std.c.fd_t).init(self.alloc));
    }

    /// Add a client.
    pub fn add_client(self: *Manager, client: std.c.fd_t) !void {
        if (self.clients.contains(client)) {
            return;
        }
        try self.clients.put(client, std.ArrayList([]const u8).init(self.alloc));
    }

    /// Subscribe a client to a specified topic.
    /// If the topic or client have not been added yet, they are added here.
    pub fn subscribe(self: *Manager, client: std.c.fd_t, topic: []const u8) !void {
        if (!self.topics.contains(topic)) {
            try self.add_topic(topic);
        }
        if (!self.clients.contains(client)) {
            try self.add_client(client);
        }
        // iterate through the client's list because I assume it will be smaller
        // than a topic's list. (unless we decide to sort the topic's list then
        // we can do binary search)
        var client_topics = self.clients.getPtr(client).?;
        var already_subbed: bool = false;
        for (client_topics.items) |item| {
            if (std.mem.eql(u8, item, topic)) {
                already_subbed = true;
            }
        }
        if (already_subbed) {
            return;
        }
        const topic_name: []const u8 = self.topics.getKey(topic).?;
        try client_topics.append(topic_name);
        var topic_mapping: std.ArrayList(std.c.fd_t) = try self.topics.getPtr(topic).?;
        try topic_mapping.append(client);
    }

    /// Unsubscribe a client from a specific topic.
    pub fn unsubscribe(self: *Manager, client: std.c.fd_t, topic: []const u8) void {
        // TODO iterating through seems slow, maybe we can sort beforehand
        // to do binary search? or maybe something else
        const client_topics = self.clients.getPtr(client);
        if (client_topics) |ct| {
            var idx: usize = 0;
            var found: bool = false;
            for (ct.items, 0..) |item, i| {
                if (std.mem.eql(u8, item, topic)) {
                    found = true;
                    idx = i;
                    break;
                }
            }
            if (found) {
                ct.swapRemove(idx);
            }
        }
        const topic_mapping = self.topics.getPtr(topic);
        if (topic_mapping) |tm| {
            var idx: usize = 0;
            var found: bool = false;
            for (tm.items, 0..) |item, i| {
                if (item == client) {
                    found = true;
                    idx = i;
                    break;
                }
            }
            if (found) {
                tm.swapRemove(idx);
            }
        }
    }

    /// Unsubscribe the client from all topics.
    /// This function also removes the client from the managed list.
    pub fn unsubscribe_all(self: *Manager, client: std.c.fd_t) void {
        const client_topics = self.clients.getPtr(client);
        if (client_topics) |ct| {
            for (ct.items) |item| {
                var topic_mapping = self.topics.getPtr(item).?;
                var idx: usize = 0;
                var found: bool = false;
                for (topic_mapping.items, 0..) |tm_item, i| {
                    if (tm_item == client) {
                        found = true;
                        idx = i;
                        break;
                    }
                }
                if (found) {
                    topic_mapping.swapRemove(idx);
                }
            }
            ct.deinit();
        }
        _ = self.clients.remove(client);
    }

    /// Grab the list of clients for a specific topic.
    pub fn client_list(self: *Manager, topic: []const u8) Error![]const std.c.fd_t {
        const topic_mapping = self.topics.get(topic);
        if (topic_mapping) |tm| {
            return tm.items;
        }
        return Error.topic_dne;
    }

    /// Deinitalize internals of the Manager.
    pub fn deinit(self: *Manager) void {
        const client_it = self.clients.valueIterator();
        while (client_it.next()) |value| {
            value.deinit();
        }
        self.clients.deinit();
        const topic_val_it = self.topics.valueIterator();
        while (topic_val_it.next()) |val| {
            val.deinit();
        }
        const topic_key_it = self.topics.keyIterator();
        while (topic_key_it.next()) |key| {
            self.alloc.free(key.*);
        }
        self.topics.deinit();
    }
};
