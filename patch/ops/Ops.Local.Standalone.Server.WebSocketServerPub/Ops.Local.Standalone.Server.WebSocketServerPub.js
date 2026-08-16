const
    inServerInstance = op.inObject("Server Instance"),
    inChannel = op.inString("Channel", "message"),
    inData = op.inObject("Data"),
    inPublish = op.inTriggerButton("Publish"),
    inTargetClientId = op.inString("Target Client ID", ""),
    inSendToAllClients = op.inBool("Send to All Clients", false),
    inSendToAllChannels = op.inBool("Send to All Channels", false),
    inRetain = op.inBool("Retain", false),

    outPublished = op.outTrigger("On Published"),
    outSubscribersCount = op.outNumber("Subscribers Count", 0),
    outSuccess = op.outBoolNum("Success", false);

let currentBroker = null;

inServerInstance.onChange = () =>
{
    const serverObj = inServerInstance.get();
    currentBroker = serverObj && (serverObj.broker || serverObj.pubsub || serverObj.client || serverObj);
    updateSubscribers();
};

inChannel.onChange = updateSubscribers;
inSendToAllClients.onChange = updateSubscribers;
inSendToAllChannels.onChange = updateSubscribers;

function updateSubscribers()
{
    if (currentBroker && typeof currentBroker.getSubscriberCount === "function")
    {
        const channel = inChannel.get() || "message";
        const allClients = inSendToAllClients.get();
        const allChannels = inSendToAllChannels.get();
        outSubscribersCount.set(currentBroker.getSubscriberCount(channel, allClients, allChannels));
    }
    else
    {
        outSubscribersCount.set(0);
    }
}

inPublish.onTriggered = () =>
{
    const serverObj = inServerInstance.get();
    const broker = serverObj && (serverObj.broker || serverObj.pubsub || serverObj.client || serverObj);

    if (!broker || typeof broker.publish !== "function")
    {
        outSuccess.set(false);
        return;
    }

    const channel = inChannel.get() || "message";
    const data = inData.get();
    const targetClientId = inTargetClientId.get() ? inTargetClientId.get().trim() : null;
    const sendToAllClients = inSendToAllClients.get();
    const sendToAllChannels = inSendToAllChannels.get();
    const retain = inRetain.get();

    try
    {
        const count = broker.publish(channel, data, {
            "targetClientId": targetClientId,
            "sendToAllClients": sendToAllClients,
            "sendToAllChannels": sendToAllChannels,
            "retain": retain,
            "senderClientId": "patch"
        });

        outSubscribersCount.set(count);
        outSuccess.set(true);
        outPublished.trigger();
    }
    catch (e)
    {
        op.logWarn("[WebSocketPub] Publish error:", e);
        outSuccess.set(false);
    }
};
