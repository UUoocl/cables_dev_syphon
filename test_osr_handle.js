import { app, BrowserWindow } from "electron";

app.whenReady().then(() => {
    const win = new BrowserWindow({
        width: 400,
        height: 400,
        show: false,
        webPreferences: {
            offscreen: {
                useSharedTexture: true
            }
        }
    });

    win.webContents.on("paint", (event, dirty, image) => {
        try {
            console.log("=== OSR Paint Event Triggered ===");
            console.log("event keys:", Object.keys(event));
            const texture = event.texture;
            console.log("event.texture exists:", !!texture);
            if (texture) {
                console.log("texture keys:", Object.keys(texture));
                console.log("textureInfo:", JSON.stringify(texture.textureInfo, (key, value) => {
                    if (value instanceof Buffer) {
                        return `Buffer(len=${value.length}, hex=${value.toString("hex")})`;
                    }
                    return value;
                }, 2));
                
                if (texture.textureInfo && texture.textureInfo.handle) {
                    const handle = texture.textureInfo.handle;
                    console.log("handle.ioSurface type:", typeof handle.ioSurface);
                    console.log("handle.ioSurface constructor:", handle.ioSurface ? handle.ioSurface.constructor.name : "null");
                    if (handle.ioSurface instanceof Buffer) {
                        console.log("handle.ioSurface buffer length:", handle.ioSurface.length);
                        console.log("handle.ioSurface hex:", handle.ioSurface.toString("hex"));
                    } else {
                        console.log("handle.ioSurface value:", handle.ioSurface);
                    }
                }
            }
        } catch (e) {
            console.error("Error in paint handler:", e);
        } finally {
            win.destroy();
            app.quit();
        }
    });

    // Load a WebGL context or page that forces GPU rendering so the texture is created
    win.loadURL("data:text/html,<html><body><canvas id='c'></canvas><script>const gl = document.getElementById('c').getContext('webgl'); gl.clearColor(1,0,0,1); gl.clear(gl.COLOR_BUFFER_BIT);</script></body></html>");
});
