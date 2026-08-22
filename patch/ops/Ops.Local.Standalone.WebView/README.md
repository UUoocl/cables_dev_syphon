# Ops.Local.Standalone.WebView

Embeds, positions, and controls an Electron `<webview>` tag directly inside the Cables Standalone editor and exported standalone applications.

## Features
- **URL Loading**: Direct navigation to web URLs, local files (`file://`), or data URIs.
- **Full Navigation**: Programmatic reload, back, and forward triggers.
- **Script & Style Injection**: Runtime `executeJavaScript` and `insertCSS` triggers.
- **IPC Support**: Bi-directional event listening from preloaded scripts.
- **Customizable Layout**: Pixel dimensions, positioning, transparency, popups, and isolated/integrated context settings.
