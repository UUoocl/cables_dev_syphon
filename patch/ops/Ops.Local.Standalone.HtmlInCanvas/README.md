# Ops.Local.Standalone.HtmlInCanvas

Render styled, interactive HTML/DOM elements directly into a WebGL texture using the experimental browser-native HTML-in-Canvas API.

---

## Description
This Op allows you to use standard HTML elements (like text boxes, buttons, tables, and styled CSS layout trees) and render them directly into a 3D WebGL scene on the GPU, avoiding the slow CPU rasterization or image export paths of traditional web tools.

---

## Design & Architecture
*   **Experimental Blink Native APIs**: Leverages the Chromium `CanvasDrawElement` experimental layout API (enabled via Electron command-line flag).
*   **Layout Subtree Incorporation**: Opts the WebGL canvas into the layout subtree using the canvas `layoutsubtree` attribute. 
*   **Decoupled Rendering Chaining**: Appends the target element as a child of the canvas in the DOM, then requests layout paint updates using `canvas.requestPaint()`.
*   **Zero-Copy GPU Upload**: Binds a cached WebGL texture and calls `gl.texElementImage2D` to upload the element's layout paint tree directly to the GPU texture memory in one native call.

---

## How to Use
1.  **Place the Op**: In Cables, add `Ops.Local.Standalone.HtmlInCanvas`.
2.  **Verify Support**: Check the `Supported` output port (must be `true`; if it is `false`, check that the Electron application has the Blink switch enabled).
3.  **Provide Element**: Connect an HTML/DOM element (e.g. from an HTML UI Op) to the `Element` input port.
4.  **Configure Resolution**: Set the `Width` and `Height` input values to define the rendering resolution of the output texture.
5.  **Trigger Update**: Connect your draw loop or update triggers to the `Update` input port to refresh layout paints.
6.  **Render Texture**: Connect the `Texture` output port to any rendering Op (like `DrawImage` or custom shader material) to place the HTML content in your 3D scene.
