const
    inExec = op.inTrigger("Update"),
    inTexture = op.inTexture("Texture"),
    inServerName = op.inString("Server Name", "Cables Output"),
    
    outNext = op.outTrigger("Next"),
    outSuccess = op.outBool("Success", false);

const cgl = op.patch.cgl;

let ipcRenderer = null;
let fb = null;
let pixels = null;
let currentServerName = "";
let serverInitialized = false;

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

inServerName.onChange = updateServer;

async function updateServer() {
    if (!ipcRenderer) return;
    
    const name = inServerName.get() || "Cables Output";
    if (name !== currentServerName || !serverInitialized) {
        currentServerName = name;
        serverInitialized = await ipcRenderer.invoke("syphonPublishStart", name);
        outSuccess.set(serverInitialized);
    }
}

inExec.onTriggered = () => {
    const texture = inTexture.get();
    if (texture && serverInitialized && ipcRenderer) {
        try {
            const gl = cgl.gl;
            const w = texture.width;
            const h = texture.height;
            
            if (w > 0 && h > 0) {
                if (!fb) {
                    fb = gl.createFramebuffer();
                }
                
                gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
                gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture.tex, 0);
                
                if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) === gl.FRAMEBUFFER_COMPLETE) {
                    const size = w * h * 4;
                    if (!pixels || pixels.length !== size) {
                        pixels = new Uint8Array(size);
                    }
                    
                    gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
                    
                    // Send to main process
                    ipcRenderer.send("syphonPublishFrame", pixels, w, h);
                }
                
                gl.bindFramebuffer(gl.FRAMEBUFFER, null);
            }
        } catch (e) {
            op.logError("Error publishing texture to Syphon:", e);
        }
    }
    
    outNext.trigger();
};

op.onDelete = () => {
    if (ipcRenderer) {
        ipcRenderer.invoke("syphonPublishStop");
    }
    if (fb && cgl && cgl.gl) {
        cgl.gl.deleteFramebuffer(fb);
        fb = null;
    }
};

// Auto-start server if name is already set
updateServer();
