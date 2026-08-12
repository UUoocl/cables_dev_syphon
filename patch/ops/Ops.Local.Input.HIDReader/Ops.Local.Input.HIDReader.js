/**
 * Ops.Local.Input.HIDReader
 * Native macOS Apple Human Interface Devices (HID) interface.
 */
const
    inActive = op.inBool("Active", false),
    inVid = op.inValue("Target Vendor ID", 0),
    inPid = op.inValue("Target Product ID", 0),
    inSerial = op.inString("Target Serial Number", ""),
    inWrite = op.inTrigger("Write Output"),
    inWriteType = op.inValueSelect("Output Report Type", ["Output", "Feature"], "Output"),
    inWriteId = op.inValue("Output Report ID", 0),
    inWriteData = op.inArray("Output Report Data"),

    outDevices = op.outArray("Devices", []),
    outOnReport = op.outTrigger("On Report"),
    outReportId = op.outNumber("Report ID", 0),
    outReportData = op.outArray("Report Data", []),
    outStatus = op.outString("Status", "Stopped"),
    outIsConnected = op.outBool("Is Connected", false);

let ipcRenderer = null;
let active = false;
let devicesList = [];

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

function updateConnectionState() {
    if (!active) {
        outIsConnected.set(false);
        outStatus.set("Stopped");
        return;
    }

    const targetVid = parseInt(inVid.get(), 10) || 0;
    const targetPid = parseInt(inPid.get(), 10) || 0;
    const targetSerial = inSerial.get() || "";

    if (targetVid === 0 && targetPid === 0) {
        outIsConnected.set(false);
        outStatus.set("Enter Target VID/PID");
        return;
    }

    const found = devicesList.find(d => {
        const matchVid = d.vendorId === targetVid;
        const matchPid = d.productId === targetPid;
        const matchSerial = targetSerial === "" || d.serialNumber === targetSerial;
        return matchVid && matchPid && matchSerial;
    });

    if (found) {
        outIsConnected.set(true);
        outStatus.set("Connected (" + found.name + ")");
    } else {
        outIsConnected.set(false);
        outStatus.set("Searching for device...");
    }
}

function handleHidEvent(_event, msg) {
    if (!msg || !msg.type) return;

    if (msg.type === "connected" || msg.type === "disconnected") {
        refreshDevices();
    } else if (msg.type === "report") {
        const targetVid = parseInt(inVid.get(), 10) || 0;
        const targetPid = parseInt(inPid.get(), 10) || 0;
        const targetSerial = inSerial.get() || "";

        const matchVid = msg.vendorId === targetVid;
        const matchPid = msg.productId === targetPid;
        const matchSerial = targetSerial === "" || msg.serialNumber === targetSerial;

        if (matchVid && matchPid && matchSerial) {
            outReportId.set(msg.reportId);
            
            // Convert Buffer/Uint8Array to regular Array of numbers
            let bytes = [];
            if (msg.data) {
                if (Array.isArray(msg.data)) {
                    bytes = msg.data;
                } else if (msg.data.data && Array.isArray(msg.data.data)) {
                    bytes = msg.data.data;
                } else {
                    bytes = Array.from(msg.data);
                }
            }
            outReportData.set(bytes);
            outOnReport.trigger();
        }
    }
}

function refreshDevices() {
    if (!ipcRenderer) return;
    ipcRenderer.invoke("hidGetDevices")
        .then((devs) => {
            devicesList = devs || [];
            outDevices.set(devicesList);
            updateConnectionState();
        })
        .catch((err) => {
            op.logError("[HIDReader] Error fetching devices: " + err.message);
        });
}

function start() {
    if (active) stop();
    if (!inActive.get() || !ipcRenderer) return;

    outStatus.set("Starting...");
    ipcRenderer.on("hidEvent", handleHidEvent);

    ipcRenderer.invoke("hidStartMonitoring")
        .then((success) => {
            if (success) {
                active = true;
                refreshDevices();
            } else {
                active = false;
                outStatus.set("Failed to start monitor");
            }
        })
        .catch((err) => {
            active = false;
            op.logError("[HIDReader] Start failed: " + err.message);
            outStatus.set("Error: " + err.message);
        });
}

function stop() {
    if (!active) return;
    active = false;

    if (ipcRenderer) {
        ipcRenderer.removeListener("hidEvent", handleHidEvent);
        ipcRenderer.invoke("hidStopMonitoring").catch(() => {});
    }

    outIsConnected.set(false);
    outStatus.set("Stopped");
}

inActive.onChange = () => {
    if (inActive.get()) {
        start();
    } else {
        stop();
    }
};

inVid.onChange = updateConnectionState;
inPid.onChange = updateConnectionState;
inSerial.onChange = updateConnectionState;

inWrite.onTriggered = () => {
    if (!ipcRenderer) return;
    const targetVid = parseInt(inVid.get(), 10) || 0;
    const targetPid = parseInt(inPid.get(), 10) || 0;
    if (targetVid === 0 && targetPid === 0) return;

    const dataArr = inWriteData.get();
    if (!dataArr || !Array.isArray(dataArr)) {
        op.logWarn("[HIDReader] Output data must be an array.");
        return;
    }

    const typeStr = inWriteType.get();
    const typeVal = typeStr === "Feature" ? 2 : 1; // 1=Output, 2=Feature
    const reportId = parseInt(inWriteId.get(), 10) || 0;

    const buffer = Uint8Array.from(dataArr);
    ipcRenderer.invoke("hidWriteReport", targetVid, targetPid, typeVal, reportId, buffer)
        .then((success) => {
            if (!success) {
                op.logWarn("[HIDReader] Native write report failed.");
            }
        })
        .catch((err) => {
            op.logError("[HIDReader] Write error: " + err.message);
        });
};

op.onDelete = () => {
    stop();
};

// Initial state
outStatus.set("Stopped");
if (inActive.get()) {
    start();
}
