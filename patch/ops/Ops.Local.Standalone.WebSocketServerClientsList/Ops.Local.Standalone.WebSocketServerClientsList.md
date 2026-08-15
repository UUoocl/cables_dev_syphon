# Ops.Local.Standalone.WebSocketServerClientsList

Monitors connected WebSocket clients and channel subscription topology from the Standalone HttpFileServer broker.

## Overview
Connects to `Ops.Local.Standalone.HttpFileServer` and outputs real-time client metadata, connection events, and active channel lists.

## Features
- **Connection Lifecycle Triggers**: Fires on client connection and disconnection.
- **Client Metadata**: Provides client IDs, IP addresses, connect timestamps, and per-client channel subscription sets.
- **Topology Discovery**: Outputs the list of all currently active channels on the broker.

## Clients

External clients (such as web browsers, Node.js scripts, Python apps, or mobile devices) can connect to the Cables Standalone WebSocket server using standard WebSocket protocols.

### 1. Connection URL
Connect to the host and port configured in `Ops.Local.Standalone.HttpFileServer` (default is `127.0.0.1:8080`):

```text
ws://127.0.0.1:8080
```
> [!NOTE]
> The server binds to `127.0.0.1` (loopback interface) by default to guarantee that only local connections from this machine can access the HTTP and WebSocket servers.

2. Message Protocol (JSON)
All control and data messages use standard JSON strings:

Subscribe to a Channel
```json
{
  "type": "subscribe",
  "channel": "cameraPos"
}
```

>TIP
>
>Use "channel": "*" to subscribe to all channels/topics.



### Publish / Send Data to a Channel
```json
{
  "type": "publish",
  "channel": "cameraPos",
  "data": { "x": 12.5, "y": 3.2, "z": -1.0 }
}
```

###Broadcast to All Clients or All Channels

```json
{
  "type": "publish",
  "sendToAllClients": true,
  "data": { "command": "resetScene" }
}
```

### Unsubscribe from a Channel

```json
{
  "type": "unsubscribe",
  "channel": "cameraPos"
}
```

### Receiving Messages
When Cables or another client publishes to a channel you are subscribed to, the server pushes an envelope like:

```json
{
  "type": "message",
  "channel": "cameraPos",
  "data": { "x": 12.5, "y": 3.2, "z": -1.0 },
  "sender": "patch",
  "timestamp": 1724238219350
}
```

## Code Examples
A. Browser / Frontend JavaScript

```javascript
const ws = new WebSocket("ws://localhost:8080");
ws.onopen = () => {
  console.log("Connected to Cables Standalone broker");
  // 1. Subscribe to a topic
  ws.send(JSON.stringify({
    type: "subscribe",
    channel: "myTopic"
  }));
  // 2. Publish a message to Cables
  ws.send(JSON.stringify({
    type: "publish",
    channel: "myTopic",
    data: { value: 42, label: "speed" }
  }));
};
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.type === "message") {
    console.log(`[${msg.channel}] from ${msg.sender}:`, msg.data);
  }
};
B. Python Client (using websockets or websocket-client)
python
import asyncio
import json
import websockets
async def run():
    uri = "ws://localhost:8080"
    async with websockets.connect(uri) as ws:
        # Subscribe
        await ws.send(json.dumps({
            "type": "subscribe",
            "channel": "sensors"
        }))
        
        # Publish
        await ws.send(json.dumps({
            "type": "publish",
            "channel": "sensors",
            "data": {"temperature": 23.4, "humidity": 55}
        }))
        
        # Listen for messages
        async for message in ws:
            payload = json.loads(message)
            print("Received from Cables:", payload)
asyncio.run(run())

C. CLI Quick Test (using wscat)

```bash
# Connect with wscat
npx wscat -c ws://localhost:8080
# Inside wscat prompt:
> {"type":"subscribe","channel":"test"}
> {"type":"publish","channel":"test","data":"Hello from terminal!"}
