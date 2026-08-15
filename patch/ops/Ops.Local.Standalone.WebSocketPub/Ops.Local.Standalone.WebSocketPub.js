const
    inServerInstance = op.inObject("Server Instance"),
    inChannel = op.inString("Channel", "message"),
    inData = op.inObject("Data"),
    inPublish = op.inTriggerButton("Publish"),
    inTargetClientId = op.inString("Target Client ID", ""),
    inRetain = op.inBool("Retain", false),

    outPublished = op.outTrigger("On Published"),
    outSubscribersCount = op.outNumber("Subscribers Count", 0),
    outSuccess = op.outBoolNum("Success", false);

let currentBroker = null;

inServerInstance.onChange = () =>
{
    const serverObj = inServerInstance.get();
    currentBroker = serverObj && (serverObj.broker || serverObj.pubsub || null);
    updateSubscribers();
};

inChannel.onChange = updateSubscribers;

function updateSubscribers()
{
    if (currentBroker && typeof currentBroker.getSubscriberCount === "function")
    {
        outSubscribersCount.set(currentBroker.getSubscriberCount(inChannel.get()));
    }
    else
    {
        outSubscribersCount.set(0);
    }
}

inPublish.onTriggered = () =>
{
    const serverObj = inServerInstance.get();
    const broker = serverObj && (serverObj.broker || serverObj.pubsub || null);

    if (!broker || typeof broker.publish !== "function")
    {
        outSuccess.set(false);
        return;
    }

    const channel = inChannel.get() || "message";
    const data = inData.get();
    const targetClientId = inTargetClientId.get() ? inTargetClientId.get().trim() : null;
    const retain = inRetain.get();

    try
    {
        const count = broker.publish(channel, data, {
            "targetClientId": targetClientId,
            "retain": retain,
            "senderClientId": "patch"
        });

        outSubscribersCount.set(broker.getSubscriberCount(channel));
        outSuccess.set(true);
        outPublished.trigger();
    }
    catch (e)
    {
        op.logWarn("[WebSocketPub] Publish error:", e);
        outSuccess.set(false);
    }
};
