/**
 * Ops.Local.Vision.HumanFace
 * Tracks 2D human facial landmarks, bounding boxes, and head orientation in real-time from an input WebGL texture using macOS Apple Vision.
 */
const
    render = op.inTrigger("Render"),
    inTexture = op.inTexture("Texture"),
    inActive = op.inBool("Active", true),
    
    outFaces = op.outArray("Faces Array"),
    outNumFaces = op.outNumber("Detected Faces"),
    outTrigger = op.outTrigger("On Faces Detected");

const cgl = op.patch.cgl;

let ipcRenderer = null;
let isProcessing = false;
let inputBuffer = null;

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

inActive.onChange = () => {
    if (!inActive.get()) {
        isProcessing = false;
    }
};

render.onTriggered = () => {
    if (!inActive.get() || !ipcRenderer) return;

    const tex = inTexture.get();
    if (!tex || !tex.tex) return;

    // Backpressure Control
    if (isProcessing) return;

    const width = tex.width;
    const height = tex.height;
    const gl = cgl.gl;

    // Downsample target calculations (384px max dimension for fast tracking)
    const maxDimension = 384;
    let targetW = width;
    let targetH = height;

    if (width > maxDimension || height > maxDimension) {
        if (width > height) {
            targetW = maxDimension;
            targetH = Math.round((height * maxDimension) / width);
        } else {
            targetH = maxDimension;
            targetW = Math.round((width * maxDimension) / height);
        }
    }

    // Setup downsample GPU texture and FBO
    if (!op._downsampleTex || op._downsampleTex.width !== targetW || op._downsampleTex.height !== targetH) {
        if (op._downsampleTex) op._downsampleTex.dispose();
        op._downsampleTex = new CGL.Texture(cgl, {
            width: targetW,
            height: targetH,
            filter: CGL.Texture.FILTER_LINEAR
        });
        inputBuffer = new Uint8Array(targetW * targetH * 4);
    }
    if (!op._downsampleFbo) op._downsampleFbo = gl.createFramebuffer();

    // Attach input texture to read framebuffer
    if (!op._fbo) op._fbo = gl.createFramebuffer();
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, op._fbo);
    gl.framebufferTexture2D(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex.tex, 0);

    // Attach downsample texture to draw framebuffer
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, op._downsampleFbo);
    gl.framebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, op._downsampleTex.tex, 0);

    // Perform Blit downsampling completely on the GPU
    gl.blitFramebuffer(
        0, 0, width, height,
        0, 0, targetW, targetH,
        gl.COLOR_BUFFER_BIT,
        gl.LINEAR
    );

    // Read downsampled pixels into CPU buffer
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, op._downsampleFbo);
    gl.readPixels(0, 0, targetW, targetH, gl.RGBA, gl.UNSIGNED_BYTE, inputBuffer);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);

    isProcessing = true;

    // Send to main process via IPC to run native Apple Vision face tracking
    ipcRenderer.invoke("syphonDetectHumanFace", inputBuffer, targetW, targetH)
        .then((faces) => {
            isProcessing = false;
            if (!inActive.get()) return;

            outFaces.set(faces || []);
            outNumFaces.set(faces ? faces.length : 0);
            outTrigger.trigger();
        })
        .catch((err) => {
            isProcessing = false;
            op.logWarn("[HumanFace] Face Tracking failed: " + err.message);
        });
};

op.onDelete = () => {
    const gl = cgl.gl;
    if (op._fbo) {
        try { gl.deleteFramebuffer(op._fbo); } catch (e) {}
        op._fbo = null;
    }
    if (op._downsampleFbo) {
        try { gl.deleteFramebuffer(op._downsampleFbo); } catch (e) {}
        op._downsampleFbo = null;
    }
    if (op._downsampleTex) {
        op._downsampleTex.dispose();
        op._downsampleTex = null;
    }
};
