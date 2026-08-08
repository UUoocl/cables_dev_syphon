import { createRequire } from "module";
const require = createRequire(import.meta.url);
const appleBridge = require("./build/Release/apple_framework_bridge.node");

export default appleBridge;
