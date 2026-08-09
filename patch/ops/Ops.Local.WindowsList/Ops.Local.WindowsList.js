const
    inRefresh = op.inTriggerButton("Refresh"),
    
    outWindows = op.outArray("Windows", null),
    outNames = op.outArray("Formatted Names", null),
    outPids = op.outArray("PIDs", null),
    outIds = op.outArray("Window IDs", null);

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
} else {
    console.warn("[WindowsList] Electron ipcRenderer not found");
}

function refreshWindowList() {
    if (!ipcRenderer) return;
    
    ipcRenderer.invoke("syphonGetWindowList").then((list) => {
        const windows = list || [];
        outWindows.set(windows);
        
        const names = [];
        const pids = [];
        const ids = [];
        
        windows.forEach((win) => {
            const formattedName = `${win.ownerName} - ${win.title || "Untitled Window"} (PID: ${win.pid}, ID: ${win.id})`;
            names.push(formattedName);
            pids.push(win.pid);
            ids.push(win.id);
        });
        
        outNames.set(names);
        outPids.set(pids);
        outIds.set(ids);
    }).catch((err) => {
        op.logError("[WindowsList] Failed to get window list:", err);
    });
}

inRefresh.onTriggered = () => {
    refreshWindowList();
};

// Initial load
setTimeout(refreshWindowList, 1000);
