#include "hid_bridge.h"
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <Foundation/Foundation.h>
#include <thread>
#include <mutex>
#include <unordered_map>
#include <vector>
#include <string>
#include <iostream>

static IOHIDManagerRef g_hid_manager = nullptr;
static std::mutex g_devices_mutex;
static std::unordered_map<std::string, IOHIDDeviceRef> g_connected_devices;
static Napi::ThreadSafeFunction g_hid_callback = nullptr;
static std::thread g_run_loop_thread;
static CFRunLoopRef g_cf_run_loop = nullptr;

// Helper to query device properties
static std::string GetDevicePropertyString(IOHIDDeviceRef dev, CFStringRef key) {
    CFTypeRef prop = IOHIDDeviceGetProperty(dev, key);
    if (prop && CFGetTypeID(prop) == CFStringGetTypeID()) {
        char buf[256] = {0};
        if (CFStringGetCString((CFStringRef)prop, buf, sizeof(buf), kCFStringEncodingUTF8)) {
            return std::string(buf);
        }
    }
    return "";
}

static int GetDevicePropertyInt(IOHIDDeviceRef dev, CFStringRef key) {
    CFTypeRef prop = IOHIDDeviceGetProperty(dev, key);
    if (prop && CFGetTypeID(prop) == CFNumberGetTypeID()) {
        int val = 0;
        if (CFNumberGetValue((CFNumberRef)prop, kCFNumberIntType, &val)) {
            return val;
        }
    }
    return 0;
}

static std::string GetDeviceKey(IOHIDDeviceRef device) {
    int vid = GetDevicePropertyInt(device, CFSTR(kIOHIDVendorIDKey));
    int pid = GetDevicePropertyInt(device, CFSTR(kIOHIDProductIDKey));
    std::string serial = GetDevicePropertyString(device, CFSTR(kIOHIDSerialNumberKey));
    return std::to_string(vid) + ":" + std::to_string(pid) + ":" + serial;
}

static void EnsureHIDManagerCreated() {
    if (!g_hid_manager) {
        g_hid_manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        IOHIDManagerSetDeviceMatching(g_hid_manager, NULL); // matches all HID devices
    }
}

// IOKit Callbacks
static void MatchCallback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device) {
    std::string key = GetDeviceKey(device);
    int vid = GetDevicePropertyInt(device, CFSTR(kIOHIDVendorIDKey));
    int pid = GetDevicePropertyInt(device, CFSTR(kIOHIDProductIDKey));
    std::string name = GetDevicePropertyString(device, CFSTR(kIOHIDProductKey));
    std::string serial = GetDevicePropertyString(device, CFSTR(kIOHIDSerialNumberKey));
    std::string mfg = GetDevicePropertyString(device, CFSTR(kIOHIDManufacturerKey));
    int usagePage = GetDevicePropertyInt(device, CFSTR(kIOHIDPrimaryUsagePageKey));
    int usage = GetDevicePropertyInt(device, CFSTR(kIOHIDPrimaryUsageKey));

    {
        std::lock_guard<std::mutex> lock(g_devices_mutex);
        g_connected_devices[key] = device;
    }

    if (g_hid_callback) {
        auto callback = [vid, pid, name, serial, mfg, usagePage, usage](Napi::Env env, Napi::Function jsCallback) {
            Napi::Object eventObj = Napi::Object::New(env);
            eventObj.Set("type", Napi::String::New(env, "connected"));
            eventObj.Set("vendorId", Napi::Number::New(env, vid));
            eventObj.Set("productId", Napi::Number::New(env, pid));
            eventObj.Set("name", Napi::String::New(env, name));
            eventObj.Set("serialNumber", Napi::String::New(env, serial));
            eventObj.Set("manufacturer", Napi::String::New(env, mfg));
            eventObj.Set("usagePage", Napi::Number::New(env, usagePage));
            eventObj.Set("usage", Napi::Number::New(env, usage));
            jsCallback.Call({ eventObj });
        };
        g_hid_callback.NonBlockingCall(callback);
    }
}

static void RemovalCallback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device) {
    std::string key = GetDeviceKey(device);
    int vid = GetDevicePropertyInt(device, CFSTR(kIOHIDVendorIDKey));
    int pid = GetDevicePropertyInt(device, CFSTR(kIOHIDProductIDKey));
    std::string serial = GetDevicePropertyString(device, CFSTR(kIOHIDSerialNumberKey));

    {
        std::lock_guard<std::mutex> lock(g_devices_mutex);
        g_connected_devices.erase(key);
    }

    if (g_hid_callback) {
        auto callback = [vid, pid, serial](Napi::Env env, Napi::Function jsCallback) {
            Napi::Object eventObj = Napi::Object::New(env);
            eventObj.Set("type", Napi::String::New(env, "disconnected"));
            eventObj.Set("vendorId", Napi::Number::New(env, vid));
            eventObj.Set("productId", Napi::Number::New(env, pid));
            eventObj.Set("serialNumber", Napi::String::New(env, serial));
            jsCallback.Call({ eventObj });
        };
        g_hid_callback.NonBlockingCall(callback);
    }
}

static void ReportCallback(void* context, IOReturn result, void* sender, IOHIDReportType type, uint32_t reportID, uint8_t* report, CFIndex reportLength) {
    if (result != kIOReturnSuccess) return;

    IOHIDDeviceRef device = (IOHIDDeviceRef)sender;
    int vid = GetDevicePropertyInt(device, CFSTR(kIOHIDVendorIDKey));
    int pid = GetDevicePropertyInt(device, CFSTR(kIOHIDProductIDKey));
    std::string serial = GetDevicePropertyString(device, CFSTR(kIOHIDSerialNumberKey));

    std::vector<uint8_t> reportData(report, report + reportLength);

    if (g_hid_callback) {
        auto callback = [vid, pid, serial, reportID, reportData](Napi::Env env, Napi::Function jsCallback) {
            Napi::Object eventObj = Napi::Object::New(env);
            eventObj.Set("type", Napi::String::New(env, "report"));
            eventObj.Set("vendorId", Napi::Number::New(env, vid));
            eventObj.Set("productId", Napi::Number::New(env, pid));
            eventObj.Set("serialNumber", Napi::String::New(env, serial));
            eventObj.Set("reportId", Napi::Number::New(env, reportID));

            Napi::Buffer<uint8_t> buffer = Napi::Buffer<uint8_t>::Copy(env, reportData.data(), reportData.size());
            eventObj.Set("data", buffer);

            jsCallback.Call({ eventObj });
        };
        g_hid_callback.NonBlockingCall(callback);
    }
}

static void RunMonitorLoop() {
    @autoreleasepool {
        g_cf_run_loop = CFRunLoopGetCurrent();

        IOHIDManagerRegisterDeviceMatchingCallback(g_hid_manager, MatchCallback, NULL);
        IOHIDManagerRegisterDeviceRemovalCallback(g_hid_manager, RemovalCallback, NULL);
        IOHIDManagerRegisterInputReportCallback(g_hid_manager, ReportCallback, NULL);

        IOHIDManagerScheduleWithRunLoop(g_hid_manager, g_cf_run_loop, kCFRunLoopDefaultMode);

        IOReturn openResult = IOHIDManagerOpen(g_hid_manager, kIOHIDOptionsTypeNone);
        if (openResult != kIOReturnSuccess) {
            std::cerr << "[hid_bridge] Failed to open IOHIDManager: " << openResult << std::endl;
            return;
        }

        CFRunLoopRun();
    }
}

// JS Exports
Napi::Value GetHIDDevices(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    EnsureHIDManagerCreated();

    Napi::Array jsDevices = Napi::Array::New(env);
    CFSetRef deviceSet = IOHIDManagerCopyDevices(g_hid_manager);
    if (deviceSet) {
        CFIndex count = CFSetGetCount(deviceSet);
        std::vector<const void*> devices(count);
        CFSetGetValues(deviceSet, devices.data());

        uint32_t idx = 0;
        for (const void* deviceVal : devices) {
            IOHIDDeviceRef device = (IOHIDDeviceRef)deviceVal;
            int vid = GetDevicePropertyInt(device, CFSTR(kIOHIDVendorIDKey));
            int pid = GetDevicePropertyInt(device, CFSTR(kIOHIDProductIDKey));
            std::string name = GetDevicePropertyString(device, CFSTR(kIOHIDProductKey));
            std::string serial = GetDevicePropertyString(device, CFSTR(kIOHIDSerialNumberKey));
            std::string mfg = GetDevicePropertyString(device, CFSTR(kIOHIDManufacturerKey));
            int usagePage = GetDevicePropertyInt(device, CFSTR(kIOHIDPrimaryUsagePageKey));
            int usage = GetDevicePropertyInt(device, CFSTR(kIOHIDPrimaryUsageKey));

            Napi::Object devObj = Napi::Object::New(env);
            devObj.Set("vendorId", Napi::Number::New(env, vid));
            devObj.Set("productId", Napi::Number::New(env, pid));
            devObj.Set("name", Napi::String::New(env, name));
            devObj.Set("serialNumber", Napi::String::New(env, serial));
            devObj.Set("manufacturer", Napi::String::New(env, mfg));
            devObj.Set("usagePage", Napi::Number::New(env, usagePage));
            devObj.Set("usage", Napi::Number::New(env, usage));

            jsDevices.Set(idx++, devObj);
        }
        CFRelease(deviceSet);
    }

    return jsDevices;
}

Napi::Value StartHIDMonitoring(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsFunction()) {
        Napi::TypeError::New(env, "Callback function required").ThrowAsJavaScriptException();
        return env.Null();
    }

    if (g_hid_callback) {
        g_hid_callback.Release();
        g_hid_callback = nullptr;
    }

    g_hid_callback = Napi::ThreadSafeFunction::New(
        env,
        info[0].As<Napi::Function>(),
        "HIDCallbackResource",
        0,
        1
    );

    EnsureHIDManagerCreated();

    if (!g_cf_run_loop) {
        g_run_loop_thread = std::thread(RunMonitorLoop);
    }

    return Napi::Boolean::New(env, true);
}

Napi::Value StopHIDMonitoring(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();

    if (g_cf_run_loop) {
        CFRunLoopStop(g_cf_run_loop);
        g_cf_run_loop = nullptr;
    }

    if (g_run_loop_thread.joinable()) {
        g_run_loop_thread.join();
    }

    if (g_hid_manager) {
        IOHIDManagerClose(g_hid_manager, kIOHIDOptionsTypeNone);
        CFRelease(g_hid_manager);
        g_hid_manager = nullptr;
    }

    {
        std::lock_guard<std::mutex> lock(g_devices_mutex);
        g_connected_devices.clear();
    }

    if (g_hid_callback) {
        g_hid_callback.Release();
        g_hid_callback = nullptr;
    }

    return Napi::Boolean::New(env, true);
}

Napi::Value WriteHIDReport(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 5) {
        Napi::TypeError::New(env, "Arguments: vendorId, productId, reportType, reportId, dataBuffer").ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }

    int targetVid = info[0].As<Napi::Number>().Int32Value();
    int targetPid = info[1].As<Napi::Number>().Int32Value();
    int reportTypeVal = info[2].As<Napi::Number>().Int32Value(); // 1=Output, 2=Feature
    int reportId = info[3].As<Napi::Number>().Int32Value();

    if (!info[4].IsBuffer() && !info[4].IsTypedArray()) {
        Napi::TypeError::New(env, "Buffer or TypedArray required for report data").ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }

    uint8_t* data = nullptr;
    size_t length = 0;

    if (info[4].IsBuffer()) {
        Napi::Buffer<uint8_t> buf = info[4].As<Napi::Buffer<uint8_t>>();
        data = buf.Data();
        length = buf.Length();
    } else {
        Napi::TypedArray ta = info[4].As<Napi::TypedArray>();
        Napi::ArrayBuffer ab = ta.ArrayBuffer();
        data = (uint8_t*)ab.Data() + ta.ByteOffset();
        length = ta.ByteLength();
    }

    IOHIDReportType type = kIOHIDReportTypeOutput;
    if (reportTypeVal == 2) {
        type = kIOHIDReportTypeFeature;
    } else if (reportTypeVal == 0) {
        type = kIOHIDReportTypeInput;
    }

    IOHIDDeviceRef targetDevice = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_devices_mutex);
        for (auto const& [key, dev] : g_connected_devices) {
            int vid = GetDevicePropertyInt(dev, CFSTR(kIOHIDVendorIDKey));
            int pid = GetDevicePropertyInt(dev, CFSTR(kIOHIDProductIDKey));
            if (vid == targetVid && pid == targetPid) {
                targetDevice = dev;
                break;
            }
        }
    }

    if (!targetDevice) {
        // Fallback: search via active copy if monitor loop is not running yet
        EnsureHIDManagerCreated();
        CFSetRef deviceSet = IOHIDManagerCopyDevices(g_hid_manager);
        if (deviceSet) {
            CFIndex count = CFSetGetCount(deviceSet);
            std::vector<const void*> devices(count);
            CFSetGetValues(deviceSet, devices.data());
            for (const void* deviceVal : devices) {
                IOHIDDeviceRef dev = (IOHIDDeviceRef)deviceVal;
                int vid = GetDevicePropertyInt(dev, CFSTR(kIOHIDVendorIDKey));
                int pid = GetDevicePropertyInt(dev, CFSTR(kIOHIDProductIDKey));
                if (vid == targetVid && pid == targetPid) {
                    targetDevice = dev;
                    break;
                }
            }
            CFRelease(deviceSet);
        }
    }

    if (!targetDevice) {
        return Napi::Boolean::New(env, false);
    }

    IOReturn writeResult = IOHIDDeviceSetReport(
        targetDevice,
        type,
        reportId,
        data,
        length
    );

    return Napi::Boolean::New(env, writeResult == kIOReturnSuccess);
}

void InitHID(Napi::Env env, Napi::Object exports) {
    exports.Set(Napi::String::New(env, "hidGetDevices"), Napi::Function::New(env, GetHIDDevices));
    exports.Set(Napi::String::New(env, "hidStartMonitoring"), Napi::Function::New(env, StartHIDMonitoring));
    exports.Set(Napi::String::New(env, "hidStopMonitoring"), Napi::Function::New(env, StopHIDMonitoring));
    exports.Set(Napi::String::New(env, "hidWriteReport"), Napi::Function::New(env, WriteHIDReport));
}
