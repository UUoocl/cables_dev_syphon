# Ops.Local.Standalone.HttpFileServer

High-performance HTTP File Server & WebSocket Pub/Sub Broker for Cables Standalone.

## Summary
Hosts static web files, Server-Sent Events (SSE) streams, REST API endpoints, and a multi-channel WebSocket Pub/Sub broker from inside Cables Standalone.

## Features
- **Static File Serving**: Serves HTML, JS, CSS, WebAssembly, GLTF/GLB models, video, and audio assets with full MIME type mapping and Cross-Origin Resource Sharing (CORS) enabled.
- **REST API Route**: Captures incoming HTTP requests on `/api/*` and fires Cables triggers with parsed queries and POST bodies.
- **SSE Streaming**: Broadcasts live event streams on `/sse` with automatic heartbeat keeping connections alive.
- **Integrated WebSocket Broker**: Powers real-time pub/sub messaging across web browsers, mobile devices, remote controllers, and Cables patch graphs via modular `WebSocketPub`, `WebSocketSub`, and `WebSocketClients` ops.
