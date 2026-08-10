/**
 * Ops.Local.Input.KeyboardMonitor
 * Streams high-frequency real-time global keyboard events and hotkey combinations directly using native macOS Node-API bindings.
 */
const
    inActive = op.inBool("Active", false),

    outPress = op.outTrigger("On Press"),
    outRelease = op.outTrigger("On Release"),
    outCombo = op.outString("Combo", ""),
    outKey = op.outString("Key", ""),
    outModifiers = op.outString("Modifiers", ""),

    outRunning = op.outBool("Running", false),
    outStatus = op.outString("Status", "Stopped");

let ipcRenderer = null;
let active = false;

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

function handleKeyboardEvent(_event, msg) {
    if (!msg || !msg.event) return;

    outCombo.set("");
    outKey.set("");
    outModifiers.set("");

    outCombo.set(msg.combo || "");
    outKey.set(msg.key || "");
    outModifiers.set(msg.modifiers || "");

    if (msg.event === "press") {
        outPress.trigger();
    } else if (msg.event === "release") {
        outRelease.trigger();
    }
}

function start() {
    if (active) stop();
    if (!inActive.get() || !ipcRenderer) return;

    outStatus.set("Starting...");
    
    ipcRenderer.invoke("startKeyboardMonitor")
        .then((success) => {
            if (success) {
                active = true;
                outRunning.set(true);
                outStatus.set("Running");
                ipcRenderer.on("keyboardEvent", handleKeyboardEvent);
            } else {
                active = false;
                outRunning.set(false);
                outStatus.set("Failed (Accessibility?)");
            }
        })
        .catch((err) => {
            op.logError("[KeyboardMonitor] Failed to start native monitor: " + err.message);
            outRunning.set(false);
            outStatus.set("Error: " + err.message);
        });
}

function stop() {
    if (!active) return;
    active = false;
    outRunning.set(false);
    outStatus.set("Stopping...");
    
    if (ipcRenderer) {
        ipcRenderer.removeListener("keyboardEvent", handleKeyboardEvent);
        ipcRenderer.invoke("stopKeyboardMonitor")
            .then(() => {
                outStatus.set("Stopped");
            })
            .catch((err) => {
                op.logError("[KeyboardMonitor] Error during stop: " + err.message);
                outStatus.set("Error stopping");
            });
    } else {
        outStatus.set("Stopped");
    }
}

inActive.onChange = () => {
    if (inActive.get()) {
        start();
    } else {
        stop();
    }
};

op.onDelete = () => {
    stop();
};

// Initialize status
outStatus.set("Stopped");
