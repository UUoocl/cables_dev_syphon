# Ops.Local.Standalone.Server.WebSocketServerSub

Subscribes to messages arriving on a specific WebSocket channel/topic from remote clients or the Cables Standalone server broker.

## Overview
Connects to `Ops.Local.Standalone.Server.HttpFileServer` and fires triggers when incoming messages matching the configured `Channel` (or wildcard `*`) arrive.

## Features
- **Channel Filtering**: Listen to dedicated channels (e.g. `touchControls`, `gestures`) or capture all traffic with `*`.
- **Automatic JSON Parsing**: Automatically decodes JSON strings into structured JavaScript objects.
- **Client Origin Tracking**: Identifies the sender client ID for easy unicast replies or multi-user state tracking.
