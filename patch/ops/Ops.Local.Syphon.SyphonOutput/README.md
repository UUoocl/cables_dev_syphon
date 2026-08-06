# Ops.Local.Syphon.SyphonOutput

Publish WebGL textures from your Cables patch system-wide on macOS using a dedicated Syphon server.

---

## Description
This Op allows you to output your real-time visual generations from Cables back to macOS (e.g. to stream into OBS Studio, MadMapper, Resolume, or Resolume Arena).

---

## Design & Architecture
*   **Op-Centric Design**: Connects directly to any rendering pipeline texture in your sketch, keeping the standalone app's editor window on-screen and separate.
*   **Framebuffer Capture**: Binds a WebGL framebuffer to the input texture and uses `gl.readPixels()` to copy the pixels into a pre-allocated typed array.
*   **IPC Channeling**: Transfers the pixel buffers via a low-overhead Electron IPC message.
*   **Texture Recycling**: In the main process, the native bridge copies the pixel bytes into a single cached Metal texture using `replaceRegion`. Reusing this texture allocation across frames avoids GC pauses and memory churn.
*   **Vertical Flip Compensation**: WebGL coordinates are flipped vertically compared to standard macOS screen coordinates. The server publishes the frame with `flipped: NO` to orient the visual output correctly.

---

## How to Use
1.  **Place the Op**: In Cables, add `Ops.Local.Syphon.SyphonOutput`.
2.  **Connect Texture**: Connect the texture you want to share (e.g., from `RenderToTexture` or `TextureOp`) to the `Texture` input port.
3.  **Name the Server**: Enter a custom name in the `Server Name` input port (e.g., `My Visual Output`).
4.  **Wire trigger**: Connect your main draw loop trigger to the `Update` port to initiate frame publication.
5.  **Receive Feed**: In your receiver application (e.g. OBS Studio), add a Syphon Source and select your server (e.g., `cables: My Visual Output`).
