#include "uvc_bridge.h"
#import <Foundation/Foundation.h>
#import "UVCController.h"
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <chrono>
#include <mutex>

struct UvcPollData {
    std::string jsonPayload;
};

static Napi::ThreadSafeFunction g_uvc_ts_fn = nullptr;
static std::atomic<bool> g_uvc_polling(false);
static int g_uvc_target_device_index = 0;
static double g_uvc_poll_rate_pps = 10.0;
static std::mutex g_uvc_mutex;
static NSArray<UVCController*>* g_cached_controllers = nil;

// Convert UVCValue to Napi::Value
static Napi::Value NapiValueFromUVCValue(Napi::Env env, UVCValue* val) {
    if (!val) return env.Null();
    NSString* str = [val stringValue];
    if (!str) return env.Null();
    
    if ([str hasPrefix:@"{"] && [str hasSuffix:@"}"]) {
        Napi::Object obj = Napi::Object::New(env);
        NSString* inner = [str substringWithRange:NSMakeRange(1, str.length - 2)];
        NSArray* parts = [inner componentsSeparatedByString:@","];
        for (NSString* part in parts) {
            NSArray* kv = [part componentsSeparatedByString:@"="];
            if (kv.count == 2) {
                NSString* k = [kv[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString* v = [kv[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                double d = [v doubleValue];
                obj.Set([k UTF8String], d);
            }
        }
        return obj;
    }
    
    NSScanner* scanner = [NSScanner scannerWithString:str];
    double doubleVal = 0;
    if ([scanner scanDouble:&doubleVal] && [scanner isAtEnd]) {
        return Napi::Number::New(env, doubleVal);
    }
    
    return Napi::String::New(env, [str UTF8String]);
}

// Convert UVCValue to Foundation JSON object
static id JsonObjectFromUVCValue(UVCValue* val) {
    if (!val) return [NSNull null];
    NSString* str = [val stringValue];
    if (!str) return [NSNull null];
    
    if ([str hasPrefix:@"{"] && [str hasSuffix:@"}"]) {
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        NSString* inner = [str substringWithRange:NSMakeRange(1, str.length - 2)];
        NSArray* parts = [inner componentsSeparatedByString:@","];
        for (NSString* part in parts) {
            NSArray* kv = [part componentsSeparatedByString:@"="];
            if (kv.count == 2) {
                NSString* k = [kv[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString* v = [kv[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                double d = [v doubleValue];
                dict[k] = @(d);
            }
        }
        return dict;
    }
    
    NSScanner* scanner = [NSScanner scannerWithString:str];
    double doubleVal = 0;
    if ([scanner scanDouble:&doubleVal] && [scanner isAtEnd]) {
        return @(doubleVal);
    }
    
    return str;
}

// Format incoming JS value to CString format acceptable to UVCControl
static NSString* FormatValueToString(Napi::Value val) {
    if (val.IsNumber()) {
        return [NSString stringWithFormat:@"%f", val.As<Napi::Number>().DoubleValue()];
    } else if (val.IsBoolean()) {
        return val.As<Napi::Boolean>().Value() ? @"1" : @"0";
    } else if (val.IsString()) {
        return [NSString stringWithUTF8String:val.As<Napi::String>().Utf8Value().c_str()];
    } else if (val.IsObject() && !val.IsArray()) {
        Napi::Object obj = val.As<Napi::Object>();
        Napi::Array props = obj.GetPropertyNames();
        NSMutableArray* parts = [NSMutableArray array];
        for (uint32_t i = 0; i < props.Length(); i++) {
            Napi::Value key = props.Get(i);
            std::string keyStr = key.As<Napi::String>().Utf8Value();
            Napi::Value subVal = obj.Get(keyStr);
            if (subVal.IsNumber()) {
                [parts addObject:[NSString stringWithFormat:@"%f", subVal.As<Napi::Number>().DoubleValue()]];
            } else {
                [parts addObject:[NSString stringWithUTF8String:subVal.ToString().Utf8Value().c_str()]];
            }
        }
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@","]];
    } else if (val.IsArray()) {
        Napi::Array arr = val.As<Napi::Array>();
        NSMutableArray* parts = [NSMutableArray array];
        for (uint32_t i = 0; i < arr.Length(); i++) {
            Napi::Value item = arr.Get(i);
            if (item.IsNumber()) {
                [parts addObject:[NSString stringWithFormat:@"%f", item.As<Napi::Number>().DoubleValue()]];
            } else {
                [parts addObject:[NSString stringWithUTF8String:item.ToString().Utf8Value().c_str()]];
            }
        }
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@","]];
    }
    return @"0";
}

// Helper to get device by index with caching
static UVCController* GetDeviceByIndex(int index) {
    std::lock_guard<std::mutex> lock(g_uvc_mutex);
    if (g_cached_controllers == nil) {
        g_cached_controllers = [UVCController uvcControllers];
    }
    if (g_cached_controllers != nil && index >= 0 && index < (int)g_cached_controllers.count) {
        UVCController* ctrl = g_cached_controllers[index];
        if (![ctrl isInterfaceOpen]) {
            [ctrl setIsInterfaceOpen:YES];
        }
        return ctrl;
    }
    return nil;
}

// uvcGetDevices() -> Array of objects (Forces a fresh scan of USB bus)
Napi::Value UvcGetDevices(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Napi::Array results = Napi::Array::New(env);
    
    @autoreleasepool {
        std::lock_guard<std::mutex> lock(g_uvc_mutex);
        g_cached_controllers = [UVCController uvcControllers];
        if (g_cached_controllers != nil) {
            uint32_t i = 0;
            for (UVCController* ctrl in g_cached_controllers) {
                Napi::Object devObj = Napi::Object::New(env);
                NSString* name = [ctrl deviceName];
                devObj.Set("name", name ? [name UTF8String] : "Unknown UVC Camera");
                devObj.Set("index", (double)i);
                devObj.Set("vendorId", (double)[ctrl vendorId]);
                devObj.Set("productId", (double)[ctrl productId]);
                devObj.Set("locationId", (double)[ctrl locationId]);
                devObj.Set("uvcVersion", (double)[ctrl uvcVersion]);
                results.Set(i++, devObj);
            }
        }
    }
    return results;
}

// uvcGetControls(deviceIndex) -> Array of control metadata objects
Napi::Value UvcGetControls(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    int deviceIndex = info.Length() > 0 && info[0].IsNumber() ? info[0].As<Napi::Number>().Int32Value() : 0;
    
    Napi::Array results = Napi::Array::New(env);
    
    @autoreleasepool {
        UVCController* device = GetDeviceByIndex(deviceIndex);
        if (!device) return results;
        
        NSArray* controlNames = [UVCController controlStrings];
        uint32_t idx = 0;
        for (NSString* name in controlNames) {
            UVCControl* ctrl = [device controlWithName:name];
            if (ctrl) {
                Napi::Object meta = Napi::Object::New(env);
                meta.Set("name", [name UTF8String]);
                meta.Set("supportsGet", (bool)[ctrl supportsGetValue]);
                meta.Set("supportsSet", (bool)[ctrl supportsSetValue]);
                meta.Set("hasRange", (bool)[ctrl hasRange]);
                meta.Set("hasStepSize", (bool)[ctrl hasStepSize]);
                meta.Set("hasDefaultValue", (bool)[ctrl hasDefaultValue]);
                
                if ([ctrl supportsGetValue]) {
                    UVCValue* val = [ctrl currentValue];
                    if (val) meta.Set("current-value", NapiValueFromUVCValue(env, val));
                }
                if ([ctrl hasRange]) {
                    UVCValue* minV = [ctrl minimum];
                    UVCValue* maxV = [ctrl maximum];
                    if (minV) meta.Set("minimum", NapiValueFromUVCValue(env, minV));
                    if (maxV) meta.Set("maximum", NapiValueFromUVCValue(env, maxV));
                }
                if ([ctrl hasStepSize]) {
                    UVCValue* stepV = [ctrl stepSize];
                    if (stepV) meta.Set("step-size", NapiValueFromUVCValue(env, stepV));
                }
                if ([ctrl hasDefaultValue]) {
                    UVCValue* defV = [ctrl defaultValue];
                    if (defV) meta.Set("default-value", NapiValueFromUVCValue(env, defV));
                }
                results.Set(idx++, meta);
            }
        }
    }
    return results;
}

// uvcGetControlValue(deviceIndex, controlName) -> Value
Napi::Value UvcGetControlValue(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "deviceIndex (number) and controlName (string) required").ThrowAsJavaScriptException();
        return env.Null();
    }
    
    int deviceIndex = info[0].As<Napi::Number>().Int32Value();
    std::string controlNameStr = info[1].As<Napi::String>().Utf8Value();
    
    @autoreleasepool {
        UVCController* device = GetDeviceByIndex(deviceIndex);
        if (!device) return env.Null();
        
        NSString* name = [NSString stringWithUTF8String:controlNameStr.c_str()];
        UVCControl* ctrl = [device controlWithName:name];
        if (!ctrl || ![ctrl supportsGetValue]) return env.Null();
        
        UVCValue* val = [ctrl currentValue];
        return NapiValueFromUVCValue(env, val);
    }
}

// uvcSetControlValue(deviceIndex, controlName, value) -> Boolean
Napi::Value UvcSetControlValue(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "deviceIndex (number), controlName (string), and value required").ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }
    
    int deviceIndex = info[0].As<Napi::Number>().Int32Value();
    std::string controlNameStr = info[1].As<Napi::String>().Utf8Value();
    Napi::Value value = info[2];
    
    @autoreleasepool {
        UVCController* device = GetDeviceByIndex(deviceIndex);
        if (!device) return Napi::Boolean::New(env, false);
        
        NSString* name = [NSString stringWithUTF8String:controlNameStr.c_str()];
        UVCControl* ctrl = [device controlWithName:name];
        if (!ctrl || ![ctrl supportsSetValue]) return Napi::Boolean::New(env, false);
        
        NSString* valStr = FormatValueToString(value);
        BOOL scanned = [ctrl setCurrentValueFromCString:[valStr UTF8String] flags:kUVCTypeScanFlagShowWarnings];
        if (scanned) {
            BOOL written = [ctrl writeFromCurrentValue];
            return Napi::Boolean::New(env, (bool)written);
        }
        return Napi::Boolean::New(env, false);
    }
}

// uvcResetControlValue(deviceIndex, controlName) -> Boolean
Napi::Value UvcResetControlValue(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "deviceIndex (number) and controlName (string) required").ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }
    
    int deviceIndex = info[0].As<Napi::Number>().Int32Value();
    std::string controlNameStr = info[1].As<Napi::String>().Utf8Value();
    
    @autoreleasepool {
        UVCController* device = GetDeviceByIndex(deviceIndex);
        if (!device) return Napi::Boolean::New(env, false);
        
        NSString* name = [NSString stringWithUTF8String:controlNameStr.c_str()];
        UVCControl* ctrl = [device controlWithName:name];
        if (!ctrl) return Napi::Boolean::New(env, false);
        
        BOOL reset = [ctrl resetToDefaultValue];
        return Napi::Boolean::New(env, (bool)reset);
    }
}

// Threadsafe JS callback invoker for background polling
static void CallUvcJsCallback(Napi::Env env, Napi::Function jsCallback, UvcPollData* data) {
    if (data) {
        if (env != nullptr && jsCallback != nullptr) {
            Napi::String jsonStr = Napi::String::New(env, data->jsonPayload);
            jsCallback.Call({ jsonStr });
        }
        delete data;
    }
}

// Background polling loop (Non-blocking, cached device, lightweight)
static void UvcPollingWorker() {
    int devIdx = g_uvc_target_device_index;
    UVCController* device = GetDeviceByIndex(devIdx);
    if (!device) {
        g_uvc_polling.store(false);
        return;
    }
    
    NSArray* controlNames = [UVCController controlStrings];
    
    while (g_uvc_polling.load()) {
        auto startTime = std::chrono::steady_clock::now();
        
        @autoreleasepool {
            if (device && [device isInterfaceOpen]) {
                NSMutableArray* controlArray = [NSMutableArray array];
                
                for (NSString* name in controlNames) {
                    UVCControl* ctrl = [device controlWithName:name];
                    if (ctrl) {
                        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
                        dict[@"name"] = name;
                        dict[@"supportsGet"] = @([ctrl supportsGetValue]);
                        dict[@"supportsSet"] = @([ctrl supportsSetValue]);
                        dict[@"hasRange"] = @([ctrl hasRange]);
                        dict[@"hasStepSize"] = @([ctrl hasStepSize]);
                        dict[@"hasDefaultValue"] = @([ctrl hasDefaultValue]);
                        
                        if ([ctrl supportsGetValue]) {
                            UVCValue* val = [ctrl currentValue];
                            if (val) dict[@"current-value"] = JsonObjectFromUVCValue(val);
                        }
                        if ([ctrl hasRange]) {
                            UVCValue* minV = [ctrl minimum];
                            UVCValue* maxV = [ctrl maximum];
                            if (minV) dict[@"minimum"] = JsonObjectFromUVCValue(minV);
                            if (maxV) dict[@"maximum"] = JsonObjectFromUVCValue(maxV);
                        }
                        if ([ctrl hasStepSize]) {
                            UVCValue* stepV = [ctrl stepSize];
                            if (stepV) dict[@"step-size"] = JsonObjectFromUVCValue(stepV);
                        }
                        if ([ctrl hasDefaultValue]) {
                            UVCValue* defV = [ctrl defaultValue];
                            if (defV) dict[@"default-value"] = JsonObjectFromUVCValue(defV);
                        }
                        [controlArray addObject:dict];
                    }
                }
                
                NSDictionary* payload = @{
                    @"type": @"uvc_poll",
                    @"deviceIndex": @(devIdx),
                    @"deviceName": [device deviceName] ?: @"Unknown",
                    @"data": controlArray
                };
                
                NSData* jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
                if (jsonData && g_uvc_ts_fn != nullptr) {
                    NSString* jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    UvcPollData* pollData = new UvcPollData();
                    pollData->jsonPayload = [jsonStr UTF8String];
                    
                    napi_status status = g_uvc_ts_fn.NonBlockingCall(pollData, CallUvcJsCallback);
                    if (status != napi_ok) {
                        delete pollData;
                    }
                }
            }
        }
        
        int intervalMs = (int)(1000.0 / std::max(0.1, g_uvc_poll_rate_pps));
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startTime).count();
        int sleepMs = std::max(5, intervalMs - (int)elapsed);
        std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
    }
}

// uvcStartPolling(deviceIndex, pollRate, callback) -> Boolean
Napi::Value UvcStartPolling(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsNumber() || !info[2].IsFunction()) {
        Napi::TypeError::New(env, "deviceIndex (number), pollRate (number), and callback (function) required").ThrowAsJavaScriptException();
        return Napi::Boolean::New(env, false);
    }
    
    int deviceIndex = info[0].As<Napi::Number>().Int32Value();
    double pollRate = info[1].As<Napi::Number>().DoubleValue();
    Napi::Function callback = info[2].As<Napi::Function>();
    
    // Stop existing polling thread
    if (g_uvc_polling.load()) {
        g_uvc_polling.store(false);
    }
    if (g_uvc_ts_fn != nullptr) {
        g_uvc_ts_fn.Release();
        g_uvc_ts_fn = nullptr;
    }
    
    g_uvc_target_device_index = deviceIndex;
    g_uvc_poll_rate_pps = (pollRate > 0 && pollRate <= 60.0) ? pollRate : 10.0;
    
    g_uvc_ts_fn = Napi::ThreadSafeFunction::New(
        env,
        callback,
        "UvcPollingCallback",
        0,
        1
    );
    
    g_uvc_polling.store(true);
    std::thread(UvcPollingWorker).detach();
    
    return Napi::Boolean::New(env, true);
}

// uvcStopPolling() -> Boolean
Napi::Value UvcStopPolling(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (g_uvc_polling.load()) {
        g_uvc_polling.store(false);
    }
    if (g_uvc_ts_fn != nullptr) {
        g_uvc_ts_fn.Release();
        g_uvc_ts_fn = nullptr;
    }
    return Napi::Boolean::New(env, true);
}

void InitUVC(Napi::Env env, Napi::Object exports) {
    exports.Set(Napi::String::New(env, "uvcGetDevices"), Napi::Function::New(env, UvcGetDevices));
    exports.Set(Napi::String::New(env, "uvcGetControls"), Napi::Function::New(env, UvcGetControls));
    exports.Set(Napi::String::New(env, "uvcGetControlValue"), Napi::Function::New(env, UvcGetControlValue));
    exports.Set(Napi::String::New(env, "uvcSetControlValue"), Napi::Function::New(env, UvcSetControlValue));
    exports.Set(Napi::String::New(env, "uvcResetControlValue"), Napi::Function::New(env, UvcResetControlValue));
    exports.Set(Napi::String::New(env, "uvcStartPolling"), Napi::Function::New(env, UvcStartPolling));
    exports.Set(Napi::String::New(env, "uvcStopPolling"), Napi::Function::New(env, UvcStopPolling));
}
