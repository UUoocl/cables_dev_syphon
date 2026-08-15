const electron = op.require("electron");
const ipcRenderer = electron ? electron.ipcRenderer : (window.ipcRenderer || null);

const
    inActive = op.inBool("Active", true),
    inCameraTarget = op.inString("Camera Target", "default"),
    inPollRate = op.inValue("Poll Rate (Hz)", 10),
    inCommand = op.inString("Command", "{}"),
    inTriggerCommand = op.inTriggerButton("Trigger Command"),

    inSetPan = op.inValue("Set Pan", 0),
    inSetTilt = op.inValue("Set Tilt", 0),
    inSendPanTilt = op.inTriggerButton("Send Pan/Tilt"),

    inSetZoom = op.inValue("Set Zoom", 0),
    inSendZoom = op.inTriggerButton("Send Zoom"),

    inSetFocus = op.inValue("Set Focus", 0),
    inSendFocus = op.inTriggerButton("Send Focus"),

    inSetExposure = op.inValue("Set Exposure", 0),
    inSendExposure = op.inTriggerButton("Send Exposure"),

    inSetBrightness = op.inValue("Set Brightness", 50),
    inSendBrightness = op.inTriggerButton("Send Brightness"),

    inResetDefaults = op.inTriggerButton("Reset Defaults"),

    outTrigger = op.outTrigger("Trigger Out"),
    outResult = op.outObject("Result Object"),
    outProperties = op.outObject("Properties Object"),
    outControlsList = op.outArray("Controls List"),
    outPan = op.outNumber("Pan", 0),
    outTilt = op.outNumber("Tilt", 0),
    outZoom = op.outNumber("Zoom", 0),
    outFocus = op.outNumber("Focus", 0),
    outExposure = op.outNumber("Exposure", 0),
    outRunning = op.outBool("Running", false),
    outStatus = op.outString("Status", "Stopped");

inCameraTarget.setUiAttribs({ "display": "dropdown", "values": ["default"] });

let availableDevices = [];
let targetDeviceIndex = 0;
let isPolling = false;

async function refreshDevicesList()
{
    if (!ipcRenderer) return;

    try
    {
        const devices = await ipcRenderer.invoke("uvcGetDevices");
        if (Array.isArray(devices))
        {
            availableDevices = devices;
            const names = devices.map((d) => d.name || `Device ${d.index}`);
            if (names.length === 0) names.push("default");
            inCameraTarget.setUiAttribs({ "values": names });

            const current = inCameraTarget.get();
            if (names.length > 0 && (!names.includes(current) || current === "default"))
            {
                inCameraTarget.set(names[0]);
            }
            resolveTargetIndex();
        }
    }
    catch (e)
    {
        op.logWarn("[UvcController] Device discovery error:", e);
    }
}

function resolveTargetIndex()
{
    const targetName = inCameraTarget.get();
    const dev = availableDevices.find((d) => d.name === targetName);
    targetDeviceIndex = dev ? dev.index : 0;
}

async function startController()
{
    if (!ipcRenderer)
    {
        outStatus.set("Electron IPC Unavailable");
        return;
    }

    resolveTargetIndex();
    const pps = inPollRate.get() > 0 ? inPollRate.get() : 30;

    try
    {
        outStatus.set("Starting polling...");
        await ipcRenderer.invoke("uvcStartPolling", targetDeviceIndex, pps);
        isPolling = true;
        outRunning.set(true);
        outStatus.set("Polling active");

        // Query initial control snapshot
        const controls = await ipcRenderer.invoke("uvcGetControls", targetDeviceIndex);
        if (Array.isArray(controls))
        {
            processControlsSnapshot(controls);
        }
    }
    catch (e)
    {
        op.logWarn("[UvcController] Start error:", e);
        outStatus.set("Error: " + (e.message || String(e)));
        outRunning.set(false);
    }
}

async function stopController()
{
    if (!ipcRenderer) return;

    try
    {
        await ipcRenderer.invoke("uvcStopPolling");
    }
    catch (e) {}

    isPolling = false;
    outRunning.set(false);
    outStatus.set("Stopped");
}

let lastPropsJson = "";

function processControlsSnapshot(controls)
{
    if (!controls) return;
    outControlsList.set(controls);
    const props = {};

    controls.forEach((ctrl) =>
    {
        const name = ctrl.name || "";
        const curVal = ctrl["current-value"];
        if (name)
        {
            props[name] = curVal;
        }

        const nameLower = name.toLowerCase();

        // Pan / Tilt
        if (nameLower.includes("pan") || nameLower.includes("tilt"))
        {
            if (typeof curVal === "object" && curVal !== null)
            {
                if (curVal.pan !== undefined) outPan.set(curVal.pan);
                if (curVal.tilt !== undefined) outTilt.set(curVal.tilt);
            }
            else if (nameLower.includes("pan"))
            {
                outPan.set(curVal);
            }
            else if (nameLower.includes("tilt"))
            {
                outTilt.set(curVal);
            }
        }

        // Zoom
        if (nameLower.includes("zoom"))
        {
            if (typeof curVal === "number")
            {
                outZoom.set(curVal);
            }
            else if (typeof curVal === "object" && curVal !== null && curVal.zoom !== undefined)
            {
                outZoom.set(curVal.zoom);
            }
        }

        // Focus
        if (nameLower.includes("focus"))
        {
            if (typeof curVal === "number")
            {
                outFocus.set(curVal);
            }
        }

        // Exposure
        if (nameLower.includes("exposure"))
        {
            if (typeof curVal === "number")
            {
                outExposure.set(curVal);
            }
        }
    });

    const currentJson = JSON.stringify(props);
    if (currentJson !== lastPropsJson)
    {
        lastPropsJson = currentJson;
        outProperties.set(props);
        outResult.set(controls);
        outTrigger.trigger();
    }
}

function onPollEvent(event, jsonStr)
{
    if (!inActive.get()) return;

    try
    {
        const payload = JSON.parse(jsonStr);
        if (payload && payload.type === "uvc_poll" && Array.isArray(payload.data))
        {
            processControlsSnapshot(payload.data);
        }
    }
    catch (e)
    {
        op.logWarn("[UvcController] Error parsing poll event:", e);
    }
}

if (ipcRenderer)
{
    ipcRenderer.on("uvcPollEvent", onPollEvent);
}

inCameraTarget.onChange = () =>
{
    resolveTargetIndex();
    if (inActive.get())
    {
        startController();
    }
};

inPollRate.onChange = () =>
{
    if (inActive.get() && isPolling)
    {
        startController();
    }
};

inActive.onChange = () =>
{
    if (inActive.get())
    {
        startController();
    }
    else
    {
        stopController();
    }
};

// Send direct Pan / Tilt
inSendPanTilt.onTriggered = async () =>
{
    if (!ipcRenderer) return;
    resolveTargetIndex();
    const panVal = inSetPan.get();
    const tiltVal = inSetTilt.get();

    try
    {
        await ipcRenderer.invoke("uvcSetControlValue", targetDeviceIndex, "pan-tilt-abs", { "pan": panVal, "tilt": tiltVal });
    }
    catch (e)
    {
        op.logWarn("[UvcController] Send Pan/Tilt error:", e);
    }
};

// Send direct Zoom
inSendZoom.onTriggered = async () =>
{
    if (!ipcRenderer) return;
    resolveTargetIndex();
    try
    {
        await ipcRenderer.invoke("uvcSetControlValue", targetDeviceIndex, "zoom-abs", inSetZoom.get());
    }
    catch (e)
    {
        op.logWarn("[UvcController] Send Zoom error:", e);
    }
};

// Send direct Focus
inSendFocus.onTriggered = async () =>
{
    if (!ipcRenderer) return;
    resolveTargetIndex();
    try
    {
        await ipcRenderer.invoke("uvcSetControlValue", targetDeviceIndex, "focus-abs", inSetFocus.get());
    }
    catch (e)
    {
        op.logWarn("[UvcController] Send Focus error:", e);
    }
};

// Send direct Exposure
inSendExposure.onTriggered = async () =>
{
    if (!ipcRenderer) return;
    resolveTargetIndex();
    try
    {
        await ipcRenderer.invoke("uvcSetControlValue", targetDeviceIndex, "exposure-time-abs", inSetExposure.get());
    }
    catch (e)
    {
        op.logWarn("[UvcController] Send Exposure error:", e);
    }
};

// Send direct Brightness
inSendBrightness.onTriggered = async () =>
{
    if (!ipcRenderer) return;
    resolveTargetIndex();
    try
    {
        await ipcRenderer.invoke("uvcSetControlValue", targetDeviceIndex, "brightness", inSetBrightness.get());
    }
    catch (e)
    {
        op.logWarn("[UvcController] Send Brightness error:", e);
    }
};

// Reset Defaults
inResetDefaults.onTriggered = async () =>
{
    if (!ipcRenderer) return;
    resolveTargetIndex();
    const commonControls = ["pan-tilt-abs", "zoom-abs", "focus-abs", "exposure-time-abs", "brightness", "contrast", "saturation", "sharpness", "white-balance-temp"];
    for (const ctrl of commonControls)
    {
        try
        {
            await ipcRenderer.invoke("uvcResetControlValue", targetDeviceIndex, ctrl);
        }
        catch (e) {}
    }
};

// Batch Command execution
inTriggerCommand.onTriggered = async () =>
{
    if (!ipcRenderer) return;
    resolveTargetIndex();

    try
    {
        let cmd = inCommand.get();
        if (typeof cmd === "string")
        {
            cmd = JSON.parse(cmd);
        }

        if (cmd && typeof cmd === "object")
        {
            const action = cmd.action || "";
            const control = cmd.control || "";
            const val = cmd.value;

            if (action === "set_value" && control)
            {
                await ipcRenderer.invoke("uvcSetControlValue", targetDeviceIndex, control, val);
            }
            else if (action === "get_value" && control)
            {
                const res = await ipcRenderer.invoke("uvcGetControlValue", targetDeviceIndex, control);
                outResult.set(res);
            }
            else if (action === "get_controls")
            {
                const res = await ipcRenderer.invoke("uvcGetControls", targetDeviceIndex);
                processControlsSnapshot(res);
            }
            else if (action === "reset_value" && control)
            {
                await ipcRenderer.invoke("uvcResetControlValue", targetDeviceIndex, control);
            }
        }
    }
    catch (e)
    {
        op.logWarn("[UvcController] Command error:", e);
    }
};

op.onDelete = () =>
{
    if (ipcRenderer)
    {
        ipcRenderer.removeListener("uvcPollEvent", onPollEvent);
    }
    stopController();
};

setTimeout(async () =>
{
    await refreshDevicesList();
    if (inActive.get())
    {
        startController();
    }
}, 200);
