/**
 * Ops.Local.Vision.PersonSegmentation
 * Isolates a person from an input texture using native macOS Apple Vision,
 * outputting a high-quality person segmentation mask in real-time.
 */
const
    render = op.inTrigger("Render"),
    inTexture = op.inTexture("Texture"),
    inActive = op.inBool("Active", true),
    inQuality = op.inValueSelect("Quality Level", ["Accurate", "Balanced", "Fast"], "Balanced"),
    
    outTex = op.outTexture("Segmentation Mask"),
    outNext = op.outTrigger("On Mask Ready"),
    outWidth = op.outNumber("Mask Width"),
    outHeight = op.outNumber("Mask Height");

const cgl = op.patch.cgl;
const emptyTexture = CGL.Texture.getEmptyTexture(cgl);
outTex.setRef(emptyTexture);

let ipcRenderer = null;
let texture = null;
let isProcessing = false;
let lastInputWidth = 0;
let lastInputHeight = 0;
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

    lastInputWidth = width;
    lastInputHeight = height;

    // Downsample calculations (max 384px dimension for high performance)
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

    // Read the downsampled pixels directly to local JS buffer
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, op._downsampleFbo);
    gl.readPixels(0, 0, targetW, targetH, gl.RGBA, gl.UNSIGNED_BYTE, inputBuffer);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);

    isProcessing = true;

    // Send frame to main process for native Apple Vision segmentation
    ipcRenderer.invoke("syphonProcessSegmentation", inputBuffer, targetW, targetH, inQuality.get().toLowerCase()).then((result) => {
        if (!result || !inActive.get()) {
            isProcessing = false;
            return;
        }

        handleIosurfaceMask(result.maskBuffer, result.width, result.height);
    }).catch((err) => {
        isProcessing = false;
        op.logWarn("[PersonSegmentation] Segmentation failed in main process: " + err.message);
    });
};

function handleIosurfaceMask(maskBuffer, maskW, maskH) {
    isProcessing = false; // Release backpressure

    if (!maskBuffer || maskW === 0 || maskH === 0) return;

    try {
        const gl = cgl.gl;

        // Upload received 1-channel mask to temporary small texture
        if (!op._maskSmallTex || op._maskSmallTex.width !== maskW || op._maskSmallTex.height !== maskH) {
            if (op._maskSmallTex) op._maskSmallTex.dispose();
            op._maskSmallTex = new CGL.Texture(cgl, {
                width: maskW,
                height: maskH,
                filter: CGL.Texture.FILTER_LINEAR
            });
        }

        gl.bindTexture(gl.TEXTURE_2D, op._maskSmallTex.tex);

        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.R8,
            maskW,
            maskH,
            0,
            gl.RED,
            gl.UNSIGNED_BYTE,
            maskBuffer
        );

        // Swizzle red channel across R, G, B channels and force alpha to 1.0 (opaque)
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_R, gl.RED);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_G, gl.RED);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_B, gl.RED);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_SWIZZLE_A, gl.ONE);

        // Allocate/Resize output texture to MATCH THE ORIGINAL INPUT SIZE
        const originalW = lastInputWidth || maskW;
        const originalH = lastInputHeight || maskH;

        if (!texture || texture.width !== originalW || texture.height !== originalH) {
            op.log("[PersonSegmentation] Creating upscale mask texture: " + originalW + "x" + originalH);
            if (texture) texture.dispose();
            texture = new CGL.Texture(cgl, {
                width: originalW,
                height: originalH,
                filter: CGL.Texture.FILTER_LINEAR,
            });
            outTex.set(texture);
        }

        outWidth.set(originalW);
        outHeight.set(originalH);

        // Upscale temporary mask back to original size on the GPU using FBO Blit
        if (!op._maskSmallFbo) op._maskSmallFbo = gl.createFramebuffer();
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, op._maskSmallFbo);
        gl.framebufferTexture2D(gl.READ_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, op._maskSmallTex.tex, 0);

        if (!op._maskUpscaleFbo) op._maskUpscaleFbo = gl.createFramebuffer();
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, op._maskUpscaleFbo);
        gl.framebufferTexture2D(gl.DRAW_FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture.tex, 0);

        gl.blitFramebuffer(
            0, 0, maskW, maskH,
            0, 0, originalW, originalH,
            gl.COLOR_BUFFER_BIT,
            gl.LINEAR
        );

        gl.bindFramebuffer(gl.FRAMEBUFFER, null);

        outNext.trigger();
    } catch (e) {
        op.logWarn("[PersonSegmentation] Error handling mask: " + String(e));
    }
}

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
    if (op._maskSmallFbo) {
        try { gl.deleteFramebuffer(op._maskSmallFbo); } catch (e) {}
        op._maskSmallFbo = null;
    }
    if (op._maskUpscaleFbo) {
        try { gl.deleteFramebuffer(op._maskUpscaleFbo); } catch (e) {}
        op._maskUpscaleFbo = null;
    }
    
    if (op._downsampleTex) {
        op._downsampleTex.dispose();
        op._downsampleTex = null;
    }
    if (op._maskSmallTex) {
        op._maskSmallTex.dispose();
        op._maskSmallTex = null;
    }
    if (texture) {
        texture.dispose();
        texture = null;
    }
};
