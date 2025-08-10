# Chebi

**!! still experimental !!**

A small message bus that written in zig to easily spin up on the fly.

The goal of this message bus is to provide support for standard text and binary
formats, with options for compression, and handles multiplexing messages.

## Standard Capabilities

The standard capabilities are supported:
- Subscribing and unsubscribing to topics
- Writing and reading from topics.

## Compression

The spec contains a flag for compression, which you can toggle on and off.
No compression is implemented out-of-the-box yet. But this is planned to be handled
automatically for the clients.

## Multiplexed Messaging

The spec allows for messages to be grouped by top-down of topic, client socket, and message channel.
This allows large messages to not clog up the pipeline if smaller messages can be proessed quicker.

## Demo


