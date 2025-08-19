# Chebi

**!! still experimental !!**

A small message bus written in zig to easily spin up on the fly.

The goal of this message bus is to provide support for standard text and binary
formats, with options for compression, and handles multiplexing messages.

## Standard Capabilities

The standard capabilities are supported:
- Subscribing and unsubscribing to topics
- Writing and reading from topics.

## Compression

The spec contains a flag for compression, which you can toggle on and off.

Supports:

- gzip
- zlib

## Multiplexed Messaging

The spec allows for messages to be grouped by top-down of topic, client socket, and message channel.
This allows large messages to not clog up the pipeline if smaller messages can be processed quicker.

## Installation & Setup

### Install

Add to your project like so.
```bash
zig fetch --save "git+https://github.com/jmatth11/chebi#master"
```

### Setup

Place this in your `build.zig`.

```zig
const chebi = b.dependency("chebi", .{
    .target = target,
    .optimize = optimize,
});

// the executable from your call to b.addExecutable(...)
exe.root_module.addImport("chebi", chebi.module("chebi"));
```

## Examples

You can find all examples in the `examples/` folder.

Currently there are examples for:

- simple.
- multiplexed messages.
- compression used.

### Example Server

A simple server application.

```zig
const std = @import("std");
const chebi = @import("chebi");
const server = chebi.server;

var s: server.Server = undefined;

export fn shutdown(_: i32) void {
   s.stop();
   s.deinit();
}

pub fn main() !void {
    // initialize our server on the port 3000
    s = try server.Server.init(std.heap.smp_allocator, 3000);

    // setup a signal interrupt callback
    std.posix.sigaction(std.posix.SIG.INT, &.{
        .handler = .{ .handler = shutdown },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    }, null);

    // start the server listener.
    s.listen() catch |err| {
        const errno = std.posix.errno(-1);
        std.debug.print("errno: {any}\n", .{errno});
        std.debug.print("err = {any}\n", .{err});
    };
}
```

### Example Subscriber

A simple subscriber.

```zig
const std = @import("std");
const chebi = @import("chebi");
const client = chebi.client;

pub fn main() !void {
    // Create our Connection Address.
    const addr = std.net.Address.initIp4([4]u8 {127,0,0,1}, 3000);

    // Initialize our client with the connection address.
    var c = try client.Client.init(std.heap.smp_allocator, addr);
    defer c.deinit();

    // Perform connection call.
    // This connects to the server and grabs server information,
    // like compression algorithm and msg size limit.
    try c.connect();

    // Subscribe to the "test" topic.
    try c.subscribe("test");

    // Wait for and grab the next message from the server.
    const msg = try c.next_msg();

    // print out info.
    std.debug.print("topic: {s}\n", .{msg.topic.?});
    std.debug.print("msg: {s}\n", .{msg.payload.?});
}
```

### Example Publisher

A simple publisher.

```zig
const std = @import("std");
const chebi = @import("chebi");
const client = chebi.client;

pub fn main() !void {
    // Create our Connection Address.
    const addr = std.net.Address.initIp4([4]u8 {127,0,0,1}, 3000);

    // Initialize our client with the connection address.
    var c = try client.Client.init(std.heap.smp_allocator, addr);
    defer c.deinit();

    // Perform connection call.
    // This connects to the server and grabs server information,
    // like compression algorithm and msg size limit.
    try c.connect();

    // Subscribe to the "test" topic.
    try c.subscribe("test");

    // Write text type message to the "test" topic.
    try c.write("test", "hello from pub", chebi.message.Type.text);

    // Ensure the message had enough time to send.
    std.time.sleep(std.time.ms_per_s * 5);

    // close the client.
    try c.close();
}
```

## Simple Demo

Simple demo of 2 subscribers and 1 publisher.

https://github.com/user-attachments/assets/27441712-afe1-4b85-b1d2-dc7ef17cec22

## Multiplexing Demo

Demo of 1 sub and 1 pub, where the pub starts by sending a 1GB file and in the
middle sends a small message before finishing the other large message.

The sub shows the small message is received and is not blocked by the larger
message.

https://github.com/user-attachments/assets/f4b2c556-daca-4699-8d73-37fd2741fb59
