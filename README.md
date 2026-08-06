# Cables Standalone with Syphon IO Support

This workspace contains the development environment for a custom version of Cables Standalone (`cables_electron`) featuring real-time GPU-to-GPU **Syphon video input and output** on macOS.

---

## Workspace Structure

- **`cables_dev/cables_electron/`**: The Electron standalone wrapper for the Cables editor and engine.
- **`cables_electron_syphon/`**: A standalone Node-API native bridge module linking Electron/Node.js to macOS system graphics frameworks (`Metal`, `IOSurfaceRef`, `CoreVideo`) and the `Syphon.framework`.
- **`reference/`**: Reference source code and build assets for the OBS Studio Syphon Server plugin.

---

## Prerequisites

- **macOS** (Syphon is a macOS-only texture sharing framework).
- **Node.js** (v20+ or v24+).
- **Xcode Command Line Tools** (required to compile the native module).
- **Python 3** (required by `node-gyp` for compilation).

---

## How to Build and Run

1. **Install and Link Dependencies**
   Navigate to the Electron project directory and install the packages. This will automatically compile the native Syphon bridge package (`cables_electron_syphon`) using `node-gyp`:
   ```bash
   cd cables_dev/cables_electron
   npm install
   ```

2. **Run Cables Standalone**
   Start the development server and watch task:
   ```bash
   npm run start
   ```

---

## Changes to cables_electron
To support custom video sharing and rendering integrations, several modifications were made to the core `cables_dev/cables_electron` standalone application:

### 1. Syphon Support
*   **Dependency Integration**: Added the custom native addon `"cables-electron-syphon": "file:../../cables_electron_syphon"` as a development dependency inside [package.json](cables_dev/cables_electron/package.json). This compiles and binds the macOS native bridge automatically on `npm install`.
*   **Main Process API Extensions**: Modified [electron_api.js](cables_dev/cables_electron/src/electron/electron_api.js) to import the bridge and register IPC channels:
    *   `syphonGetServers`: Queries active system-wide Syphon streams.
    *   `syphonSubscribe` & `syphonUnsubscribe`: Creates and destroys native clients, managing the shared texture stream.
    *   `syphonPublishStart` & `syphonPublishStop`: Orchestrates the publishing server lifecycle.
    *   `syphonPublishFrame`: Channels raw frame buffers from the renderer directly to Metal.
*   **Subframe Target Routing**: Adjusted IPC message delivery in `electron_api.js` to send shared textures directly to `event.senderFrame` (editor iframe context) to ensure stable texture importing and cleanup.
*   **Terminal Log Bridging**: Added a `renderer-log` IPC handler to route browser console outputs to the Node terminal process.

### 2. HTML-in-Canvas Support
*   **Blink Switch Activation**: Modified [main.js](cables_dev/cables_electron/src/electron/main.js) to append the `--enable-blink-features=CanvasDrawElement` flag to Electron's startup command-line switches. This exposes Chromium's experimental browser-native HTML-in-Canvas APIs (`HTMLCanvasElement.prototype.requestPaint` and `WebGLRenderingContext.prototype.texElementImage2D`) to the WebGL context.
*   **DOM Painting Pipeline**: Allows opting the canvas element into layout subtree mode using the `layoutsubtree` attribute, enabling high-performance GPU uploads of fully styled HTML/CSS nodes directly to WebGL textures without CPU rasterization bottlenecks.

---

### How to Use Syphon IO

### 1. Syphon Input (Get Video into Cables)
Bring external video feeds (like OBS Studio or VJ software output) directly into Cables GPU-to-GPU:
1. Start a Syphon Server on your system (e.g. enable the Syphon Server plugin in OBS Studio sharing a test pattern or source).
2. Inside the Cables editor, add the custom Op: `Ops.Local.Syphon.SyphonInput`.
3. Click the **Refresh Servers** trigger button on the Op, or select the active server from the **Server** dropdown list.
4. **Custom UI Integration**: Alternatively, you can use the custom Op `Ops.Local.Syphon.SyphonList`. Triggering its `Refresh` port outputs the list of active server names as a JavaScript Array (`Servers`). You can pass this array to custom UI selector components and connect the selected name directly to the `Server` input port of `Ops.Local.Syphon.SyphonInput` to build dynamic server selectors inside your patch.
5. Connect the `Texture` output port to a rendering Op (e.g. `DrawImage` or `FullscreenRectangle`) to display the real-time, zero-copy feed.

### 2. Syphon Output (Send Video out of Cables)
Publish your visual generations from Cables back to the system (e.g. to OBS Studio or MadMapper):
1. Inside the Cables editor, add the custom Op: `Ops.Local.Syphon.SyphonOutput`.
2. Connect your desired rendering texture to the `Texture` input port.
3. Enter a custom name in the `Server Name` text input port (defaults to `Cables Output`).
4. Trigger the `Update` port (usually connected to your main rendering loop/draw trigger) to start streaming frames to the Syphon server.
5. In your receiver software (e.g. OBS Studio), add a Syphon Source and select the server name you specified in Cables (e.g., `cables: Cables Output`). The visual feed will update in real time.

---

### How to Use HTML-in-Canvas

The browser-native HTML-in-Canvas feature allows rendering rich, interactive DOM content (text, tables, CSS layouts) directly onto WebGL textures without CPU rasterization or image export overhead:

1. Inside the Cables editor, add the custom Op: `Ops.Local.Canvas.HTMLInCanvas`.
2. Connect a DOM/HTML element (e.g., output by `Ops.Html.Element` or a custom UI element Op) to the `Element` input port.
3. Configure the `Width` and `Height` ports to set the render resolution of the output texture.
4. Trigger the `Update` port to refresh the layout paint tree.
5. Connect the `Texture` output port to any WebGL rendering Op (like `DrawImage` or a custom Shader) to display the DOM element in your 3D canvas scene.

