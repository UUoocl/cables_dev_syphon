const
    inExec = op.inTrigger("Update"),
    inRefresh = op.inTriggerButton("Refresh Servers"),
    inServer = op.inSwitch("Server", ["None"], "None"),
    
    outNext = op.outTrigger("Next"),
    outTexture = op.outTexture("Texture"),
    outWidth = op.outNumber("Width"),
    outHeight = op.outNumber("Height");

const cgl = op.patch.cgl;
const emptyTexture = CGL.Texture.getEmptyTexture(cgl);
outTexture.setRef(emptyTexture);

let ipcRenderer = null;
let sharedTexture = null;
let serversList = [];
let latestImportedTexture = null;
let needsUpdate = false;
let tex = null;

const logToMain = (msg) => {
    if (ipcRenderer) {
        ipcRenderer.send("renderer-log", msg);
    } else if (window.parent && window.parent.ipcRenderer) {
        window.parent.ipcRenderer.send("renderer-log", msg);
    } else {
        console.log(msg);
    }
};

// Initialize Electron integration
let electron = null;
let methodUsed = "none";
try {
    if (typeof op.require === "function") {
        electron = op.require("electron");
        methodUsed = "op.require";
    }
} catch (e) {}

if (!electron && window.parent && window.parent.nodeRequire) {
    try {
        electron = window.parent.nodeRequire("electron");
        methodUsed = "window.parent.nodeRequire";
    } catch (e) {}
}

if (!electron && window.nodeRequire) {
    try {
        electron = window.nodeRequire("electron");
        methodUsed = "window.nodeRequire";
    } catch (e) {}
}

if (electron) {
    try {
        ipcRenderer = electron.ipcRenderer;
        sharedTexture = electron.sharedTexture;
        
        if (sharedTexture && sharedTexture.setSharedTextureReceiver) {
            sharedTexture.setSharedTextureReceiver((options) => {
                if (!options || !options.importedSharedTexture) return;
                
                const importedTexture = options.importedSharedTexture;
                
                if (latestImportedTexture) {
                    if (latestImportedTexture.release) {
                        latestImportedTexture.release();
                    } else if (latestImportedTexture.subtle && latestImportedTexture.subtle.release) {
                        latestImportedTexture.subtle.release();
                    }
                }
                latestImportedTexture = importedTexture;
                needsUpdate = true;
            });
        }
    } catch (e) {
        logToMain("[SyphonInput Op] Failed to initialize Electron Syphon client: " + e.message);
    }
} else {
    console.warn("Electron modules not found in Op iframe context");
}

function updateServersList() {
    if (!ipcRenderer) return;
    
    ipcRenderer.invoke("syphonGetServers").then((servers) => {
        serversList = servers || [];
        const names = ["None"];
        serversList.forEach((s) => {
            const name = s.SyphonServerDescriptionNameKey || s.SyphonServerDescriptionName || s.SyphonServerDescriptionAppNameKey || s.SyphonServerDescriptionAppName || "Unknown Server";
            names.push(name);
        });
        inServer.setUiAttribs({ "values": names });
        
        // Re-trigger current subscription if still valid
        const currentVal = inServer.get();
        if (currentVal && currentVal !== "None") {
            inServer.set("None");
            inServer.set(currentVal);
        }
    }).catch((e) => {
        op.logError("Failed to fetch Syphon servers:", e);
    });
}

inRefresh.onTriggered = () => {
    updateServersList();
};

inServer.onChange = () => {
    if (!ipcRenderer) return;
    
    const selected = inServer.get();
    if (!selected || selected === "None") {
        ipcRenderer.invoke("syphonUnsubscribe");
        return;
    }
    
    const trySubscribe = () => {
        const desc = serversList.find((s) => {
            const name = s.SyphonServerDescriptionNameKey || s.SyphonServerDescriptionName || s.SyphonServerDescriptionAppNameKey || s.SyphonServerDescriptionAppName || "Unknown Server";
            return name === selected;
        });
        
        if (desc) {
            ipcRenderer.invoke("syphonSubscribe", desc).then((success) => {
                if (!success) {
                    op.logWarn("Failed to subscribe to Syphon server:", selected);
                }
            });
        }
    };
    
    if (serversList.length === 0) {
        ipcRenderer.invoke("syphonGetServers").then((servers) => {
            serversList = servers || [];
            trySubscribe();
        });
    } else {
        trySubscribe();
    }
};

inExec.onTriggered = () => {
    if (needsUpdate && latestImportedTexture) {
        try {
            const videoFrame = latestImportedTexture.subtle && typeof latestImportedTexture.subtle.getVideoFrame === "function"
                ? latestImportedTexture.subtle.getVideoFrame()
                : (typeof latestImportedTexture.getVideoFrame === "function" ? latestImportedTexture.getVideoFrame() : null);
            if (videoFrame) {
                if (!tex) {
                    tex = new CGL.Texture(cgl, {
                        "filter": CGL.Texture.FILTER_LINEAR,
                        "wrap": CGL.Texture.WRAP_CLAMP_TO_EDGE
                    });
                }
                
                if (tex.width !== videoFrame.displayWidth || tex.height !== videoFrame.displayHeight) {
                    tex.setSize(videoFrame.displayWidth, videoFrame.displayHeight);
                }
                
                cgl.gl.bindTexture(cgl.gl.TEXTURE_2D, tex.tex);
                cgl.gl.texImage2D(cgl.gl.TEXTURE_2D, 0, cgl.gl.RGBA, cgl.gl.RGBA, cgl.gl.UNSIGNED_BYTE, videoFrame);
                
                outWidth.set(videoFrame.displayWidth);
                outHeight.set(videoFrame.displayHeight);
                outTexture.setRef(tex);
                
                videoFrame.close();
                needsUpdate = false;
            }
        } catch (e) {
            op.logError("Error rendering shared texture frame:", e);
        }
    }
    
    outNext.trigger();
};

// Initial load
setTimeout(updateServersList, 1000);

op.onDelete = () => {
    if (ipcRenderer) {
        ipcRenderer.invoke("syphonUnsubscribe");
    }
    if (latestImportedTexture) {
        if (latestImportedTexture.release) {
            latestImportedTexture.release();
        } else if (latestImportedTexture.subtle && latestImportedTexture.subtle.release) {
            latestImportedTexture.subtle.release();
        }
    }
    if (tex) {
        tex.delete();
    }
};
