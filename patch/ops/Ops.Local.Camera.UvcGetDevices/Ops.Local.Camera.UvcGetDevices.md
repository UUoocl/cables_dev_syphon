# Ops.Local.Camera.UvcGetDevices

Queries available USB Video Class (UVC) capture devices using native Apple IOKit USB framework bridge.

## Overview
Discovers and lists all connected UVC-compliant USB video cameras, webcams, capture cards, and PTZ cameras directly via macOS IOKit.

## Features
- **In-Process Native Scan**: Zero sidecar processes; queries the USB bus in milliseconds.
- **Hardware Metadata**: Outputs vendor ID, product ID, location ID, and device index for seamless camera targeting in `Ops.Local.Camera.UvcController`.
