/**
 * Ops.Local.Input.KeyboardController
 * Emits virtual keyboard keystrokes globally on macOS using direct native Node-API bindings.
 */
const
    inActive = op.inBool("Active", false),
    inEmit = op.inTrigger("Emit"),
    inKeystrokeObj = op.inObject("Keystroke Object"),
    
    outCombo = op.outString("Emitted Keystroke", ""),
    outTrigger = op.outTrigger("On Emitted"),
    
    outRunning = op.outBool("Running", false),
    outStatus = op.outString("Status", "Stopped");

let ipcRenderer = null;

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

inEmit.onTriggered = () => {
    if (!inActive.get() || !ipcRenderer) return;

    const obj = inKeystrokeObj.get();
    if (!obj) {
        op.logWarn("[KeyboardController] Cannot emit: Keystroke Object is null.");
        return;
    }

    const key = obj.key || obj.Key || "";
    if (!key || String(key).trim() === "") {
        op.logWarn("[KeyboardController] Cannot emit: 'key' property is empty or missing in Keystroke Object.");
        return;
    }

    let modifiers = obj.modifier || obj.modifiers || obj.Modifier || obj.Modifiers || "";
    if (typeof modifiers === "string" && modifiers.toLowerCase() === "none") {
        modifiers = "";
    }

    ipcRenderer.invoke("emitKeyboardAction", {
        key: String(key),
        modifiers: String(modifiers)
    })
        .then((result) => {
            if (result && result.combo !== undefined) {
                outCombo.set(result.combo);
                outTrigger.trigger();
            }
        })
        .catch((e) => {
            op.logError("[KeyboardController] Error emitting keystroke: " + e.message);
            outStatus.set("Error: " + e.message);
        });
};

inActive.onChange = () => {
    if (inActive.get() && ipcRenderer) {
        outRunning.set(true);
        outStatus.set("Running");
    } else {
        outRunning.set(false);
        outStatus.set("Stopped");
    }
};

if (inActive.get() && ipcRenderer) {
    outRunning.set(true);
    outStatus.set("Running");
} else {
    outStatus.set("Stopped");
}
