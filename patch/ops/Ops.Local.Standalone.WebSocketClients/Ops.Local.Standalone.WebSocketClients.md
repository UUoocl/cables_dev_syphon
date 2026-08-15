# Ops.Local.Standalone.WebSocketClients

Monitors connected WebSocket clients and channel subscription topology from the Standalone HttpFileServer broker.

## Overview
Connects to `Ops.Local.Standalone.HttpFileServer` and outputs real-time client metadata, connection events, and active channel lists.

## Features
- **Connection Lifecycle Triggers**: Fires on client connection and disconnection.
- **Client Metadata**: Provides client IDs, IP addresses, connect timestamps, and per-client channel subscription sets.
- **Topology Discovery**: Outputs the list of all currently active channels on the broker.
