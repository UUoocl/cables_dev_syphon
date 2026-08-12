/**
 * Ops.Local.Input.BmdSpeedEditor
 * Interfaces natively with Blackmagic Design DaVinci Resolve Speed Editor controller.
 */
const
    inActive = op.inBool("Active", false),
    inLedsObj = op.inObject("LEDs State"),
    inButtonLeds = op.inInt("Button LEDs", 0),
    inJogLeds = op.inInt("Jog LEDs", 0),
    inJogMode = op.inInt("Jog Mode", 0),

    outEvent = op.outTrigger("On Event"),
    outStatus = op.outString("Status", "Stopped"),
    outRunning = op.outBool("Running", false),
    outKeysPressed = op.outArray("Keys Pressed", []),
    outKeyNames = op.outArray("Key Names", []),
    outLastKey = op.outString("Last Key", ""),
    outLastKeyPressed = op.outBool("Last Key Pressed", false),
    outKeyEvent = op.outTrigger("Key Event"),
    outJogValue = op.outNumber("Jog Value", 0),
    outJogDelta = op.outNumber("Jog Delta", 0),
    outJogTurned = op.outTrigger("Jog Turned"),
    outBatteryLevel = op.outNumber("Battery Level", 0),
    outCharging = op.outBool("Charging", false);

let ipcRenderer = null;
let active = false;

const keyNames = {
    0x01: "SMART_INSERT",
    0x02: "APPEND",
    0x03: "RIPPLE_OVERWRITE",
    0x04: "CLOSE_UP",
    0x05: "PLACE_ON_TOP",
    0x06: "SOURCE_OVERWRITE",
    0x07: "IN",
    0x08: "OUT",
    0x09: "TRIM_IN",
    0x0a: "TRIM_OUT",
    0x0b: "ROLL",
    0x0c: "SLIP_SOURCE",
    0x0d: "SLIP_DEST",
    0x0e: "TRANS_DUR",
    0x0f: "CUT",
    0x10: "DIS",
    0x11: "SMOOTH_CUT",
    0x1a: "SOURCE",
    0x1b: "TIMELINE",
    0x1c: "SHTL",
    0x1d: "JOG",
    0x1e: "SCRL",
    0x1f: "SYNC_BIN",
    0x22: "TRANS",
    0x25: "VIDEO_ONLY",
    0x26: "AUDIO_ONLY",
    0x2b: "RIPPLE_DELETE",
    0x2c: "AUDIO_LEVEL",
    0x2d: "FULL_VIEW",
    0x2e: "SNAP",
    0x2f: "SPLIT",
    0x30: "LIVE_OVERWRITE",
    0x31: "ESC",
    0x33: "CAM1",
    0x34: "CAM2",
    0x35: "CAM3",
    0x36: "CAM4",
    0x37: "CAM5",
    0x38: "CAM6",
    0x39: "CAM7",
    0x3a: "CAM8",
    0x3b: "CAM9",
    0x3c: "STOP_PLAY"
};

const LED_MAP = {
    "CLOSE_UP": 1 << 0,
    "CUT": 1 << 1,
    "DIS": 1 << 2,
    "SMOOTH_CUT": 1 << 3,
    "TRANS": 1 << 4,
    "SNAP": 1 << 5,
    "CAM7": 1 << 6,
    "CAM8": 1 << 7,
    "CAM9": 1 << 8,
    "LIVE_OVERWRITE": 1 << 9,
    "CAM4": 1 << 10,
    "CAM5": 1 << 11,
    "CAM6": 1 << 12,
    "VIDEO_ONLY": 1 << 13,
    "CAM1": 1 << 14,
    "CAM2": 1 << 15,
    "CAM3": 1 << 16,
    "AUDIO_ONLY": 1 << 17
};

const JOG_LED_MAP = {
    "JOG": 1 << 0,
    "SHTL": 1 << 1,
    "SCRL": 1 << 2
};

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
                syncControls();
            } else if (msg.status === "searching") {
                outStatus.set("Searching...");
            }
        } else if (msg.type === "error") {
            outStatus.set("Error: " + msg.message);
        } else if (msg.type === "jog") {
            outJogDelta.set(msg.delta);
            outJogValue.set(msg.value);
            outJogTurned.trigger();
            outEvent.trigger();
        } else if (msg.type === "keys") {
            outKeysPressed.set(msg.codes);
            const names = (msg.codes || []).map(code => keyNames[code] || "UNKNOWN_" + code);
            outKeyNames.set(names);
            outEvent.trigger();
        } else if (msg.type === "key_event") {
            outLastKey.set(keyNames[msg.code] || "UNKNOWN_" + msg.code);
            outLastKeyPressed.set(msg.pressed);
            outKeyEvent.trigger();
            outEvent.trigger();
        } else if (msg.type === "battery") {
            outBatteryLevel.set(msg.level);
            outCharging.set(msg.charging);
            outEvent.trigger();
        }
    } catch (e) {
        op.logWarn("[BmdSpeedEditor] Event error: " + e.message);
    }
}

function start() {
    if (active) stop();
    if (!inActive.get() || !ipcRenderer) return;

    outStatus.set("Starting...");
    ipcRenderer.on("speedEditorEvent", handleIpcEvent);

    ipcRenderer.invoke("speedEditorStart")
        .then((success) => {
            if (success) {
                active = true;
                outRunning.set(true);
                ipcRenderer.invoke("speedEditorIsConnected").then(connected => {
                    outStatus.set(connected ? "Connected" : "Searching...");
                    if (connected) syncControls();
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
        ipcRenderer.removeListener("speedEditorEvent", handleIpcEvent);
        ipcRenderer.invoke("speedEditorStop").catch(() => {});
    }
}

function syncControls() {
    if (!ipcRenderer || !active) return;

    if (inLedsObj.get() && typeof inLedsObj.get() === "object") {
        updateLedsFromObject(inLedsObj.get());
    } else {
        ipcRenderer.invoke("speedEditorSetLeds", inButtonLeds.get() || 0);
        ipcRenderer.invoke("speedEditorSetJogLeds", inJogLeds.get() || 0);
    }
    ipcRenderer.invoke("speedEditorSetJogMode", inJogMode.get() || 0);
}

function updateLedsFromObject(obj) {
    if (!ipcRenderer || !active || !obj || typeof obj !== "object") return;

    let buttonBitfield = 0;
    let jogBitfield = 0;
    let hasButtonLed = false;
    let hasJogLed = false;

    for (const key in obj) {
        const val = obj[key];
        const ledActive = (val === 1 || val === true || val === "1");

        if (LED_MAP.hasOwnProperty(key)) {
            hasButtonLed = true;
            if (ledActive) buttonBitfield |= LED_MAP[key];
        } else if (JOG_LED_MAP.hasOwnProperty(key)) {
            hasJogLed = true;
            if (ledActive) jogBitfield |= JOG_LED_MAP[key];
        }
    }

    if (hasButtonLed) ipcRenderer.invoke("speedEditorSetLeds", buttonBitfield);
    if (hasJogLed) ipcRenderer.invoke("speedEditorSetJogLeds", jogBitfield);
}

inActive.onChange = () => {
    if (inActive.get()) start();
    else stop();
};

inLedsObj.onChange = () => {
    updateLedsFromObject(inLedsObj.get());
};

inButtonLeds.onChange = () => {
    if (ipcRenderer && active) {
        ipcRenderer.invoke("speedEditorSetLeds", inButtonLeds.get());
    }
};

inJogLeds.onChange = () => {
    if (ipcRenderer && active) {
        ipcRenderer.invoke("speedEditorSetJogLeds", inJogLeds.get());
    }
};

inJogMode.onChange = () => {
    if (ipcRenderer && active) {
        ipcRenderer.invoke("speedEditorSetJogMode", inJogMode.get());
    }
};

op.onDelete = stop;

outStatus.set("Stopped");
if (inActive.get()) start();
