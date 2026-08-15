# Ops.Local.Camera.UvcController

Controls and queries UVC PTZ webcams and USB video capture cameras (Pan, Tilt, Zoom, Focus, Exposure, Brightness) via native Apple IOKit USB framework bridge.

## Overview
Connects directly to USB Video Class (UVC) cameras to read hardware properties, stream property state in real-time, and send PTZ and image setting commands.

## Features
- **Direct Hardware PTZ**: Control Pan, Tilt, Zoom, Focus, Exposure, Brightness, White Balance, Contrast, and Saturation.
- **Dedicated Port Inputs**: Direct numerical ports with triggers for easy patching without constructing JSON strings.
- **JSON Command Support**: Programmatic batch control and querying.
- **Hardware Telemetry**: Outputs full property dictionaries and specific coordinate numbers (`Pan`, `Tilt`, `Zoom`, `Focus`, `Exposure`).
