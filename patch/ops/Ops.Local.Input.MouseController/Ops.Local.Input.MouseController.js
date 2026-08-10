/**
 * Ops.Local.Input.MouseController
 * Controls mouse cursor position, emits virtual button clicks/drags, and scrolls globally on macOS using direct native Node-API bindings.
 */
const
    inActive = op.inBool("Active", false),
    inEmit = op.inTrigger("Emit"),
    inMouseObj = op.inObject("Mouse Object"),
    
    outEmitted = op.outObject("Emitted Mouse"),
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

    const obj = inMouseObj.get();
    if (!obj) {
        op.logWarn("[MouseController] Cannot emit: Mouse Object is null.");
        return;
    }

    const payload = {};
    if (obj.x !== undefined && obj.x !== null) payload.x = Number(obj.x);
    if (obj.y !== undefined && obj.y !== null) payload.y = Number(obj.y);
    if (obj.button !== undefined && obj.button !== null) payload.button = String(obj.button).toLowerCase();
    if (obj.action !== undefined && obj.action !== null) payload.action = String(obj.action).toLowerCase();
    if (obj.scrollX !== undefined && obj.scrollX !== null) payload.scrollX = Number(obj.scrollX);
    if (obj.scrollY !== undefined && obj.scrollY !== null) payload.scrollY = Number(obj.scrollY);

    if (payload.action === "click") {
        const downPayload = Object.assign({}, payload, { action: "down" });
        ipcRenderer.invoke("emitMouseAction", downPayload)
            .then((resultDown) => {
                setTimeout(() => {
                    const upPayload = Object.assign({}, payload, { action: "up" });
                    ipcRenderer.invoke("emitMouseAction", upPayload)
                        .then((resultUp) => {
                            const emitted = Object.assign({}, resultUp, { action: "click" });
                            outEmitted.set(emitted);
                            outTrigger.trigger();
                        })
                        .catch((errUp) => {
                            op.logError("[MouseController] Error during click up release: " + errUp.message);
                        });
                }, 10);
            })
            .catch((errDown) => {
                op.logError("[MouseController] Error during click down press: " + errDown.message);
            });
    } else {
        ipcRenderer.invoke("emitMouseAction", payload)
            .then((result) => {
                outEmitted.set(result || {});
                outTrigger.trigger();
            })
            .catch((e) => {
                op.logError("[MouseController] Error emitting event: " + e.message);
                outStatus.set("Error: " + e.message);
            });
    }
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
