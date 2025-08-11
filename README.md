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

## Examples

You can find different examples in the `examples/` folder.

## Simple Demo

Simple demo of 2 subscribers and 2 publisher.

https://github.com/user-attachments/assets/27441712-afe1-4b85-b1d2-dc7ef17cec22

## Multiplexing Demo

Demo of 1 sub and 1 pub, where the pub starts by sending a 1GB file and in the
middle sends a small message before finishing the other large message.

The sub shows the small message is received and is not blocked by the larger
message.

https://github.com/user-attachments/assets/f4b2c556-daca-4699-8d73-37fd2741fb59
