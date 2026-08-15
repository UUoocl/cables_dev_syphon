# Ops.Local.Standalone.WebSocketServerPub

Publishes messages to a specific channel/topic on the Cables Standalone WebSocket server broker.

## Overview
Connects to the `Server Instance` output of `Ops.Local.Standalone.HttpFileServer` and publishes messages to connected browser clients, mobile interfaces, or other remote subscribers.

## Features
- **Channel-Targeted Publishing**: Broadcasts messages exclusively to clients subscribed to the specified channel.
- **Broadcast to All Clients**: Enable `Send to All Clients` (or target `'*'`) to send payloads to every connected client across all subscriptions.
- **Send to All Channels**: Enable `Send to All Channels` (or set channel to `'*'`) to dispatch global broadcasts to subscribers of any channel.
- **Direct Unicast**: Target a specific client by providing their unique `Target Client ID`.
- **Message Retention**: Set `Retain` to true to cache state on the server so newly connecting clients immediately receive the latest state upon subscribing.
