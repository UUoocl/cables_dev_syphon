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

### How to Use Syphon IO

### 1. Syphon Input (Get Video into Cables)
Bring external video feeds (like OBS Studio or VJ software output) directly into Cables GPU-to-GPU:
1. Start a Syphon Server on your system (e.g. enable the Syphon Server plugin in OBS Studio sharing a test pattern or source).
2. Inside the Cables editor, add the custom Op: `Ops.Gl.Textures.SyphonInput`.
3. Click the **Refresh Servers** trigger button on the Op.
4. Select the active server from the **Server** dropdown list.
5. Connect the `Texture` output port to a rendering Op (e.g. `DrawImage` or `FullscreenRectangle`) to display the real-time, zero-copy feed.

### 2. Syphon Output (Send Video out of Cables)
Publish your visual generations from Cables back to the system (e.g. to OBS Studio or MadMapper):
1. Inside the Cables editor, add the custom Op: `Ops.Gl.Textures.SyphonOutput`.
2. Connect your desired rendering texture to the `Texture` input port.
3. Enter a custom name in the `Server Name` text input port (defaults to `Cables Output`).
4. Trigger the `Update` port (usually connected to your main rendering loop/draw trigger) to start streaming frames to the Syphon server.
5. In your receiver software (e.g. OBS Studio), add a Syphon Source and select the server name you specified in Cables (e.g., `cables: Cables Output`). The visual feed will update in real time.
