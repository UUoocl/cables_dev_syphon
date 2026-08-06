const
    inRefresh = op.inTrigger("Refresh"),
    
    outTriggered = op.outTrigger("Triggered"),
    outServers = op.outArray("Servers"),
    outDescriptions = op.outArray("Server Descriptions");

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

function updateList() {
    if (!ipcRenderer) return;
    
    ipcRenderer.invoke("syphonGetServers").then((servers) => {
        const rawList = servers || [];
        const names = [];
        
        rawList.forEach((s) => {
            const name = s.SyphonServerDescriptionNameKey || s.SyphonServerDescriptionName || s.SyphonServerDescriptionAppNameKey || s.SyphonServerDescriptionAppName || "Unknown Server";
            names.push(name);
        });
        
        outServers.set(names);
        outDescriptions.set(rawList);
        outTriggered.trigger();
    }).catch((e) => {
        op.logError("Failed to fetch Syphon servers:", e);
    });
}

inRefresh.onTriggered = () => {
    updateList();
};

// Initial load
setTimeout(updateList, 1000);
