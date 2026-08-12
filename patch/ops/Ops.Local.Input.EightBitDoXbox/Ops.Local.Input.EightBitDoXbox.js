/**
 * Ops.Local.Input.EightBitDoXbox
 * Interfaces natively with 8BitDo Xbox Mode controller.
 */
const
    inActive = op.inBool("Active", false),
    
    inRumbleLeft = op.inValue("Rumble Left", 0.0),
    inRumbleRight = op.inValue("Rumble Right", 0.0),
    inRumbleLeftTrigger = op.inValue("Rumble Left Trigger", 0.0),
    inRumbleRightTrigger = op.inValue("Rumble Right Trigger", 0.0),
    inTriggerRumble = op.inTrigger("Trigger Rumble"),
    inSendOnChange = op.inBool("Send Rumble on Change", false),
    
    outTrigger = op.outTrigger("On Event"),
    outIsConnected = op.outBool("Is Connected", false),
    outStatus = op.outString("Status", "Stopped"),
    outButtonsPressed = op.outArray("Buttons Pressed", []),
    
    outLSX = op.outNumber("LS X"),
    outLSY = op.outNumber("LS Y"),
    outRSX = op.outNumber("RS X"),
    outRSY = op.outNumber("RS Y"),
    outLT = op.outNumber("LT"),
    outRT = op.outNumber("RT"),
    
    outA = op.outBool("A", false),
    outB = op.outBool("B", false),
    outX = op.outBool("X", false),
    outY = op.outBool("Y", false),
    outDpadUp = op.outBool("DPad Up", false),
    outDpadDown = op.outBool("DPad Down", false),
    outDpadLeft = op.outBool("DPad Left", false),
    outDpadRight = op.outBool("DPad Right", false),
    outLB = op.outBool("LB", false),
    outRB = op.outBool("RB", false),
    outLSClick = op.outBool("LS Click", false),
    outRSClick = op.outBool("RS Click", false),
    outMenu = op.outBool("Menu", false),
    outView = op.outBool("View", false),
    outGuide = op.outBool("Guide", false),
    outShare = op.outBool("Share", false);

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
        const event = (typeof jsonStr === "string") ? JSON.parse(jsonStr) : jsonStr;
        if (event.type === "info") {
            const isConnected = event.status === "connected";
            outIsConnected.set(isConnected);
            outStatus.set(isConnected ? "Connected" : "Searching...");
        } else if (event.type === "input") {
            outLSX.set(event.ls[0]);
            outLSY.set(event.ls[1]);
            outRSX.set(event.rs[0]);
            outRSY.set(event.rs[1]);
            outLT.set(event.lt);
            outRT.set(event.rt);
            
            const pressed = event.buttons || [];
            outButtonsPressed.set(pressed);
            
            outA.set(pressed.includes("A"));
            outB.set(pressed.includes("B"));
            outX.set(pressed.includes("X"));
            outY.set(pressed.includes("Y"));
            outDpadUp.set(pressed.includes("Dpad Up"));
            outDpadDown.set(pressed.includes("Dpad Down"));
            outDpadLeft.set(pressed.includes("Dpad Left"));
            outDpadRight.set(pressed.includes("Dpad Right"));
            outLB.set(pressed.includes("LB"));
            outRB.set(pressed.includes("RB"));
            outLSClick.set(pressed.includes("LS Click"));
            outRSClick.set(pressed.includes("RS Click"));
            outMenu.set(pressed.includes("Menu"));
            outView.set(pressed.includes("View"));
            outGuide.set(pressed.includes("Guide"));
            outShare.set(pressed.includes("Share"));
            
            outTrigger.trigger();
        }
    } catch (e) {
        op.logWarn("[EightBitDoXbox] Event error: " + e.message);
    }
}

function start() {
    if (active) stop();
    if (!inActive.get() || !ipcRenderer) return;

    outStatus.set("Starting...");
    ipcRenderer.on("xboxEvent", handleIpcEvent);

    ipcRenderer.invoke("xboxStart")
        .then((success) => {
            if (success) {
                active = true;
                ipcRenderer.invoke("xboxIsConnected").then(connected => {
                    outIsConnected.set(connected);
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
    outIsConnected.set(false);
    outStatus.set("Stopped");

    if (ipcRenderer) {
        ipcRenderer.removeListener("xboxEvent", handleIpcEvent);
        ipcRenderer.invoke("xboxStop").catch(() => {});
    }
}

function writeRumble() {
    if (!ipcRenderer || !active || !outIsConnected.get()) return;
    
    const left = parseFloat(inRumbleLeft.get()) || 0;
    const right = parseFloat(inRumbleRight.get()) || 0;
    const lt = parseFloat(inRumbleLeftTrigger.get()) || 0;
    const rt = parseFloat(inRumbleRightTrigger.get()) || 0;
    
    ipcRenderer.invoke("xboxSendRumble", left, right, lt, rt).catch(() => {});
}

inActive.onChange = () => {
    if (inActive.get()) start();
    else stop();
};

function onRumbleChange() {
    if (inSendOnChange.get()) {
        writeRumble();
    }
}

inRumbleLeft.onChange = onRumbleChange;
inRumbleRight.onChange = onRumbleChange;
inRumbleLeftTrigger.onChange = onRumbleChange;
inRumbleRightTrigger.onChange = onRumbleChange;

inTriggerRumble.onTriggered = writeRumble;

op.onDelete = stop;

outStatus.set("Stopped");
if (inActive.get()) start();
