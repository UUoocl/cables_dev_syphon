/**
 * Ops.Local.ActiveApp.ActiveApp
 * Monitors the frontmost active application and window title on macOS using direct native Node-API bindings.
 */
const
    inActive = op.inBool("Active", true),
    inInterval = op.inValueInt("Interval (ms)", 500),
    
    outAppName = op.outString("Application Name", ""),
    outBundleId = op.outString("Bundle Identifier", ""),
    outPid = op.outNumber("Process ID", 0),
    outWindowTitle = op.outString("Window Title", ""),
    outChanged = op.outTrigger("On Changed"),
    
    outRunning = op.outBool("Running", false),
    outStatus = op.outString("Status", "Stopped");

inInterval.setUiAttribs({
    "min": 100,
    "max": 10000,
    "step": 50
});

let ipcRenderer = null;
let intervalId = null;
let lastPID = 0;
let lastTitle = "";

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

function startPolling() {
    stopPolling();
    if (!inActive.get() || !ipcRenderer) return;
    
    outRunning.set(true);
    outStatus.set("Polling");
    
    const intervalVal = parseInt(inInterval.get()) || 500;
    intervalId = setInterval(checkActiveApp, intervalVal);
}

function stopPolling() {
    if (intervalId) {
        clearInterval(intervalId);
        intervalId = null;
    }
    outRunning.set(false);
    outStatus.set("Stopped");
}

function checkActiveApp() {
    if (!ipcRenderer) return;
    ipcRenderer.invoke("getActiveApp")
        .then((info) => {
            if (!info) return;
            
            const pid = info.pid || 0;
            const windowTitle = info.windowTitle || "";
            
            if (pid !== lastPID || windowTitle !== lastTitle) {
                lastPID = pid;
                lastTitle = windowTitle;
                
                outAppName.set(info.name || "");
                outBundleId.set(info.bundleId || "");
                outPid.set(pid);
                outWindowTitle.set(windowTitle);
                outChanged.trigger();
            }
        })
        .catch((e) => {
            op.logError("[ActiveApp] Error polling active app: " + String(e.message));
        });
}

inActive.onChange = () => {
    if (inActive.get()) {
        startPolling();
    } else {
        stopPolling();
    }
};

inInterval.onChange = () => {
    if (inActive.get()) {
        startPolling();
    }
};

op.onDelete = () => {
    stopPolling();
};

// Start monitoring automatically on init if active
if (inActive.get()) {
    startPolling();
}
