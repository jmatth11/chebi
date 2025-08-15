const std = @import("std");

/// Compression Type for messages.
pub const CompressionType = enum(u8) {
    /// raw -- no compression
    raw,
    /// gzip
    gzip,
    /// zlib
    zlib,
};

pub const Error = error{
    eof,
    compression_read,
    compression_write_alloc,
};

pub const CompressionReader = struct {
    buf: []const u8,
    offset: usize = 0,

    pub const Reader = std.io.GenericReader(*CompressionReader, Error, read);

    pub fn init(buf: []const u8) CompressionReader {
        const result: CompressionReader = .{
            .buf = buf,
        };
        return result;
    }
    pub fn read(context: *CompressionReader, buffer: []u8) Error!usize {
        if (context.offset >= context.buf.len) {
            return Error.eof;
        }
        var ending_offset = buffer.len + context.offset;
        if (ending_offset > (context.buf.len)) {
            ending_offset = context.buf.len;
        }
        @memcpy(
            buffer,
            context.buf[context.offset..ending_offset],
        );
        const n = ending_offset - context.offset;
        context.offset += buffer.len;
        return n;
    }

    pub fn get_reader(self: *CompressionReader) Reader {
        return .{ .context = self };
    }
};

pub const CompressionWriter = struct {
    alloc: std.mem.Allocator,
    buf: std.ArrayList(u8),
    offset: usize = 0,
    pub const Writer = std.io.GenericWriter(*CompressionWriter, Error, write);
    pub fn init(alloc: std.mem.Allocator) CompressionWriter {
        const result: CompressionWriter = .{
            .alloc = alloc,
            .buf = std.ArrayList(u8).init(alloc),
        };
        return result;
    }

    pub fn write(context: *CompressionWriter, buf: []const u8) Error!usize {
        context.buf.appendSlice(buf) catch {
            return Error.compression_write_alloc;
        };
        return buf.len;
    }

    pub fn get_writer(self: *CompressionWriter) Writer {
        return .{ .context = self };
    }

    pub fn deinit(self: *CompressionWriter) void {
        self.buf.deinit();
    }
};

pub fn compress(alloc: std.mem.Allocator, compression_type: CompressionType, buf: []const u8) ![]u8 {
    var local_writer = CompressionWriter.init(alloc);
    defer local_writer.deinit();
    var local_reader = CompressionReader.init(buf);
    const reader = local_reader.get_reader();
    const writer = local_writer.get_writer();
    switch (compression_type) {
        .gzip => {
            try std.compress.gzip.compress(reader, writer, .{});
        },
        .zlib => {
            try std.compress.zlib.compress(reader, writer, .{});
        },
        .raw => {
            return try alloc.dupe(u8, buf);
        },
    }
    return try local_writer.buf.toOwnedSlice();
}

pub fn decompress(alloc: std.mem.Allocator, compression_type: CompressionType, buf: []const u8) ![]u8 {
    var local_writer = CompressionWriter.init(alloc);
    defer local_writer.deinit();
    var local_reader = CompressionReader.init(buf);
    const reader = local_reader.get_reader();
    const writer = local_writer.get_writer();
    switch (compression_type) {
        .gzip => {
            try std.compress.gzip.decompress(reader, writer);
        },
        .zlib => {
            try std.compress.zlib.decompress(reader, writer);
        },
        .raw => {
            return try alloc.dupe(u8, buf);
        },
    }
    return try local_writer.buf.toOwnedSlice();
}
