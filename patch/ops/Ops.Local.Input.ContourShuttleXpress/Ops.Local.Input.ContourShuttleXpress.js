/**
 * Ops.Local.Input.ContourShuttleXpress
 * Interfaces natively with Contour ShuttleXpress controller.
 */
const
    inActive = op.inBool("Active", false),

    outEvent = op.outTrigger("On Event"),
    outStatus = op.outString("Status", "Stopped"),
    outRunning = op.outBool("Running", false),

    outJogValue = op.outNumber("Jog Value", 0),
    outJogDelta = op.outNumber("Jog Delta", 0),
    outJogTurned = op.outTrigger("Jog Turned"),

    outShuttleValue = op.outNumber("Shuttle Value", 0),
    outShuttleMoved = op.outTrigger("Shuttle Moved"),

    outButtonIndex = op.outNumber("Button Index", -1),
    outButtonPressed = op.outBool("Button Pressed", false),
    outButtonEvent = op.outTrigger("Button Event");

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

function handleIpcEvent(_event, jsonStr) {
    if (!jsonStr) return;
    try {
        const msg = (typeof jsonStr === "string") ? JSON.parse(jsonStr) : jsonStr;
        if (msg.type === "info") {
            if (msg.status === "connected") {
                outStatus.set("Connected: " + msg.device);
            } else if (msg.status === "searching") {
                outStatus.set("Searching...");
            }
        } else if (msg.type === "shuttle") {
            outShuttleValue.set(msg.value);
            outShuttleMoved.trigger();
            outEvent.trigger();
        } else if (msg.type === "jog") {
            outJogDelta.set(msg.delta);
            outJogValue.set(msg.value);
            outJogTurned.trigger();
            outEvent.trigger();
        } else if (msg.type === "button") {
            outButtonIndex.set(msg.index);
            outButtonPressed.set(msg.pressed);
            outButtonEvent.trigger();
            outEvent.trigger();
        }
    } catch (e) {
        op.logWarn("[ContourShuttleXpress] Event error: " + e.message);
    }
}

function start() {
    if (active) stop();
    if (!inActive.get() || !ipcRenderer) return;

    outStatus.set("Starting...");
    ipcRenderer.on("shuttleXpressEvent", handleIpcEvent);

    ipcRenderer.invoke("shuttleXpressStart")
        .then((success) => {
            if (success) {
                active = true;
                outRunning.set(true);
                ipcRenderer.invoke("shuttleXpressIsConnected").then(connected => {
                    outStatus.set(connected ? "Connected" : "Searching...");
                });
            } else {
                active = false;
                outStatus.set("Start Failed");
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
    outRunning.set(false);
    outStatus.set("Stopped");

    if (ipcRenderer) {
        ipcRenderer.removeListener("shuttleXpressEvent", handleIpcEvent);
        ipcRenderer.invoke("shuttleXpressStop").catch(() => {});
    }
}

inActive.onChange = () => {
    if (inActive.get()) start();
    else stop();
};

op.onDelete = stop;

outStatus.set("Stopped");
if (inActive.get()) start();
