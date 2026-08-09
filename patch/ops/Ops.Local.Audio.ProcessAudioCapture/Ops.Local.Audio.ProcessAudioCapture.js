const
    inStart = op.inTriggerButton("Start"),
    inStop = op.inTriggerButton("Stop"),
    inRefresh = op.inTriggerButton("Refresh Processes"),
    inProcess = op.inSwitch("Process", ["None"], "None"),
    inGain = op.inFloatSlider("Volume", 1),
    inMute = op.inBool("Mute", false),
    
    audioOut = op.outObject("Audio Out", null, "audioNode"),
    outCapturing = op.outBoolNum("Capturing", false);

op.setPortGroup("Volume Settings", [inGain, inMute]);

const audioCtx = CABLES.WEBAUDIO.createAudioContext(op);
const bufferSize = 4096;
const gainNode = audioCtx.createGain();
gainNode.gain.setValueAtTime(1, audioCtx.currentTime);

let scriptNode = null;
let ringBuffer = null;
let isCapturing = false;
let ipcRenderer = null;
let processes = [];

class AudioRingBuffer {
    constructor(capacity = 48000 * 2) {
        this.capacity = capacity;
        this.bufferL = new Float32Array(capacity);
        this.bufferR = new Float32Array(capacity);
        this.readIndex = 0;
        this.writeIndex = 0;
        this.length = 0;
    }
    
    write(dataL, dataR) {
        const len = dataL.length;
        if (this.length + len > this.capacity) {
            // Buffer overflow: drop older samples to maintain real-time low latency
            this.readIndex = (this.readIndex + len) % this.capacity;
            this.length = Math.max(0, this.capacity - len);
        }
        
        for (let i = 0; i < len; i++) {
            const idx = (this.writeIndex + i) % this.capacity;
            this.bufferL[idx] = dataL[i];
            this.bufferR[idx] = dataR[i];
        }
        this.writeIndex = (this.writeIndex + len) % this.capacity;
        this.length += len;
    }
    
    read(outL, outR) {
        const len = outL.length;
        if (this.length < len) {
            // Underflow: output silence
            outL.fill(0);
            outR.fill(0);
            return false;
        }
        
        for (let i = 0; i < len; i++) {
            const idx = (this.readIndex + i) % this.capacity;
            outL[i] = this.bufferL[idx];
            outR[i] = this.bufferR[idx];
        }
        this.readIndex = (this.readIndex + len) % this.capacity;
        this.length -= len;
        return true;
    }
}

ringBuffer = new AudioRingBuffer();

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
    console.warn("[ProcessAudioCapture] Electron ipcRenderer not found");
}

function initAudioNodes() {
    if (scriptNode) return;
    
    scriptNode = audioCtx.createScriptProcessor(bufferSize, 0, 2);
    scriptNode.onaudioprocess = (e) => {
        const outL = e.outputBuffer.getChannelData(0);
        const outR = e.outputBuffer.getChannelData(1);
        ringBuffer.read(outL, outR);
    };
}

function startScriptNode() {
    initAudioNodes();
    scriptNode.connect(gainNode);
}

function stopScriptNode() {
    if (scriptNode) {
        try {
            scriptNode.disconnect(gainNode);
        } catch (e) {}
    }
}

function refreshProcessList() {
    if (!ipcRenderer) return;
    
    ipcRenderer.invoke("syphonGetAudioSources").then((list) => {
        processes = list || [];
        const names = ["None"];
        processes.forEach((p) => {
            names.push(`${p.name} (${p.pid})`);
        });
        inProcess.setUiAttribs({ "values": names });
    }).catch((err) => {
        op.logError("[ProcessAudioCapture] Failed to get processes:", err);
    });
}

let frameCount = 0;
function handleAudioFrame(event, leftChannel, rightChannel) {
    if (isCapturing) {
        if (frameCount < 10) {
            frameCount++;
            let nonZeroL = 0;
            if (leftChannel) {
                for (let i = 0; i < leftChannel.length; i++) {
                    if (leftChannel[i] !== 0) nonZeroL++;
                }
            }
            // console.log(`[ProcessAudioCapture] Received frame #${frameCount}. L-len: ${leftChannel ? leftChannel.length : 'null'}, R-len: ${rightChannel ? rightChannel.length : 'null'}, nonZeroSamples: ${nonZeroL}`);
        }
        ringBuffer.write(leftChannel, rightChannel);
    }
}

function startCapture() {
    if (!ipcRenderer) return;
    if (isCapturing) return;
    
    const selected = inProcess.get();
    if (!selected || selected === "None") {
        op.setUiError("noProcess", "No process selected!");
        return;
    }
    op.setUiError("noProcess", null);
    op.setUiError("captureFailed", null);
    
    const match = selected.match(/\((\d+)\)$/);
    if (!match) return;
    const pid = parseInt(match[1], 10);
    
    ringBuffer = new AudioRingBuffer();
    frameCount = 0;
    
    // console.log("[ProcessAudioCapture] AudioContext state before capture:", audioCtx.state);
    if (audioCtx.state === "suspended") {
        audioCtx.resume().then(() => {
            // console.log("[ProcessAudioCapture] AudioContext resumed successfully, state:", audioCtx.state);
        }).catch((err) => {
            console.error("[ProcessAudioCapture] Failed to resume AudioContext:", err);
        });
    }
    
    ipcRenderer.invoke("syphonStartAudioCapture", pid).then((success) => {
        // console.log("[ProcessAudioCapture] syphonStartAudioCapture success result:", success);
        if (success) {
            isCapturing = true;
            outCapturing.set(true);
            startScriptNode();
            ipcRenderer.on("syphonAudioFrame", handleAudioFrame);
        } else {
            op.logWarn("[ProcessAudioCapture] Start audio capture returned false");
            op.setUiError("captureFailed", "Capture failed. Make sure screen recording permissions are granted.");
        }
    }).catch((err) => {
        op.logError("[ProcessAudioCapture] Error starting audio capture:", err);
        op.setUiError("captureFailed", "Error starting capture: " + err.message);
    });
}

function stopCapture() {
    if (!ipcRenderer || !isCapturing) return;
    
    ipcRenderer.invoke("syphonStopAudioCapture").then(() => {
        isCapturing = false;
        outCapturing.set(false);
        stopScriptNode();
        ipcRenderer.removeListener("syphonAudioFrame", handleAudioFrame);
    }).catch((err) => {
        op.logError("[ProcessAudioCapture] Error stopping audio capture:", err);
    });
}

inStart.onTriggered = () => {
    startCapture();
};

inStop.onTriggered = () => {
    stopCapture();
};

inRefresh.onTriggered = () => {
    refreshProcessList();
};

inProcess.onChange = () => {
    stopCapture();
};

inGain.onChange = () => {
    if (inMute.get()) return;
    gainNode.gain.setValueAtTime(Number(inGain.get()) || 0, audioCtx.currentTime);
};

inMute.onChange = () => {
    if (inMute.get()) {
        gainNode.gain.setValueAtTime(0, audioCtx.currentTime);
    } else {
        gainNode.gain.setValueAtTime(Number(inGain.get()) || 0, audioCtx.currentTime);
    }
};

// Initial load
initAudioNodes();
audioOut.set(gainNode);
setTimeout(refreshProcessList, 1000);

op.onDelete = () => {
    stopCapture();
    if (scriptNode) {
        try {
            scriptNode.disconnect();
        } catch (e) {}
        scriptNode = null;
    }
};
