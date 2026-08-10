/**
 * Ops.Local.Speech.SpeechToText
 * Transcribes default or custom microphone audio input to a text string in real-time using native macOS Apple Speech APIs.
 */
const
    inActive = op.inBool("Active", false),
    inLocale = op.inValueSelect("Language Locale", ["en-US", "es-ES", "fr-FR", "de-DE", "it-IT", "ja-JP", "zh-CN", "pt-BR"], "en-US"),
    inAudioDevice = op.inValueSelect("Audio Input Device", ["Default System Microphone"]),
    inOutputMode = op.inValueSelect("Output Mode", ["Full Transcript", "New Words Only", "Chunk"], "Full Transcript"),
    inSilenceDuration = op.inValue("Silence Duration (s)", 1.5),
    inResetText = op.inTrigger("Reset Text"),
    
    outText = op.outString("Transcribed Text", ""),
    outTrigger = op.outTrigger("On Word Received"),
    outIsFinal = op.outBool("Is Final Segment", false),
    outRunning = op.outBool("Running", false),
    outStatus = op.outString("Status", "Stopped");

let ipcRenderer = null;
let initialized = false;
let audioDevicesList = [];
let lastEmittedText = "";

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

function handleAddonEvent(event) {
    if (!event) return;

    if (event.type === "transcription") {
        const text = event.text || "";
        outIsFinal.set(!!event.isFinal);
        
        if (event.isFinal) {
            lastEmittedText = "";
        }
        
        const mode = inOutputMode.get();
        if (mode === "New Words Only") {
            const prevWords = lastEmittedText.trim().split(/\s+/).filter(Boolean);
            const currWords = text.trim().split(/\s+/).filter(Boolean);
            
            const isNewSentence = prevWords.length === 0 || 
                                 currWords.length === 0 || 
                                 currWords[0].toLowerCase() !== prevWords[0].toLowerCase();
            
            if (isNewSentence) {
                if (currWords.length <= 5) {
                    const delta = currWords.join(" ");
                    if (delta) {
                        outText.set(delta);
                        outTrigger.trigger();
                    }
                }
            } else if (currWords.length > prevWords.length) {
                const deltaWords = currWords.slice(prevWords.length);
                const delta = deltaWords.join(" ");
                if (delta) {
                    outText.set(delta);
                    outTrigger.trigger();
                }
            }
            lastEmittedText = text;
        } else if (mode === "Chunk") {
            if (event.isFinal) {
                outText.set(text);
                outTrigger.trigger();
            }
        } else {
            outText.set(text);
            outTrigger.trigger();
        }
    } else if (event.type === "devices") {
        audioDevicesList = event.devices || [];
        const names = [];
        audioDevicesList.forEach(dev => {
            names.push(dev.name);
        });
        
        inAudioDevice.setUiAttribs({ "values": names });
    } else if (event.type === "status") {
        outStatus.set(event.status || "Stopped");
        if (event.status === "Running") {
            outRunning.set(true);
        } else if (event.status === "Stopped" || event.status.indexOf("Failed") !== -1) {
            outRunning.set(false);
        }
    }
}

function handleIpcSpeechEvent(_event, msg) {
    handleAddonEvent(msg);
}

function ensureInitialized() {
    if (initialized) return true;
    if (!ipcRenderer) return false;
    
    try {
        ipcRenderer.on("speechEvent", handleIpcSpeechEvent);
        ipcRenderer.invoke("initSpeechRecognizer");
        initialized = true;
        return true;
    } catch (e) {
        op.logError("[SpeechToText] Failed to initialize native recognizer: " + e.message);
        return false;
    }
}

inActive.onChange = () => {
    if (!ensureInitialized()) return;

    if (inActive.get()) {
        const locale = inLocale.get() || "en-US";
        const selectedName = inAudioDevice.get();
        let selectedID = "Default";
        const found = audioDevicesList.find(d => d.name === selectedName);
        if (found) {
            selectedID = found.id;
        }
        const silenceDur = parseFloat(inSilenceDuration.get()) || 1.5;
        
        ipcRenderer.invoke("startSpeechRecognizer", locale, selectedID, silenceDur);
    } else {
        ipcRenderer.invoke("stopSpeechRecognizer");
        outRunning.set(false);
        outStatus.set("Stopped");
    }
};

inLocale.onChange = () => {
    if (!ensureInitialized()) return;
    if (inActive.get()) {
        ipcRenderer.invoke("setSpeechLocale", inLocale.get() || "en-US");
    }
};

inAudioDevice.onChange = () => {
    if (!ensureInitialized()) return;
    if (inActive.get()) {
        const selectedName = inAudioDevice.get();
        let selectedID = "Default";
        const found = audioDevicesList.find(d => d.name === selectedName);
        if (found) {
            selectedID = found.id;
        }
        ipcRenderer.invoke("setSpeechAudioDevice", selectedID);
    }
};

inSilenceDuration.onChange = () => {
    if (!ensureInitialized()) return;
    if (inActive.get()) {
        ipcRenderer.invoke("setSpeechSilenceDuration", parseFloat(inSilenceDuration.get()) || 1.5);
    }
};

inResetText.onTriggered = () => {
    if (!ensureInitialized()) return;
    ipcRenderer.invoke("resetSpeechRecognizer");
    outText.set("");
    lastEmittedText = "";
};

op.onDelete = () => {
    if (ipcRenderer) {
        try {
            ipcRenderer.removeListener("speechEvent", handleIpcSpeechEvent);
            ipcRenderer.invoke("stopSpeechRecognizer");
        } catch (e) {}
    }
};

// Initialize device listing dynamically on evaluation
ensureInitialized();
