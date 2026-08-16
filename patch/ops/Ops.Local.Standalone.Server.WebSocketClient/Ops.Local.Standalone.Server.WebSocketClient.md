# Ops.Local.Standalone.Server.WebSocketClient

Connects a Cables patch as a client to a WebSocket server broker (such as `Ops.Local.Standalone.Server.HttpFileServer` or any remote WebSocket server).

## Overview
Provides a full-featured client connection manager that supports auto-reconnection, heartbeat/keepalive handling, and state synchronization with `WebSocketClientSub` and `WebSocketClientPub` ops.

## Features
- **Auto-Reconnection**: Automatically detects connection loss and reconnects with configurable backoff.
- **Automatic Subscription Sync**: Restores all active channel subscriptions immediately upon reconnecting.
- **Universal Compatibility**: Runs both inside Cables Standalone and in browser-based Cables patches.


>Three new client-side operations have been created to allow any Cables patch (running in another Standalone instance or in a web browser) to connect to the >WebSocket server, manage channel subscriptions, and exchange messages:

---

### 1. New Client Operations

| Operation | Purpose |
| :--- | :--- |
| **[`Ops.Local.Standalone.Server.WebSocketClient`](file:///Users/jonwood/Github_local_dev/cables_standalone_for_mac/patch/ops/Ops.Local.Standalone.Server.WebSocketClient/Ops.Local.Standalone.Server.WebSocketClient.js)** | Establishes and manages the WebSocket connection to `ws://127.0.0.1:8080` with automatic reconnect and state sync. |
| **[`Ops.Local.Standalone.Server.WebSocketClientSub`](file:///Users/jonwood/Github_local_dev/cables_standalone_for_mac/patch/ops/Ops.Local.Standalone.Server.WebSocketClientSub/Ops.Local.Standalone.Server.WebSocketClientSub.js)** | Subscribes to a specific channel/topic (or `*` for all), handles incoming messages, and automatically resubscribes upon reconnecting. |
| **[`Ops.Local.Standalone.Server.WebSocketClientPub`](file:///Users/jonwood/Github_local_dev/cables_standalone_for_mac/patch/ops/Ops.Local.Standalone.Server.WebSocketClientPub/Ops.Local.Standalone.Server.WebSocketClientPub.js)** | Publishes data payloads to specific channels, specific client IDs, or broadcasts to all clients/channels. |

---

### 2. How to Use in a Client Cables Patch

```
[ Ops.Local.Standalone.Server.WebSocketClient ] (URL: ws://127.0.0.1:8080)
   │
   ├─► [Client Connection] ──► [ Ops.Local.Standalone.Server.WebSocketClientSub ] (Channel: "sensors")
   │                               └─► [On Message] ──► [Data] ──► (Your patch logic)
   │
   └─► [Client Connection] ──► [ Ops.Local.Standalone.Server.WebSocketClientPub ] (Channel: "controls")
                                  ├─► [Data] (Object / Value)
                                  └─► [Publish] (Trigger)
```

---

### 3. Key Features

1. **Automatic Subscription Lifecycle**: When you change the `Channel` port in `WebSocketClientSub`, it automatically sends `unsubscribe` for the old channel and `subscribe` for the new channel.
2. **Auto-Reconnect with Subscription Recovery**: If the connection drops or the server restarts, `WebSocketClient` automatically reconnects and re-establishes all active channel subscriptions seamlessly.
3. **Cross-Compatible**: Works inside Cables Standalone for Mac, in separate Electron instances, or inside standard browser-based Cables exports without needing native Node dependencies.
4. **Interchangeability**: [`Ops.Local.Standalone.Server.WebSocketServerSub`](file:///Users/jonwood/Github_local_dev/cables_standalone_for_mac/patch/ops/Ops.Local.Standalone.Server.WebSocketServerSub/Ops.Local.Standalone.Server.WebSocketServerSub.js) and [`Ops.Local.Standalone.Server.WebSocketServerPub`](file:///Users/jonwood/Github_local_dev/cables_standalone_for_mac/patch/ops/Ops.Local.Standalone.Server.WebSocketServerPub/Ops.Local.Standalone.Server.WebSocketServerPub.js) have also been updated so their connection inputs accept both `Server Instance` and `Client Connection` objects.