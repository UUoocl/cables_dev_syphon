/**
 * Ops.Local.Input.SoomfonController
 * Interfaces natively with Soomfon dials/keys controller.
 */
const
    inActive = op.inBool("Active", false),
    
    outConnection = op.outObject("Connection"),
    outIsConnected = op.outBool("Is Connected", false),
    outStatus = op.outString("Status", "Stopped"),
    outDeviceInfo = op.outObject("Device Info"),
    
    outKeyEvent = op.outTrigger("Key Event"),
    outEventKeyIndex = op.outNumber("Event Key Index", 0),
    outEventPressed = op.outBool("Event Pressed", false),

    outKnobEvent = op.outTrigger("Knob Event"),
    outEventKnobIndex = op.outNumber("Event Knob Index", 0),
    outEventKnobDirection = op.outNumber("Event Knob Direction", 0),
    outKnob0Value = op.outNumber("Knob 0 Value", 0),
    outKnob1Value = op.outNumber("Knob 1 Value", 0),
    outKnob2Value = op.outNumber("Knob 2 Value", 0),

    outKnobClickEvent = op.outTrigger("Knob Click Event"),
    outEventKnobClickIndex = op.outNumber("Event Knob Click Index", 0),
    outEventKnobClickPressed = op.outBool("Event Knob Click Pressed", false);

let ipcRenderer = null;
let active = false;

let knob0Val = 0;
let knob1Val = 0;
let knob2Val = 0;

outConnection.set(null);
outDeviceInfo.set(null);
resetKnobValues();

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

function resetKnobValues() {
    knob0Val = 0;
    knob1Val = 0;
    knob2Val = 0;
    outKnob0Value.set(0);
    outKnob1Value.set(0);
    outKnob2Value.set(0);
}

const connection = {
    key_width: 60,
    key_height: 60,
    cols: 3,
    rows: 2,
    send(action, params) {
        if (!ipcRenderer || !active) return;
        try {
            if (action === "set_key_image") {
                ipcRenderer.invoke("soomfonSetKeyImage", params.key, params.image);
            } else if (action === "set_stretched_image") {
                ipcRenderer.invoke("soomfonSetStretchedImage", params.image);
            }
        } catch (e) {
            op.logError("[SoomfonController] Write failed: " + e.message);
        }
    }
};

function handleIpcEvent(_event, jsonStr) {
    if (!jsonStr) return;
    try {
        const msg = (typeof jsonStr === "string") ? JSON.parse(jsonStr) : jsonStr;
        if (msg.type === "connected") {
            outIsConnected.set(true);
            outDeviceInfo.set(msg);
            outConnection.set(connection);
            outStatus.set("Connected");
        } else if (msg.type === "key_event") {
            outEventKeyIndex.set(msg.key);
            outEventPressed.set(msg.pressed);
            outKeyEvent.trigger();
        } else if (msg.type === "knob_turn") {
            outEventKnobIndex.set(msg.knob);
            outEventKnobDirection.set(msg.direction);
            if (msg.knob === 0) {
                knob0Val += msg.direction;
                outKnob0Value.set(knob0Val);
            } else if (msg.knob === 1) {
                knob1Val += msg.direction;
                outKnob1Value.set(knob1Val);
            } else if (msg.knob === 2) {
                knob2Val += msg.direction;
                outKnob2Value.set(knob2Val);
            }
            outKnobEvent.trigger();
        } else if (msg.type === "knob_click") {
            outEventKnobClickIndex.set(msg.knob);
            outEventKnobClickPressed.set(msg.pressed);
            outKnobClickEvent.trigger();
        } else if (msg.type === "error") {
            outStatus.set("Error: " + msg.message);
            outIsConnected.set(false);
            outConnection.set(null);
        } else if (msg.type === "disconnected") {
            outIsConnected.set(false);
            outConnection.set(null);
            outDeviceInfo.set(null);
            outStatus.set("Disconnected");
        }
    } catch (e) {
        op.logWarn("[SoomfonController] Event error: " + e.message);
    }
}

function start() {
    if (active) stop();
    if (!inActive.get() || !ipcRenderer) return;

    outStatus.set("Connecting...");
    resetKnobValues();
    ipcRenderer.on("soomfonEvent", handleIpcEvent);

    ipcRenderer.invoke("soomfonStart", 0)
        .then((success) => {
            if (success) {
                active = true;
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
    outIsConnected.set(false);
    outConnection.set(null);
    outDeviceInfo.set(null);
    outStatus.set("Stopped");

    if (ipcRenderer) {
        ipcRenderer.removeListener("soomfonEvent", handleIpcEvent);
        ipcRenderer.invoke("soomfonStop").catch(() => {});
    }
}

inActive.onChange = () => {
    if (inActive.get()) start();
    else stop();
};

op.onDelete = stop;

outStatus.set("Stopped");
if (inActive.get()) start();
