const electron = op.require("electron");
const ipcRenderer = electron ? electron.ipcRenderer : (window.ipcRenderer || null);

const
    inActive = op.inBool("Active", true),
    inRefresh = op.inTriggerButton("Refresh Devices"),

    outDevices = op.outArray("Devices"),
    outDeviceNames = op.outArray("Device Names"),
    outCount = op.outNumber("Count", 0),
    outTrigger = op.outTrigger("Trigger Out"),
    outStatus = op.outString("Status", "Ready");

async function fetchDevices()
{
    if (!ipcRenderer)
    {
        outStatus.set("Electron IPC Unavailable");
        return;
    }

    try
    {
        outStatus.set("Querying...");
        const devices = await ipcRenderer.invoke("uvcGetDevices");
        const devs = Array.isArray(devices) ? devices : [];

        outDevices.set(devs);
        const names = devs.map((d) => d.name || `Device ${d.index}`);
        outDeviceNames.set(names);
        outCount.set(devs.length);

        outStatus.set(`Found ${devs.length} device(s)`);
        outTrigger.trigger();
    }
    catch (e)
    {
        op.logWarn("[UvcGetDevices] Query error:", e);
        outStatus.set("Error: " + (e.message || String(e)));
    }
}

inRefresh.onTriggered = () =>
{
    fetchDevices();
};

inActive.onChange = () =>
{
    if (inActive.get())
    {
        fetchDevices();
    }
    else
    {
        outDevices.set([]);
        outDeviceNames.set([]);
        outCount.set(0);
        outStatus.set("Inactive");
    }
};

setTimeout(() =>
{
    if (inActive.get()) fetchDevices();
}, 100);
