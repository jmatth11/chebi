const std = @import("std");

pub const Error = error{
    empty_buffer,
};

/// Compression Type for messages.
pub const CompressionType = enum(u8) {
    none,
    /// raw
    raw,
    /// gzip
    gzip,
    /// zlib
    zlib,
};

//pub const Error = error{
//    /// The given read buffer is empty.
//    compression_read_buffer_empty,
//    /// Allocating for the writer failed.
//    compression_write_alloc,
//};
//
///// Simple reader to use with compression functions.
//pub const CompressionReader = struct {
//    buf: []const u8,
//    offset: usize = 0,
//
//    pub const Reader = std.io.GenericReader(*CompressionReader, Error, read);
//
//    pub fn init(buf: []const u8) CompressionReader {
//        const result: CompressionReader = .{
//            .buf = buf,
//        };
//        return result;
//    }
//    pub fn read(context: *CompressionReader, buffer: []u8) Error!usize {
//        if (buffer.len == 0) {
//            return Error.compression_read_buffer_empty;
//        }
//        if (context.offset >= context.buf.len) {
//            return 0;
//        }
//        var ending_offset = buffer.len + context.offset;
//        if (ending_offset > context.buf.len) {
//            ending_offset = context.buf.len;
//        }
//        const local_slice = context.buf[context.offset..ending_offset];
//        @memcpy(
//            buffer[0..local_slice.len],
//            local_slice,
//        );
//        context.offset += buffer.len;
//        return local_slice.len;
//    }
//
//    pub fn get_reader(self: *CompressionReader) Reader {
//        return .{ .context = self };
//    }
//};
//
///// Simple writer to use with compression functions.
//pub const CompressionWriter = struct {
//    alloc: std.mem.Allocator,
//    buf: std.ArrayList(u8),
//    offset: usize = 0,
//    pub const Writer = std.io.GenericWriter(*CompressionWriter, Error, write);
//    pub fn init(alloc: std.mem.Allocator) CompressionWriter {
//        const result: CompressionWriter = .{
//            .alloc = alloc,
//            .buf = std.ArrayList(u8).init(alloc),
//        };
//        return result;
//    }
//
//    pub fn write(context: *CompressionWriter, buf: []const u8) Error!usize {
//        context.buf.appendSlice(buf) catch {
//            return Error.compression_write_alloc;
//        };
//        return buf.len;
//    }
//
//    pub fn get_writer(self: *CompressionWriter) Writer {
//        return .{ .context = self };
//    }
//
//    pub fn deinit(self: *CompressionWriter) void {
//        self.buf.deinit();
//    }
//};

/// Compress a given slice using the compression type.
pub fn compress(alloc: std.mem.Allocator, compression_type: CompressionType, buf: []const u8) ![]u8 {
    _ = alloc;
    _ = compression_type;
    _ = buf;
    @panic("zig compression library doesn't work currently");
    //if (buf.len == 0) {
    //    return Error.empty_buffer;
    //}
    //var out: std.Io.Writer.Allocating = .init(alloc);
    //const dup: []u8 = try alloc.dupe(u8, buf);
    //defer alloc.free(dup);
    //switch (compression_type) {
    //    .gzip, .zlib, .raw => {
    //        const local_type = switch (compression_type) {
    //            .gzip => std.compress.flate.Container.gzip,
    //            .zlib => std.compress.flate.Container.zlib,
    //            .raw => std.compress.flate.Container.raw,
    //        };
    //        var compressor: std.compress.flate.Compress = .init(
    //            &out.writer,
    //            dup,
    //            .{ .container = local_type },
    //        );
    //        compressor.endUnflushed();
    //        try compressor.end();
    //    },
    //}
    //return try out.toOwnedSlice();
}

/// Decompress a given slice using the compression type.
pub fn decompress(alloc: std.mem.Allocator, compression_type: CompressionType, buf: []const u8) ![]u8 {
    _ = alloc;
    _ = compression_type;
    _ = buf;
    @panic("zig compression library doesn't work currently");
    //if (buf.len == 0) {
    //    return Error.empty_buffer;
    //}
    //var in: std.Io.Reader = .fixed(buf);
    //var aw: std.Io.Writer.Allocating = .init(alloc);

    //switch (compression_type) {
    //    .gzip, .zlib, .raw => {
    //        const local_type = switch (compression_type) {
    //            .gzip => std.compress.flate.Container.gzip,
    //            .zlib => std.compress.flate.Container.zlib,
    //            .raw => std.compress.flate.Container.raw,
    //        };
    //        var decompressor = std.compress.flate.Decompress.init(
    //            &in,
    //            local_type,
    //            &.{},
    //        );
    //        _ = try decompressor.reader.streamRemaining(&aw.writer);
    //    },
    //    none =>
    //}
    //return try aw.toOwnedSlice();
}
