const http = op.require("http");
const fs = op.require("fs");
const path = op.require("path");
const url = op.require("url");
const EventEmitter = op.require("events");
let WebSocket = null;
let WebSocketServer = null;
function getWebSocketModule()
{
    if (WebSocketServer) return WebSocketServer;
    try
    {
        if (typeof op !== "undefined" && op.require) WebSocket = op.require("ws");
    }
    catch (e) {}
    try
    {
        if (!WebSocket && typeof window !== "undefined" && window.nodeRequire) WebSocket = window.nodeRequire("ws");
    }
    catch (e) {}
    try
    {
        if (!WebSocket && typeof require !== "undefined") WebSocket = require("ws");
    }
    catch (e) {}

    if (WebSocket)
    {
        WebSocketServer = WebSocket.WebSocketServer || WebSocket.Server || WebSocket;
    }
    return WebSocketServer;
}

const
    inHost = op.inString("Hostname", "127.0.0.1"),
    inPort = op.inInt("Port", 8080),
    inRootDir = op.inString("Root Directory", ""),
    inAutoStart = op.inBool("Auto Start", true),
    inStart = op.inTriggerButton("Start Server"),
    inStop = op.inTriggerButton("Stop Server"),

    inEnableSse = op.inBool("Enable SSE", true),
    inSseRoute = op.inString("SSE Route", "/sse"),
    inSseEvent = op.inString("SSE Event Name", "message"),
    inSseData = op.inObject("SSE Data"),
    inSseBroadcast = op.inTrigger("Broadcast SSE"),

    inEnableApi = op.inBool("Enable API", true),
    inEnableWs = op.inBool("Enable WS", true),

    outStarted = op.outTrigger("Server Started"),
    outStopped = op.outTrigger("Server Stopped"),
    outIsReady = op.outTrigger("Server Ready"),
    outRunning = op.outBoolNum("Running", false),
    outServerInstance = op.outObject("Server Instance"),

    outHttpRequest = op.outTrigger("HTTP Request"),
    outHttpUrl = op.outString("HTTP URL"),
    outHttpReqData = op.outObject("HTTP Request Data"),
    outHttpResData = op.outObject("HTTP Response Data"),

    outSseActiveClients = op.outNumber("SSE Active Clients", 0),
    outWsActiveClients = op.outNumber("WS Active Clients", 0),
    outError = op.outString("Error");

outHttpResData.ignoreValueSerialize = true;
outServerInstance.ignoreValueSerialize = true;

let server = null;
let wss = null;
let broker = null;
const sseClientsByRoute = new Map();

const mimeTypes = {
    ".html": "text/html",
    ".js": "application/javascript",
    ".mjs": "application/javascript",
    ".wasm": "application/wasm",
    ".css": "text/css",
    ".json": "application/json",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".webp": "image/webp",
    ".ico": "image/x-icon",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".ogv": "video/ogg",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg"
};

// Set default root directory to patch directory if available
const paths = op.patch.config.paths || {};
if (paths.patchPath && !inRootDir.get()) inRootDir.set(paths.patchPath);

op.onDelete = stop;
inHost.onChange = restart;
inPort.onChange = restart;
inRootDir.onChange = restart;

class PubSubBroker extends EventEmitter
{
    constructor()
    {
        super();
        this.clients = new Map(); // id -> { id, ws, ip, connectedAt, subscriptions: Set }
        this.channels = new Map(); // channel -> Set of clientIds
        this.retained = new Map(); // channel -> lastMessage
    }

    registerClient(ws, req)
    {
        const id = "ws_" + Math.random().toString(36).substring(2, 9) + "_" + Date.now().toString(36);
        const ip = req && (req.headers["x-forwarded-for"] || req.socket.remoteAddress) || "127.0.0.1";
        const clientInfo = {
            "id": id,
            "ws": ws,
            "ip": ip,
            "connectedAt": Date.now(),
            "subscriptions": new Set()
        };
        this.clients.set(id, clientInfo);
        ws._pubsubClientId = id;

        this.emit("clientConnect", clientInfo);
        return clientInfo;
    }

    unregisterClient(id)
    {
        const client = this.clients.get(id);
        if (!client) return;

        client.subscriptions.forEach((channel) =>
        {
            const set = this.channels.get(channel);
            if (set)
            {
                set.delete(id);
                if (set.size === 0) this.channels.delete(channel);
            }
        });

        this.clients.delete(id);
        this.emit("clientDisconnect", client);
    }

    subscribe(clientId, channel)
    {
        if (!channel || typeof channel !== "string") return false;
        const client = this.clients.get(clientId);
        if (!client) return false;

        client.subscriptions.add(channel);
        if (!this.channels.has(channel)) this.channels.set(channel, new Set());
        this.channels.get(channel).add(clientId);

        this.emit("clientSubscribe", { "clientId": clientId, "channel": channel });

        // Send retained message if available
        if (this.retained.has(channel))
        {
            const retainedPayload = this.retained.get(channel);
            this._sendToClient(client, {
                "type": "message",
                "channel": channel,
                "data": retainedPayload,
                "retained": true,
                "timestamp": Date.now()
            });
        }
        return true;
    }

    unsubscribe(clientId, channel)
    {
        const client = this.clients.get(clientId);
        if (!client) return false;

        client.subscriptions.delete(channel);
        const set = this.channels.get(channel);
        if (set)
        {
            set.delete(clientId);
            if (set.size === 0) this.channels.delete(channel);
        }

        this.emit("clientUnsubscribe", { "clientId": clientId, "channel": channel });
        return true;
    }

    publish(channel, data, opts = {})
    {
        const { senderClientId, targetClientId, retain } = opts;
        if (!channel || typeof channel !== "string") return 0;

        if (retain)
        {
            this.retained.set(channel, data);
        }

        const messageEnvelope = {
            "type": "message",
            "channel": channel,
            "data": data,
            "sender": senderClientId || "patch",
            "timestamp": Date.now()
        };

        let recipientCount = 0;

        // Targeted unicast
        if (targetClientId)
        {
            const targetClient = this.clients.get(targetClientId);
            if (targetClient && this._sendToClient(targetClient, messageEnvelope))
            {
                recipientCount++;
            }
        }
        else
        {
            // Send to all subscribers of this channel + wildcard subscribers
            const directSubscribers = this.channels.get(channel) || new Set();
            const wildcardSubscribers = this.channels.get("*") || new Set();

            const recipients = new Set([...directSubscribers, ...wildcardSubscribers]);

            recipients.forEach((cid) =>
            {
                // Avoid echoing back to sender unless echo option is explicitly true
                if (cid === senderClientId && opts.echo !== true) return;
                const client = this.clients.get(cid);
                if (client && this._sendToClient(client, messageEnvelope))
                {
                    recipientCount++;
                }
            });
        }

        // Fire internal event for Cables patch operators
        this.emit("message", {
            "channel": channel,
            "data": data,
            "sender": senderClientId || "patch",
            "raw": messageEnvelope,
            "timestamp": messageEnvelope.timestamp
        });

        // Also emit channel-specific event
        this.emit(`channel:${channel}`, data, senderClientId || "patch", messageEnvelope);

        return recipientCount;
    }

    _sendToClient(client, obj)
    {
        if (!client || !client.ws) return false;
        const openState = WebSocket.OPEN !== undefined ? WebSocket.OPEN : 1;
        if (client.ws.readyState !== openState) return false;

        try
        {
            client.ws.send(JSON.stringify(obj));
            return true;
        }
        catch (err)
        {
            return false;
        }
    }

    handleMessage(client, messageStr)
    {
        let parsed = null;
        try
        {
            if (Buffer.isBuffer(messageStr)) messageStr = messageStr.toString();
            parsed = JSON.parse(messageStr);
        }
        catch (e)
        {
            // Unparseable raw message
            this.emit("rawMessage", { "clientId": client.id, "data": messageStr });
            return;
        }

        if (!parsed || typeof parsed !== "object") return;

        const actionType = parsed.type || parsed.action || "";

        // Subscription
        if (actionType === "subscribe" || actionType === "sub")
        {
            const channel = parsed.channel || parsed.topic;
            if (channel) this.subscribe(client.id, channel);
            return;
        }

        // Unsubscription
        if (actionType === "unsubscribe" || actionType === "unsub")
        {
            const channel = parsed.channel || parsed.topic;
            if (channel) this.unsubscribe(client.id, channel);
            return;
        }

        // Ping / Heartbeat
        if (actionType === "ping")
        {
            this._sendToClient(client, { "type": "pong", "timestamp": Date.now() });
            return;
        }

        // Publish event from client
        if (actionType === "publish" || parsed.channel || parsed.topic)
        {
            const channel = parsed.channel || parsed.topic || "default";
            const data = parsed.data !== undefined ? parsed.data : parsed.payload !== undefined ? parsed.payload : parsed;
            this.publish(channel, data, {
                "senderClientId": client.id,
                "retain": Boolean(parsed.retain),
                "targetClientId": parsed.targetClientId || null
            });
            return;
        }

        // General message fallback
        this.emit("message", {
            "channel": "general",
            "data": parsed,
            "sender": client.id,
            "raw": parsed,
            "timestamp": Date.now()
        });
    }

    getClientList()
    {
        const list = [];
        this.clients.forEach((c) =>
        {
            list.push({
                "id": c.id,
                "ip": c.ip,
                "connectedAt": c.connectedAt,
                "subscriptions": Array.from(c.subscriptions)
            });
        });
        return list;
    }

    getActiveChannels()
    {
        return Array.from(this.channels.keys());
    }

    getSubscriberCount(channel)
    {
        const set = this.channels.get(channel);
        return set ? set.size : 0;
    }

    clear()
    {
        this.clients.clear();
        this.channels.clear();
        this.retained.clear();
        this.removeAllListeners();
    }
}

function start()
{
    if (server) return;
    if (!http) return;

    broker = new PubSubBroker();

    server = http.createServer({ "noDelay": true, "keepAlive": true }, (req, res) =>
    {
        res.setHeader("Access-Control-Allow-Origin", "*");
        res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE");
        res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With, Range");

        if (req.method === "OPTIONS")
        {
            res.statusCode = 204;
            res.end();
            return;
        }

        const parsedUrl = url.parse(req.url);
        const pathname = parsedUrl.pathname;

        outHttpUrl.set(req.url);

        if (res.headersSent) return;

        // Health check route
        if (pathname === "/health")
        {
            res.statusCode = 200;
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify({
                "status": "ok",
                "wsClients": broker ? broker.clients.size : 0,
                "sseClients": getTotalSseClients()
            }));
            return;
        }

        // SSE route
        if (pathname === "/sse" || pathname.startsWith("/sse/"))
        {
            if (!inEnableSse.get())
            {
                res.statusCode = 403;
                res.end("SSE is disabled");
                return;
            }
            setupSse(req, res, pathname);
            return;
        }

        // Custom API route
        if (pathname === "/api" || pathname.startsWith("/api/"))
        {
            if (!inEnableApi.get())
            {
                res.statusCode = 403;
                res.end("API is disabled");
                return;
            }
            handleApiRequest(req, res, pathname);
            return;
        }

        // Static file serving
        let rootDir = inRootDir.get();
        if (!rootDir && paths.patchPath) rootDir = paths.patchPath;

        let filePath = path.join(rootDir, pathname);

        fs.stat(filePath, (err, stats) =>
        {
            if (res.headersSent) return;

            if (err)
            {
                res.statusCode = 404;
                res.end(`File ${pathname} not found!`);
                return;
            }

            if (stats.isDirectory())
            {
                filePath = path.join(filePath, "index.html");
            }

            fs.readFile(filePath, (readErr, data) =>
            {
                if (res.headersSent) return;

                if (readErr)
                {
                    res.statusCode = 500;
                    res.end(`Error getting the file: ${readErr}.`);
                }
                else
                {
                    const ext = path.parse(filePath).ext;
                    res.setHeader("Content-type", mimeTypes[ext] || "text/plain");
                    res.end(data);
                }
            });
        });
    });

    try
    {
        server.listen(inPort.get(), inHost.get(), (listenErr) =>
        {
            if (listenErr)
            {
                outRunning.set(false);
                outError.set(listenErr.message || String(listenErr));
                op.logWarn(listenErr);
                return;
            }

            outRunning.set(true);
            outError.set("");

            // Initialize WebSocket Server
            if (inEnableWs.get())
            {
                try
                {
                    const WSSClass = getWebSocketModule();
                    if (WSSClass && typeof WSSClass === "function")
                    {
                        wss = new WSSClass({ "server": server });
                        server.wss = wss;
                        server.broker = broker;
                        server.pubsub = broker;

                        wss.on("connection", (ws, req) =>
                        {
                            if (!inEnableWs.get())
                            {
                                ws.close(1008, "WebSocket is disabled");
                                return;
                            }

                            const client = broker.registerClient(ws, req);
                            outWsActiveClients.set(broker.clients.size);

                            ws.on("message", (msg) =>
                            {
                                broker.handleMessage(client, msg);
                            });

                            ws.on("close", () =>
                            {
                                broker.unregisterClient(client.id);
                                outWsActiveClients.set(broker.clients.size);
                            });

                            ws.on("error", (wsErr) =>
                            {
                                op.logWarn("[HttpFileServer WS Client Error]", wsErr);
                                broker.unregisterClient(client.id);
                                outWsActiveClients.set(broker.clients.size);
                            });
                        });

                        wss.on("error", (err) =>
                        {
                            op.logWarn("[HttpFileServer WS] Server Error:", err);
                        });
                    }
                    else
                    {
                        op.logWarn("[HttpFileServer] WebSocket module (ws) not available. Running HTTP/SSE only.");
                    }
                }
                catch (wsErr)
                {
                    op.logWarn("[HttpFileServer] Failed to initialize WebSocket server:", wsErr);
                }
            }

            outServerInstance.set({
                "server": server,
                "wss": wss,
                "broker": broker,
                "pubsub": broker
            });if (!server.toJSON)
            {
                server.toJSON = () => ({
                    "__type": "HttpServer",
                    "listening": server.listening,
                    "host": inHost.get(),
                    "port": inPort.get()
                });
            }

            outServerInstance.set(server);
            outStarted.trigger();

            // Health ready check
            const checkUrl = `http://${inHost.get()}:${inPort.get()}/health`;
            http.get(checkUrl, (resCheck) =>
            {
                if (resCheck.statusCode === 200)
                {
                    outIsReady.trigger();
                }
            }).on("error", (err) =>
            {
                op.logWarn("[HttpFileServer] Ready health check error:", err);
            });
        });

        server.on("error", (e) =>
        {
            outRunning.set(false);
            outError.set(e.message || String(e));
            op.logWarn("[HttpFileServer] Server error:", e);
        });
    }
    catch (e)
    {
        outRunning.set(false);
        outError.set(e.message || String(e));
        op.logWarn("[HttpFileServer] Exception on start:", e);
    }
}

function handleApiRequest(req, res, pathname)
{
    outHttpUrl.set(req.url);
    if (res && !res.toJSON)
    {
        res.toJSON = () => ({
            "__type": "ServerResponse",
            "statusCode": res.statusCode,
            "headersSent": res.headersSent
        });
    }
    outHttpResData.set(res);

    if (req.method === "POST")
    {
        let body = "";
        req.on("data", (chunk) => { body += chunk; });
        req.on("end", () =>
        {
            let data = body;
            try { data = JSON.parse(body); } catch (e) {}

            const reqInfo = Object.assign({
                "method": req.method,
                "url": req.url,
                "pathname": pathname,
                "headers": req.headers,
                "body": data
            }, (data && typeof data === "object") ? data : {});

            outHttpReqData.set(reqInfo);
            outHttpRequest.trigger();

            setTimeout(() =>
            {
                if (!res.headersSent)
                {
                    res.statusCode = 200;
                    res.setHeader("Content-Type", "application/json");
                    res.end(JSON.stringify({ "status": "received", "path": pathname }));
                }
            }, 1000);
        });
    }
    else
    {
        let queryParams = {};
        try
        {
            const parsedUrl = url.parse(req.url, true);
            queryParams = parsedUrl.query || {};
        }
        catch (e) {}

        const reqInfo = Object.assign({
            "method": req.method,
            "url": req.url,
            "pathname": pathname,
            "headers": req.headers,
            "query": queryParams
        }, queryParams);

        outHttpReqData.set(reqInfo);
        outHttpRequest.trigger();

        setTimeout(() =>
        {
            if (!res.headersSent)
            {
                res.statusCode = 200;
                res.setHeader("Content-Type", "application/json");
                res.end(JSON.stringify({ "status": "ok", "path": pathname }));
            }
        }, 1000);
    }
}

function setupSse(req, res, route)
{
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("Access-Control-Allow-Origin", "*");

    if (res.flushHeaders) res.flushHeaders();

    if (!sseClientsByRoute.has(route)) sseClientsByRoute.set(route, new Set());
    const clients = sseClientsByRoute.get(route);

    const client = { "res": res };
    clients.add(client);
    outSseActiveClients.set(getTotalSseClients());

    const heartbeat = setInterval(() =>
    {
        try
        {
            if (!res.writableEnded)
            {
                res.write(": heartbeat\n\n");
            }
            else
            {
                clearInterval(heartbeat);
            }
        }
        catch (e)
        {
            clearInterval(heartbeat);
        }
    }, 15000);

    req.on("close", () =>
    {
        clearInterval(heartbeat);
        clients.delete(client);
        if (clients.size === 0) sseClientsByRoute.delete(route);
        outSseActiveClients.set(getTotalSseClients());
    });
}

function getTotalSseClients()
{
    let count = 0;
    sseClientsByRoute.forEach((clients) => { count += clients.size; });
    return count;
}

inSseBroadcast.onTriggered = () =>
{
    const route = inSseRoute.get();
    const clients = sseClientsByRoute.get(route);
    if (!clients || clients.size === 0) return;

    const eventName = inSseEvent.get();
    const data = inSseData.get();

    const payload = {
        "route": route,
        "eventName": eventName,
        "data": data
    };

    let message = "";
    if (eventName) message += `event: ${eventName}\n`;
    message += `data: ${JSON.stringify(payload)}\n\n`;

    clients.forEach((client) =>
    {
        try
        {
            if (!client.res.writableEnded)
            {
                client.res.write(message);
            }
            else
            {
                clients.delete(client);
                outSseActiveClients.set(getTotalSseClients());
            }
        }
        catch (e)
        {
            clients.delete(client);
            outSseActiveClients.set(getTotalSseClients());
        }
    });
};

function stop()
{
    if (wss)
    {
        try { wss.close(); } catch (e) {}
        wss = null;
    }
    if (broker)
    {
        broker.clear();
        broker = null;
    }
    outWsActiveClients.set(0);

    if (server)
    {
        server.wss = null;
        server.broker = null;
        server.pubsub = null;
        server.close();
        server = null;
        outServerInstance.set(null);
        outStopped.trigger();
    }

    sseClientsByRoute.forEach((clients) =>
    {
        clients.forEach((client) =>
        {
            try { client.res.end(); } catch (e) {}
        });
    });
    sseClientsByRoute.clear();
    outSseActiveClients.set(0);

    outRunning.set(false);
}

inStart.onTriggered = start;
inStop.onTriggered = stop;

function restart()
{
    if (outRunning.get())
    {
        stop();
        start();
    }
}

setTimeout(() =>
{
    if (inAutoStart.get()) start();
}, 0);
