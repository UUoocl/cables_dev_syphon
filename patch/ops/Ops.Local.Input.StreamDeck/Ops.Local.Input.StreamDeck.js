/**
 * Ops.Local.Input.StreamDeck
 * Interfaces natively with Elgato Stream Decks.
 */
const
    inActive = op.inBool("Active", false),
    inDeviceIdx = op.inInt("Device Index", 0),
    
    outConnection = op.outObject("Connection"),
    outIsConnected = op.outBool("Is Connected", false),
    outStatus = op.outString("Status", "Stopped"),
    outDeviceInfo = op.outObject("Device Info"),
    
    outKeyEvent = op.outTrigger("Key Event"),
    outEventKeyIndex = op.outNumber("Event Key Index", 0),
    outEventPressed = op.outBool("Event Pressed", false);

op.setPortGroup("Controls", [inActive]);
op.setPortGroup("Settings", [inDeviceIdx]);

let ipcRenderer = null;
let active = false;
let currentDevice = null;

outConnection.set(null);
outDeviceInfo.set(null);

// Initialize Electron integration
let electron = null;
try {
    if (typeof op.require === "function") {
        electron = op.require("electron");
    }
} catch (e) {}

if (!electron && window.parent && window.parent.nodeRequire) {
    try {
        electron = window.parent.nodeRequire("electron");
    } catch (e) {}
}

if (!electron && window.nodeRequire) {
    try {
        electron = window.nodeRequire("electron");
    } catch (e) {}
}

if (electron) {
    ipcRenderer = electron.ipcRenderer;
}

const connection = {
    key_width: 72,
    key_height: 72,
    cols: 5,
    rows: 3,
    send(action, params) {
        if (!ipcRenderer || !active || !outIsConnected.get()) return;
        try {
            if (action === "set_key_image") {
                ipcRenderer.invoke("streamDeckSetKeyImage", params.key, params.image);
            } else if (action === "set_stretched_image") {
                ipcRenderer.invoke("streamDeckSetStretchedImage", params.image);
            }
        } catch (e) {
            op.logError("[StreamDeck] Write failed: " + e.message);
        }
    }
};

function handleIpcEvent(_event, msg) {
    if (!msg) return;
    try {
        // Stream Deck native callbacks deliver structured JS objects
        if (msg.key !== undefined) {
            outEventKeyIndex.set(msg.key);
            outEventPressed.set(!!msg.pressed);
            outKeyEvent.trigger();
        }
    } catch (e) {
        op.logWarn("[StreamDeck] Event error: " + e.message);
    }
}

function refreshConnection() {
    if (!ipcRenderer || !active) return;
    
    ipcRenderer.invoke("streamDeckEnumerateDevices")
        .then((devices) => {
            const idx = inDeviceIdx.get() || 0;
            if (devices && devices.length > idx) {
                const dev = devices[idx];
                currentDevice = dev;
                
                ipcRenderer.invoke("streamDeckConnect", idx)
                    .then((connected) => {
                        if (connected) {
                            connection.key_width = dev.iconSize || 72;
                            connection.key_height = dev.iconSize || 72;
                            connection.cols = dev.cols || 5;
                            connection.rows = dev.rows || 3;
                            
                            outDeviceInfo.set(dev);
                            outConnection.set(connection);
                            outIsConnected.set(true);
                            outStatus.set("Connected to " + dev.name);
                        } else {
                            outIsConnected.set(false);
                            outConnection.set(null);
                            outDeviceInfo.set(null);
                            outStatus.set("Connection Failed");
                        }
                    });
            } else {
                outIsConnected.set(false);
                outConnection.set(null);
                outDeviceInfo.set(null);
                outStatus.set("No device found at index " + idx);
            }
        })
        .catch((err) => {
            op.logError("[StreamDeck] Enumeration failed: " + err.message);
        });
}

function start() {
    if (active) stop();
    if (!inActive.get() || !ipcRenderer) return;

    outStatus.set("Searching...");
    ipcRenderer.on("streamDeckEvent", handleIpcEvent);

    ipcRenderer.invoke("streamDeckInit")
        .then((success) => {
            if (success) {
                active = true;
                refreshConnection();
            } else {
                active = false;
                outStatus.set("Init Failed");
            }
        })
        .catch((err) => {
            active = false;
            outStatus.set("Error: " + err.message);
        });
}

function stop() {
    if (!active) return;
    active = false;
    outIsConnected.set(false);
    outConnection.set(null);
    outDeviceInfo.set(null);
    outStatus.set("Stopped");

    if (ipcRenderer) {
        ipcRenderer.removeListener("streamDeckEvent", handleIpcEvent);
        ipcRenderer.invoke("streamDeckDisconnect").catch(() => {});
        ipcRenderer.invoke("streamDeckStop").catch(() => {});
    }
}

inActive.onChange = () => {
    if (inActive.get()) start();
    else stop();
};

inDeviceIdx.onChange = () => {
    if (active) refreshConnection();
};

op.onDelete = stop;

outStatus.set("Stopped");
if (inActive.get()) start();
