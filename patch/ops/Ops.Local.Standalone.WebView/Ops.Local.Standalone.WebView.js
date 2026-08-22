// Ops.Local.Standalone.WebView.js

const
    inUrl = op.inString("URL", "https://cables.gl"),
    inActive = op.inBool("Active", true),
    inWidth = op.inInt("Width", 640),
    inHeight = op.inInt("Height", 480),
    inPosX = op.inInt("Position X", 100),
    inPosY = op.inInt("Position Y", 100),
    inTransparent = op.inBool("Transparent", false),
    inAllowPopups = op.inBool("Allow Popups", true),
    inPreload = op.inString("Preload Script Path", ""),
    inContextIsolation = op.inBool("Context Isolation", false),
    inNodeIntegration = op.inBool("Node Integration", false),
    inReload = op.inTriggerButton("Reload"),
    inBack = op.inTriggerButton("Go Back"),
    inForward = op.inTriggerButton("Go Forward"),
    inExecJsStr = op.inStringEditor("JavaScript Code", ""),
    inExecJsTrigger = op.inTriggerButton("Execute JS"),
    inCssStr = op.inStringEditor("CSS Code", ""),
    inInjectCssTrigger = op.inTriggerButton("Inject CSS"),

    outElement = op.outObject("Element", null),
    outIsLoaded = op.outBoolNum("Is Loaded", false),
    outTitle = op.outString("Page Title", ""),
    outCurrentUrl = op.outString("Current URL", ""),
    outDomReady = op.outTrigger("DOM Ready"),
    outDidFinishLoad = op.outTrigger("Did Finish Load"),
    outIpcMessage = op.outObject("IPC Message", null),
    outSupported = op.outBoolNum("Supported", true),
    outError = op.outString("Error", "");

op.setPortGroup("Configuration", [inUrl, inActive, inTransparent, inAllowPopups, inPreload, inContextIsolation, inNodeIntegration]);
op.setPortGroup("Layout", [inWidth, inHeight, inPosX, inPosY]);
op.setPortGroup("Navigation", [inReload, inBack, inForward]);
op.setPortGroup("Injection", [inExecJsStr, inExecJsTrigger, inCssStr, inInjectCssTrigger]);

let containerEl = null;
let webviewEl = null;

function getTopDocument()
{
    if (typeof window !== "undefined")
    {
        if (window.top && window.top.document) return window.top.document;
        return window.document;
    }
    return null;
}

function updateLayout()
{
    if (!containerEl) return;
    const w = inWidth.get() || 640;
    const h = inHeight.get() || 480;
    const x = inPosX.get() ?? 100;
    const y = inPosY.get() ?? 100;
    const active = inActive.get();
    const transparent = inTransparent.get();

    containerEl.style.width = w + "px";
    containerEl.style.height = h + "px";
    containerEl.style.left = x + "px";
    containerEl.style.top = y + "px";
    containerEl.style.display = active ? "flex" : "none";
    containerEl.style.background = transparent ? "transparent" : "#1e1e1e";
}

function createWebView()
{
    destroyWebView();

    if (!inActive.get()) return;

    const doc = (typeof document !== "undefined") ? document : null;
    const topDoc = getTopDocument();

    if (!doc || !doc.body)
    {
        setTimeout(createWebView, 100);
        return;
    }

    try
    {
        containerEl = doc.createElement("div");
        containerEl.id = "cables_webview_container_" + op.id;
        containerEl.style.position = "fixed";
        containerEl.style.zIndex = "999999";
        containerEl.style.display = "flex";
        containerEl.style.flexDirection = "column";
        containerEl.style.overflow = "hidden";
        containerEl.style.border = inTransparent.get() ? "none" : "1px solid rgba(255, 255, 255, 0.15)";
        containerEl.style.borderRadius = inTransparent.get() ? "0" : "6px";
        containerEl.style.boxShadow = inTransparent.get() ? "none" : "0 8px 24px rgba(0,0,0,0.6)";

        updateLayout();

        // Instantiate webview element (using topDoc factory if inside subframe)
        if (topDoc && typeof topDoc.createElement === "function")
        {
            webviewEl = topDoc.createElement("webview");
        }
        else
        {
            webviewEl = doc.createElement("webview");
        }

        webviewEl.style.flex = "1";
        webviewEl.style.width = "100%";
        webviewEl.style.height = "100%";
        webviewEl.style.border = "none";
        webviewEl.style.background = inTransparent.get() ? "transparent" : "#ffffff";

        const webPrefs = [];
        webPrefs.push("contextIsolation=" + (inContextIsolation.get() ? "yes" : "no"));
        webPrefs.push("nodeIntegration=" + (inNodeIntegration.get() ? "yes" : "no"));
        if (inTransparent.get()) webPrefs.push("transparent=yes");
        webviewEl.setAttribute("webpreferences", webPrefs.join(", "));

        if (inAllowPopups.get())
        {
            webviewEl.setAttribute("allowpopups", "");
        }

        const preload = inPreload.get();
        if (preload && typeof preload === "string" && preload.trim())
        {
            webviewEl.setAttribute("preload", preload.trim());
        }

        const initialUrl = inUrl.get() || "";
        if (initialUrl)
        {
            webviewEl.src = initialUrl;
            outCurrentUrl.set(initialUrl);
        }

        webviewEl.addEventListener("dom-ready", () =>
        {
            outIsLoaded.set(true);
            outDomReady.trigger();
            outError.set("");
            try
            {
                if (typeof webviewEl.getTitle === "function")
                {
                    outTitle.set(webviewEl.getTitle() || "");
                }
                if (typeof webviewEl.getURL === "function")
                {
                    outCurrentUrl.set(webviewEl.getURL() || "");
                }
            }
            catch (e) {}
        });

        webviewEl.addEventListener("did-finish-load", () =>
        {
            outIsLoaded.set(true);
            outDidFinishLoad.trigger();
            try
            {
                if (typeof webviewEl.getTitle === "function")
                {
                    outTitle.set(webviewEl.getTitle() || "");
                }
                if (typeof webviewEl.getURL === "function")
                {
                    outCurrentUrl.set(webviewEl.getURL() || "");
                }
            }
            catch (e) {}
        });

        webviewEl.addEventListener("page-title-updated", (e) =>
        {
            if (e && e.title) outTitle.set(e.title);
        });

        webviewEl.addEventListener("ipc-message", (event) =>
        {
            if (event)
            {
                outIpcMessage.set({
                    "channel": event.channel,
                    "args": event.args,
                    "data": (event.args && event.args.length > 0) ? event.args[0] : null
                });
            }
        });

        webviewEl.addEventListener("did-fail-load", (event) =>
        {
            if (event && event.errorDescription)
            {
                outError.set(`Load failed: ${event.errorDescription} (${event.errorCode})`);
            }
        });

        containerEl.appendChild(webviewEl);
        doc.body.appendChild(containerEl);

        outElement.setRef(containerEl);
        outSupported.set(true);
    }
    catch (err)
    {
        op.logError("[WebView] Error creating webview:", err);
        outError.set("WebView creation failed: " + err.message);
        outSupported.set(false);
    }
}

function destroyWebView()
{
    if (webviewEl)
    {
        try
        {
            if (webviewEl.parentNode) webviewEl.parentNode.removeChild(webviewEl);
        }
        catch (e) {}
        webviewEl = null;
    }

    if (containerEl)
    {
        try
        {
            if (containerEl.parentNode) containerEl.parentNode.removeChild(containerEl);
        }
        catch (e) {}
        containerEl = null;
    }

    outElement.setRef(null);
    outIsLoaded.set(false);
}

inUrl.onChange = () =>
{
    const u = inUrl.get() || "";
    if (webviewEl && u)
    {
        try
        {
            if (typeof webviewEl.loadURL === "function")
            {
                webviewEl.loadURL(u);
            }
            else
            {
                webviewEl.src = u;
            }
            outCurrentUrl.set(u);
        }
        catch (e)
        {
            op.logWarn("[WebView] Failed to load URL:", e);
        }
    }
};

inActive.onChange = () =>
{
    if (inActive.get())
    {
        if (!containerEl) createWebView();
        else updateLayout();
    }
    else
    {
        if (containerEl) updateLayout();
    }
};

inWidth.onChange = updateLayout;
inHeight.onChange = updateLayout;
inPosX.onChange = updateLayout;
inPosY.onChange = updateLayout;
inTransparent.onChange = () => { createWebView(); };
inAllowPopups.onChange = () => { createWebView(); };
inPreload.onChange = () => { createWebView(); };
inContextIsolation.onChange = () => { createWebView(); };
inNodeIntegration.onChange = () => { createWebView(); };

inReload.onTriggered = () =>
{
    if (webviewEl)
    {
        try
        {
            if (typeof webviewEl.reload === "function") webviewEl.reload();
            else if (typeof webviewEl.reloadIgnoringCache === "function") webviewEl.reloadIgnoringCache();
            else webviewEl.src = webviewEl.src;
        }
        catch (e) {}
    }
};

inBack.onTriggered = () =>
{
    if (webviewEl && typeof webviewEl.goBack === "function" && webviewEl.canGoBack())
    {
        webviewEl.goBack();
    }
};

inForward.onTriggered = () =>
{
    if (webviewEl && typeof webviewEl.goForward === "function" && webviewEl.canGoForward())
    {
        webviewEl.goForward();
    }
};

inExecJsTrigger.onTriggered = () =>
{
    const js = inExecJsStr.get();
    if (webviewEl && js && typeof webviewEl.executeJavaScript === "function")
    {
        webviewEl.executeJavaScript(js).catch((err) =>
        {
            op.logWarn("[WebView] executeJavaScript error:", err);
            outError.set("JS Error: " + err.message);
        });
    }
};

inInjectCssTrigger.onTriggered = () =>
{
    const css = inCssStr.get();
    if (webviewEl && css && typeof webviewEl.insertCSS === "function")
    {
        webviewEl.insertCSS(css).catch((err) =>
        {
            op.logWarn("[WebView] insertCSS error:", err);
            outError.set("CSS Error: " + err.message);
        });
    }
};

createWebView();

op.onDelete = () =>
{
    destroyWebView();
};
