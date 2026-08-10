/**
 * Ops.Local.Input.MouseMonitor
 * Streams high-frequency real-time global mouse telemetry (position, clicks, scrolls) directly using native macOS Node-API bindings.
 */
const
    inActive = op.inBool("Active", false),
    inPps = op.inInt("PPS Limit", 20),

    outTriggerMove = op.outTrigger("On Move"),
    outTriggerClick = op.outTrigger("On Click"),
    outTriggerScroll = op.outTrigger("On Scroll"),
    outPosX = op.outNumber("Pos X", 0),
    outPosY = op.outNumber("Pos Y", 0),
    outButton = op.outNumber("Button", 0),
    outIsDown = op.outBool("Button Is Down", false),
    outIsUp = op.outBool("Button Is Up", false),
    outScrollDeltaX = op.outNumber("Scroll Delta X", 0),
    outScrollDeltaY = op.outNumber("Scroll Delta Y", 0),

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

function handleMouseEvent(_event, msg) {
    if (!msg || !msg.type) return;

    if (msg.type === "mousePosition") {
        outPosX.set(msg.data.x);
        outPosY.set(msg.data.y);
        outTriggerMove.trigger();
    } else if (msg.type === "mouseClick") {
        outPosX.set(msg.data.x);
        outPosY.set(msg.data.y);
        const buttonNum = msg.data.button ? parseInt(msg.data.button.substring(2), 10) : 0;
        outButton.set(buttonNum);
        outIsDown.set(msg.data.pressed);
        outIsUp.set(!msg.data.pressed);
        outTriggerClick.trigger();
    } else if (msg.type === "mouseScroll") {
        outPosX.set(msg.data.x);
        outPosY.set(msg.data.y);
        outScrollDeltaX.set(msg.data.dx);
        outScrollDeltaY.set(msg.data.dy);
        outTriggerScroll.trigger();
    }
}

function start() {
    if (active) stop();
    if (!inActive.get() || !ipcRenderer) return;

    const pps = inPps.get() || 20;
    outStatus.set("Starting...");
    
    ipcRenderer.invoke("startMouseMonitor", pps)
        .then((success) => {
            if (success) {
                active = true;
                outRunning.set(true);
                outStatus.set("Running");
                ipcRenderer.on("mouseEvent", handleMouseEvent);
            } else {
                active = false;
                outRunning.set(false);
                outStatus.set("Failed (Accessibility?)");
            }
        })
        .catch((err) => {
            op.logError("[MouseMonitor] Failed to start native monitor: " + err.message);
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
        ipcRenderer.removeListener("mouseEvent", handleMouseEvent);
        ipcRenderer.invoke("stopMouseMonitor")
            .then(() => {
                outStatus.set("Stopped");
            })
            .catch((err) => {
                op.logError("[MouseMonitor] Error during stop: " + err.message);
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

inPps.onChange = () => {
    if (inActive.get() && active) {
        start();
    }
};

op.onDelete = () => {
    stop();
};

// Initialize status
outStatus.set("Stopped");
outButton.set(0);
outIsDown.set(false);
outIsUp.set(false);
