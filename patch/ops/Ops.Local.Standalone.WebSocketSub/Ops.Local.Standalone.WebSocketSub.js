const
    inServerInstance = op.inObject("Server Instance"),
    inChannel = op.inString("Channel", "message"),
    inActive = op.inBool("Active", true),
    inAutoParse = op.inBool("Auto Parse JSON", true),

    outMessage = op.outTrigger("On Message"),
    outChannel = op.outString("Channel"),
    outData = op.outObject("Data"),
    outRaw = op.outString("Raw Message"),
    outSender = op.outString("Sender Client ID"),
    outTotalReceived = op.outNumber("Total Received", 0),
    outTimestamp = op.outNumber("Timestamp", 0);

let currentBroker = null;
let messageCount = 0;

const handleBrokerMessage = (msgObj) =>
{
    if (!inActive.get()) return;
    if (!msgObj) return;

    const filterChannel = inChannel.get();
    const msgChannel = msgObj.channel || "";

    // Wildcard '*' or exact channel match
    if (filterChannel !== "*" && filterChannel !== msgChannel) return;

    messageCount++;
    outTotalReceived.set(messageCount);

    outChannel.set(msgChannel);
    outSender.set(msgObj.sender || "");
    outTimestamp.set(msgObj.timestamp || Date.now());

    let payload = msgObj.data;
    if (typeof payload === "string" && inAutoParse.get())
    {
        try
        {
            payload = JSON.parse(payload);
        }
        catch (e) {}
    }

    outData.set(payload);
    outRaw.set(typeof msgObj.data === "object" ? JSON.stringify(msgObj.data) : String(msgObj.data));

    outMessage.trigger();
};

function detachBroker()
{
    if (currentBroker && typeof currentBroker.off === "function")
    {
        currentBroker.off("message", handleBrokerMessage);
    }
    currentBroker = null;
}

function attachBroker()
{
    detachBroker();

    const serverObj = inServerInstance.get();
    const broker = serverObj && (serverObj.broker || serverObj.pubsub || null);

    if (broker && typeof broker.on === "function")
    {
        currentBroker = broker;
        currentBroker.on("message", handleBrokerMessage);
    }
}

inServerInstance.onChange = attachBroker;

op.onDelete = () =>
{
    detachBroker();
};
