import { createRequire } from "module";
const require = createRequire(import.meta.url);
const syphonBridge = require("./build/Release/syphon_bridge.node");

export default syphonBridge;
