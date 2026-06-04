# Chebi Protocol RFC

|                   |                                                        |
|-------------------|--------------------------------------------------------|
| **Title**         | Chebi Message Bus Protocol v0                          |
| **Status**        | Experimental                                           |
| **Implementation**| https://codeberg.org/jmatth11/chebi                    |

---

## 1. Introduction

Chebi is a lightweight, topic-based message bus designed for local, ephemeral use
cases. It runs over TCP and supports text and binary messages, topic
subscribe/unsubscribe semantics, channel-based multiplexing within a single
connection, and optional (currently non-functional) compression.

The protocol is inspired by WebSocket framing but adapted for pub/sub
workloads: a fixed 6-byte header precedes every packet, and large messages are
split across multiple packets using a FIN flag mechanism.

---

## 2. Wire Protocol

Every unit of data on the wire is a **packet**. A packet consists of a 6-byte
header followed by an optional body.

### 2.1 Header Layout (6 bytes)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|F| Ver | OpCode|C| Channel (7) |       Topic Length (16)       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|     Payload Length (16)       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

**Byte 0 – Flags**

```
   0   1 2 3  4 5 6 7
+-----+-----+--------+
| Fin | Ver | OpCode |
+-----+-----+--------+
```

| Field     | Size    | Description                                              |
|-----------|---------|----------------------------------------------------------|
| Fin       | 1 bit   | Final fragment flag. `1` if this is the last (or only) packet of a message. |
| Version   | 3 bits  | Protocol version. Currently `0`.                         |
| OpCode    | 4 bits  | Indicates the packet type (see §2.3).                   |

**Byte 1 – Info**

```
       0       1 2 3 4 5 6 7
+-------------+-------------+
| Compression |   Channel   |
+-------------+-------------+
```

| Field      | Size   | Description                                           |
|------------|--------|-------------------------------------------------------|
| Compressed | 1 bit  | `1` if the payload is compressed.                     |
| Channel    | 7 bits | Multiplexing channel identifier (see §5). Value `0..127`. |

**Bytes 2–3 – Topic Length** (u16, little-endian)

The byte-length of the topic name that follows in the body.

**Bytes 4–5 – Payload Length** (u16, little-endian)

The byte-length of the payload that follows the topic name in the body.

A topic_length of `0` indicates a control frame (no topic). A payload_length of
`0` indicates an empty payload.

### 2.2 Body Layout

```
+-------------------+-----------------------+
| Topic (topic_len) | Payload (payload_len) |
+-------------------+-----------------------+
```

- **Topic**: UTF-8 (or arbitrary bytes) topic name, `topic_len` bytes.
- **Payload**: Arbitrary binary data, `payload_len` bytes.

For control opcodes (values `8..15`), the topic is typically empty and the
payload may carry control data.

### 2.3 OpCodes

| Code | Name              | Type      | Direction        | Description                                   |
|------|-------------------|-----------|------------------|-----------------------------------------------|
| 0    | `nc_continue`     | Non-control | Client ↔ Server | Intermediate fragment of a multi-packet message. |
| 1    | `nc_text`         | Non-control | Client ↔ Server | Final fragment; payload is text.              |
| 2    | `nc_bin`          | Non-control | Client ↔ Server | Final fragment; payload is binary data.       |
| 3–7  | *(reserved)*      | —         | —                | Reserved for future non-control codes.        |
| 8    | `c_connection`    | Control   | Client → Server  | Connection request (handshake).               |
|      |                   |           | Server → Client  | Connection response with server capabilities. |
| 9    | `c_close`         | Control   | Client → Server  | Graceful connection close.                    |
| 10   | `c_ping`          | Control   | Client → Server  | Keep-alive ping.                              |
| 11   | `c_pong`          | Control   | Server → Client  | Ping response (updates client timestamp).     |
| 12   | `c_subscribe`     | Control   | Client → Server  | Subscribe to a topic (topic in body).         |
| 13   | `c_unsubscribe`   | Control   | Client → Server  | Unsubscribe from a topic (topic in body).     |
| 14–15| *(reserved)*      | —         | —                | Reserved for future control codes.            |

### 2.4 Connection Response Payload (ServerFlags)

The server responds to a `c_connection` packet with a payload whose first byte
is a `ServerFlags` bit-field:

```
  0   1  2 3 4 5 6 7
+---+---+-----------+
|Msg|Cmp|(reserved) |
|Lmt|   | 6 bits    |
+---+---+-----------+
```

| Field         | Size   | Description                                             |
|---------------|--------|---------------------------------------------------------|
| msg_limit     | 1 bit  | Server has a maximum message size limit.                |
| compression   | 1 bit  | Server supports compression (`1`) or not (`0`).         |
| reserved      | 6 bits | Reserved, must be `0`.                                  |

**If compression is supported** (`compression = 1`):
The next byte (offset 1) contains the `CompressionType`:

| Value | Type   |
|-------|--------|
| 0     | none   |
| 1     | raw    |
| 2     | gzip   |
| 3     | zlib   |

**If msg_limit is set** (`msg_limit = 1`):
The next 8 bytes (offset 2–9, or offset 1–8 when compression is disabled)
contain a `usize` in little-endian format representing the maximum allowed
payload bytes per message.

---

## 3. Packet Model

### 3.1 Packet

The smallest addressable unit on the wire. Defined in `src/packet.zig`.

```
Packet {
    header: Protocol       // 6-byte wire header
    body: ?[]u8            // topic + payload bytes (may be null for zero-length)
}
```

A packet always carries the full topic name, even in intermediate fragments.
This allows reassembly to validate topic consistency across fragments.

### 3.2 PacketCollection

A logical message may span multiple packets. A `PacketCollection` groups
fragments by:

- **topic** – all fragments must share the same topic.
- **channel** – all fragments must share the same channel ID.
- **opcode** – the final fragment's opcode (`nc_text` or `nc_bin`) is the
  collection's opcode.

```
PacketCollection {
    opcode: OpCode
    version: u8
    channel: u8
    topic: []const u8
    packets: []Packet       // ordered fragments
    limit: ?usize           // server-imposed max payload size
}
```

### 3.3 Fragmentation

When a message's payload exceeds 1024 bytes (the max fragment size), the sender
splits it into multiple packets:

1. All intermediate fragments carry `opcode = nc_continue` and `fin = 0`.
2. The final fragment carries `opcode = nc_text` or `nc_bin` and `fin = 1`.
3. Every fragment repeats the full topic name.
4. A single-packet message has `fin = 1` and the appropriate opcode
   (`nc_text`/`nc_bin`).

---

## 4. Message Model

Defined in `src/message.zig`. A **Message** is the application-level
abstraction. It is the entire payload a client sends or receives.

```
Message {
    msg_type: Type          // text | bin | compressed
    topic: ?[]const u8
    payload: ?[]const u8
    compression_type: CompressionType
}
```

When sending, a message is converted into one or more packets via
`packet_collection()`. When receiving, packets are assembled into a
`PacketCollection` and then converted back into a `Message` via
`from_packet_collection()`.

| Message Type  | Corresponding OpCode | Notes                           |
|---------------|----------------------|----------------------------------|
| `text`        | `nc_text`            | Plain text payload.              |
| `bin`         | `nc_bin`             | Arbitrary binary payload.        |
| `compressed`  | `nc_bin`             | Same as bin; compression flag set in header's Info byte. |

---

## 5. Channel Multiplexing

Channels allow a single TCP connection to interleave multiple logical message
streams. A large message on channel 0 does not block a small message on channel
1.

### 5.1 Channel Field

The 7-bit `channel` field in the Info byte (byte 1 of the header) identifies
which logical stream a packet belongs to. Valid range: `0..127`.

### 5.2 Client Channel Assignment

`client.zig` uses an atomic counter that wraps at 127 to assign a fresh channel
for every outgoing message. This means concurrent `write()` calls from the same
client get distinct channels and won't corrupt each other.

### 5.3 Channel Reassembly

Incoming packets are grouped by (topic, client FD, channel). The hierarchy is:

```
PacketManager
  └── topic (String)
       └── client FD (std.c.fd_t)
            └── ChannelCollection
                 └── channel (u7) → PacketCollection
```

The `ChannelCollection` stores incomplete `PacketCollection` values keyed by
channel. When a packet with `fin = 1` arrives on a channel, the complete
`PacketCollection` is popped and forwarded for delivery.

If a new packet arrives on a channel that already has a collection with a
different topic, the old partial collection is discarded and replaced — this
handles the case where a client's channel counter resets or reuses a channel.

---

## 6. Server Architecture

Defined in `src/server.zig`.

### 6.1 Event Loop

The server uses `epoll` with edge-triggered (ET) notifications:

```
while (running):
    n = epoll_wait()
    for i in 0..n:
        if fd is listener → accept()
        elif EPOLLIN → event(fd)         // read incoming data
        if EPOLLOUT → process_eagain(fd) // retry blocked writes
        if EPOLLRDHUP | EPOLLHUP → remove(fd) // connection closed
    process()  // deliver ready messages to subscribers
```

### 6.2 Connection Lifecycle

1. **accept()** – Non-blocking `accept4` with `SOCK_NONBLOCK`. The new FD is
   added to epoll.
2. **c_connection** – The server registers the client in the Manager and replies
   with a `c_connection` packet carrying `ServerFlags` (compression support,
   message size limit).
3. **c_subscribe / c_unsubscribe** – Topic subscriptions are tracked in the
   Manager (see §8).
4. **c_ping / c_pong** – Ping updates the client's `last_active` timestamp in
   the Manager.
5. **c_close** – The client is removed from epoll and the Manager; the socket is
   closed.

### 6.3 Message Delivery

When a `nc_continue` / `nc_text` / `nc_bin` packet arrives:

1. The packet is passed to `PacketManager.store_or_pop()`. If the message is
   complete (all fragments received), a `PacketCollection` is returned.
2. The server looks up subscribers for the collection's topic via the Manager.
3. A `PacketHandlerInfo` is created containing the collection and a clone of
   the recipient list.
4. The info is pushed onto the `PacketHandler` queue for delivery.

### 6.4 PacketHandler & Threaded Delivery

Defined in `src/handler.zig`. Delivery uses a thread pool:

```
process():
    for each pending PacketHandlerInfo:
        pool.spawn(process_threaded, info)
    pool.waitAndWork(wg)

process_threaded(info):
    for each recipient FD:
        for each packet in collection:
            send(packet, recipient)
```

If `send()` returns `EAGAIN` (would block), the collection is duplicated and
stored in a `try_again_list`. On the next `EPOLLOUT` event for that FD, the
send is retried (up to `MAX_ATTEMPTS = 5` times, then dropped).

### 6.5 Signal Handling

The server uses `signalfd` to handle `SIGINT` and `SIGTERM` within the epoll
loop, allowing clean shutdown.

---

## 7. Client Architecture

Defined in `src/client.zig`.

### 7.1 Connection

```
connect():
    TCP connect to server address
    send c_connection packet (fin=1, opcode=c_connection)
    receive c_connection response
    parse ServerFlags to determine compression type and message limit
```

TCP_NODELAY is enabled on the client socket.

### 7.2 Publishing

```
write(topic, payload, msg_type):
    create Message
    if compression enabled and applicable → set compression type
    msg.packet_collection(channel) → PacketCollection
    for each packet in collection:
        write_packet(socket, packet)
```

If the payload exceeds 1024 bytes, the message is transparently fragmented into
multiple packets (see §3.3).

### 7.3 Subscribing

```
next_msg():
    while not received:
        read_packet() → Packet
        packetManager.store_or_pop(fd, packet) → ?PacketCollection
        if collection returned:
            if compressed → set decompression
            msg.from_packet_collection(collection)
            return msg
```

The client uses the same `PacketManager` hierarchy for reassembly, just like
the server. Partial packet reads are handled by `reader.zig` which stores
partially-received packets in a global `PartialPackets` map keyed by socket FD.

---

## 8. Topic Management (Manager)

Defined in `src/manager.zig`.

### 8.1 Data Structures

```
Manager {
    topics:  StringHashMap→SocketList   // topic → list of subscribed FDs
    clients: HashMap→ClientInfo         // FD → client metadata
}

ClientInfo {
    fd: std.c.fd_t
    last_active: Instant
    topics: []const u8                  // topics this client is subscribed to
}
```

### 8.2 Operations

| Operation        | Description                                               |
|------------------|-----------------------------------------------------------|
| `add_topic`      | Create a topic entry (no-op if already exists).           |
| `add_client`     | Register client FD (no-op if already registered).         |
| `subscribe`      | Add FD to topic's subscriber list and topic to client's list. Duplicates are ignored. |
| `unsubscribe`    | Remove FD from topic and topic from client.               |
| `unsubscribe_all`| Remove client from all subscribed topics and delete client.|
| `client_list`    | Return all FDs subscribed to a topic.                     |
| `update_client_timestamp` | Update client's `last_active` (used by pong).    |

Topic keys are heap-duplicated to ensure stable pointers for the subscriber
lists.

---

## 9. Reader & Writer

### 9.1 Reader (`src/reader.zig`)

`next_packet()` reads one complete packet from a socket:

1. Attempt to read a partial packet from the global `PartialPackets` map for
   this FD.
2. If no partial packet exists, allocate a new `Packet` and read 6 header bytes.
3. Parse the header to determine topic_len and payload_len.
4. Read the body bytes.
5. If fewer bytes arrive than expected, store the partial packet and return
   `payload_len_invalid` — the caller is expected to retry.

Partial packets are stored in a global `std.AutoHashMap(std.c.fd_t, Packet)`
using the SMP allocator.

### 9.2 Writer (`src/write.zig`)

`write_packet()` serialises and sends a packet:

1. Allocate a buffer of `header_size() + body.len`.
2. Call `packet.write()` to serialise header + body into the buffer.
3. Call `send()` on the socket.
4. If `send()` returns `EAGAIN`, return `would_block`.

---

## 10. Compression

Defined in `src/compression.zig`.

The protocol reserves the `compressed` flag in the Info byte and a
`CompressionType` enum (`none`, `raw`, `gzip`, `zlib`). ServerFlags advertise
whether compression is supported.

**Current status**: Compression is **not functional**. Both `compress()` and
`decompress()` call `@panic()` because the Zig standard library's `flate`
module was removed. The code paths are wired through — the flag is set on
outgoing packets and checked on incoming packets — but execution never reaches
the compression logic.

---

## 11. OpCode Flow Summary

```
Client                      Server
  │                           │
  ├── c_connection ──────────►│
  │◄────────── c_connection ──┤  (ServerFlags)
  │                           │
  ├── c_subscribe ───────────►│
  ├── c_unsubscribe ─────────►│
  │                           │
  ├── nc_text/nc_bin ────────►│  (published message)
  │   (one or more packets)   │  ├── store_or_pop()
  │                           │  ├── lookup subscribers
  │                           │  └── deliver to subscribers
  │                           │
  ├── c_ping ────────────────►│
  │◄────────── c_pong ────────┤
  │                           │
  ├── c_close ───────────────►│
  │                           │  (close socket, cleanup)
```

---

## 12. Security Considerations

- Chebi is designed for **trusted local networks only**.
- There is no authentication, encryption, or access control.
- There is no rate limiting or back-pressure mechanism beyond TCP flow control
  and the `try_again` retry logic.
- Message size limits are optional and advertised but not enforced by the
  protocol — only by the server's `PacketManager`.
- The protocol is experimental and the implementation may contain bugs.

---

## 13. References

- Source: https://codeberg.org/jmatth11/chebi
- `src/protocol.zig` — Protocol header structures and wire serialisation.
- `src/packet.zig` — Packet, PacketCollection, ChannelCollection, PacketManager.
- `src/message.zig` — Application-level message abstraction.
- `src/server.zig` — Epoll-based server event loop.
- `src/client.zig` — Client connection, publish, subscribe, read.
- `src/manager.zig` — Topic and client subscription management.
- `src/handler.zig` — Multi-threaded packet delivery with EAGAIN retry.
- `src/reader.zig` — Socket reading with partial packet support.
- `src/write.zig` — Socket writing.
- `src/compression.zig` — Compression stubs (non-functional).
- `src/poll.zig` — Epoll wrapper with signalfd support.
