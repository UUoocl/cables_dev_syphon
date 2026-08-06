# Ops.Local.Syphon.SyphonInput

Receive video feeds from system Syphon servers on macOS directly into a Cables WebGL texture GPU-to-GPU (hardware accelerated).

---

## Description
This Op allows you to bring live, real-time video streams from other applications (like OBS Studio, Resolume, Resolume Arena, Resolume Avenue, Resolume Wire, or Max/MSP) into your Cables WebGL sketch. 

---

## Design & Architecture
*   **Zero-Copy GPU Sharing**: Uses Electron's experimental `sharedTexture` API to import a macOS `IOSurfaceRef` GPU buffer registered by the native Syphon bridge client.
*   **Chromium Compatibility Blit**: Because many external Syphon servers do not declare a standard pixel format (returning format `0`), the native bridge blits the incoming texture to a standard `'BGRA'` (`kCVPixelFormatType_32BGRA`) `IOSurface` on the GPU.
*   **Subframe Routing**: Messages containing the shared texture handle are target-routed to `event.senderFrame` to ensure they resolve within the sandboxed editor `iframe`.
*   **WebGL Binding**: Inside the Op, the shared texture is uploaded to WebGL as a `VideoFrame` using `gl.texImage2D()`, and the frame reference is immediately closed to prevent GPU memory leaks.
*   **Dropdown Selector**: Includes a built-in dropdown selector list that displays active servers on the system.

---

## How to Use
1.  **Start a Syphon Server**: Run a server on your system (e.g. enable the Syphon Server plugin in OBS Studio with a video source or test pattern running).
2.  **Place the Op**: In Cables, add `Ops.Local.Syphon.SyphonInput`.
3.  **Refresh List**: Click the **Refresh Servers** button to populate the dropdown.
4.  **Select Server**: Click the **Server** dropdown and choose your server.
5.  **Connect Texture**: Connect the `Texture` output port to a draw Op (like `DrawImage` or `FullscreenRectangle`) to render the stream.
