# Ops.Local.Standalone.WebSocketPub

Publishes messages to a specific channel/topic on the Cables Standalone WebSocket server broker.

## Overview
Connects to the `Server Instance` output of `Ops.Local.Standalone.HttpFileServer` and publishes messages to connected browser clients, mobile interfaces, or other remote subscribers.

## Features
- **Channel-Targeted Publishing**: Broadcasts messages exclusively to clients subscribed to the specified channel.
- **Direct Unicast**: Target a specific client by providing their unique `Target Client ID`.
- **Message Retention**: Set `Retain` to true to cache state on the server so newly connecting clients immediately receive the latest state upon subscribing.
