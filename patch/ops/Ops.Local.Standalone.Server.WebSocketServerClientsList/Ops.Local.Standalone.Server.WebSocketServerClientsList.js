const
    inServerInstance = op.inObject("Server Instance"),
    inActive = op.inBool("Active", true),

    outConnected = op.outTrigger("On Client Connected"),
    outDisconnected = op.outTrigger("On Client Disconnected"),
    outCount = op.outNumber("Active Client Count", 0),
    outClientList = op.outArray("Client List"),
    outLastClientId = op.outString("Last Client ID"),
    outActiveChannels = op.outArray("Active Channels");

let currentBroker = null;

const handleConnect = (clientInfo) =>
{
    if (!inActive.get()) return;
    outLastClientId.set(clientInfo ? clientInfo.id : "");
    refreshState();
    outConnected.trigger();
};

const handleDisconnect = (clientInfo) =>
{
    if (!inActive.get()) return;
    outLastClientId.set(clientInfo ? clientInfo.id : "");
    refreshState();
    outDisconnected.trigger();
};

const handleSubscriptionChange = () =>
{
    if (!inActive.get()) return;
    refreshState();
};

function refreshState()
{
    if (currentBroker && typeof currentBroker.getClientList === "function")
    {
        const list = currentBroker.getClientList();
        outCount.set(list.length);
        outClientList.set(list);
        outActiveChannels.set(currentBroker.getActiveChannels());
    }
    else
    {
        outCount.set(0);
        outClientList.set([]);
        outActiveChannels.set([]);
    }
}

function detachBroker()
{
    if (currentBroker && typeof currentBroker.off === "function")
    {
        currentBroker.off("clientConnect", handleConnect);
        currentBroker.off("clientDisconnect", handleDisconnect);
        currentBroker.off("clientSubscribe", handleSubscriptionChange);
        currentBroker.off("clientUnsubscribe", handleSubscriptionChange);
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
        currentBroker.on("clientConnect", handleConnect);
        currentBroker.on("clientDisconnect", handleDisconnect);
        currentBroker.on("clientSubscribe", handleSubscriptionChange);
        currentBroker.on("clientUnsubscribe", handleSubscriptionChange);
        refreshState();
    }
    else
    {
        refreshState();
    }
}

inServerInstance.onChange = attachBroker;

op.onDelete = () =>
{
    detachBroker();
};
