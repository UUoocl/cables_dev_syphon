#include "input_bridge.h"
#include <napi.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ApplicationServices/ApplicationServices.h>
#include <thread>
#include <mutex>
#include <string>
#include <vector>
#include <unordered_map>
#include <iostream>
#include <sys/time.h>
#include <algorithm>
#include <cctype>

// ====================================================
// Constants & Maps
// ====================================================

// Keycode to standard Cables key names mapping
static const std::unordered_map<int, std::string> keyCodeMap = {
    {0, "a"}, {1, "s"}, {2, "d"}, {3, "f"}, {4, "h"}, {5, "g"}, {6, "z"}, {7, "x"}, {8, "c"}, {9, "v"},
    {11, "b"}, {12, "q"}, {13, "w"}, {14, "e"}, {15, "r"}, {16, "y"}, {17, "t"}, {18, "1"}, {19, "2"},
    {20, "3"}, {21, "4"}, {22, "6"}, {23, "5"}, {24, "="}, {25, "9"}, {26, "7"}, {27, "-"}, {28, "8"},
    {29, "0"}, {30, "]"}, {31, "o"}, {32, "u"}, {33, "["}, {34, "i"}, {35, "p"}, {36, "return"}, {37, "l"},
    {38, "j"}, {39, "'"}, {40, "k"}, {41, ";"}, {42, "\\"}, {43, ","}, {44, "/"}, {45, "n"}, {46, "m"},
    {47, "."}, {48, "tab"}, {49, "space"}, {50, "`"}, {51, "delete"}, {52, "enter"}, {53, "escape"},
    {64, "f17"}, {65, "."}, {67, "*"}, {69, "+"}, {71, "clear"}, {75, "/"}, {76, "enter"}, {78, "-"},
    {79, "f18"}, {80, "f19"}, {81, "="}, {82, "0"}, {83, "1"}, {84, "2"}, {85, "3"}, {86, "4"}, {87, "5"},
    {88, "6"}, {89, "7"}, {90, "f20"}, {91, "8"}, {92, "9"}, {96, "f5"}, {97, "f6"}, {98, "f7"}, {99, "f3"},
    {100, "f8"}, {101, "f9"}, {103, "f11"}, {105, "f13"}, {106, "f16"}, {107, "f14"}, {109, "f10"},
    {111, "f12"}, {113, "f15"}, {115, "home"}, {116, "pageup"}, {117, "delete"}, {118, "f4"}, {119, "end"},
    {120, "f2"}, {121, "pagedown"}, {122, "f1"}, {123, "left"}, {124, "right"}, {125, "down"}, {126, "up"}
};

// Standard key name to CGKeyCode map
static const std::unordered_map<std::string, CGKeyCode> keyToKeyCode = {
    {"a", 0}, {"s", 1}, {"d", 2}, {"f", 3}, {"h", 4}, {"g", 5}, {"z", 6}, {"x", 7}, {"c", 8}, {"v", 9},
    {"b", 11}, {"q", 12}, {"w", 13}, {"e", 14}, {"r", 15}, {"y", 16}, {"t", 17}, {"1", 18}, {"2", 19},
    {"3", 20}, {"4", 21}, {"6", 22}, {"5", 23}, {"=", 24}, {"9", 25}, {"7", 26}, {"-", 27}, {"8", 28},
    {"0", 29}, {"]", 30}, {"o", 31}, {"u", 32}, {"[", 33}, {"i", 34}, {"p", 35}, {"return", 36}, {"l", 37},
    {"j", 38}, {"'", 39}, {"k", 40}, {";", 41}, {"\\", 42}, {",", 43}, {"/", 44}, {"n", 45}, {"m", 46},
    {".", 47}, {"tab", 48}, {"space", 49}, {"`", 50}, {"delete", 51}, {"enter", 76}, {"escape", 53}, {"esc", 53},
    {"f17", 64}, {"clear", 71},
    {"f18", 79}, {"f19", 80}, {"f20", 90}, {"f5", 96}, {"f6", 97}, {"f7", 98}, {"f3", 99},
    {"f8", 100}, {"f9", 101}, {"f11", 103}, {"f13", 105}, {"f16", 106}, {"f14", 107}, {"f10", 109},
    {"f12", 111}, {"f15", 113}, {"home", 115}, {"pageup", 116}, {"pgup", 116}, {"end", 119},
    {"f4", 118}, {"f2", 120}, {"pagedown", 121}, {"pgdn", 121}, {"f1", 122}, {"left", 123}, {"right", 124}, {"down", 125}, {"up", 126}
};

static CGEventFlags parseModifiers(const std::string& modifierStr) {
    CGEventFlags flags = 0;
    std::string lowerStr = modifierStr;
    std::transform(lowerStr.begin(), lowerStr.end(), lowerStr.begin(), ::tolower);

    if (lowerStr.find("cmd") != std::string::npos || lowerStr.find("command") != std::string::npos) {
        flags |= kCGEventFlagMaskCommand;
    }
    if (lowerStr.find("shift") != std::string::npos) {
        flags |= kCGEventFlagMaskShift;
    }
    if (lowerStr.find("alt") != std::string::npos || lowerStr.find("option") != std::string::npos || lowerStr.find("opt") != std::string::npos) {
        flags |= kCGEventFlagMaskAlternate;
    }
    if (lowerStr.find("ctrl") != std::string::npos || lowerStr.find("control") != std::string::npos) {
        flags |= kCGEventFlagMaskControl;
    }

    return flags;
}

// ====================================================
// Mouse Monitoring (Global Event Tap)
// ====================================================

struct MouseEvent {
    std::string type;
    int x;
    int y;
    std::string button;
    bool pressed;
    double dx;
    double dy;
};

static Napi::ThreadSafeFunction g_MouseCallback;
static std::mutex g_MouseMutex;
static CFRunLoopRef g_MouseRunLoop = nullptr;
static CFMachPortRef g_MouseEventTap = nullptr;
static CFRunLoopSourceRef g_MouseRunLoopSource = nullptr;
static bool g_MouseActive = false;
static int g_MouseTargetPps = 20;
static double g_MouseLastMoveTime = 0;

static CGEventRef MouseEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon) {
    std::lock_guard<std::mutex> lock(g_MouseMutex);
    if (!g_MouseActive || !g_MouseCallback) return event;

    CGPoint location = CGEventGetLocation(event);
    MouseEvent ev;
    bool shouldSend = false;

    if (type == kCGEventMouseMoved || type == kCGEventLeftMouseDragged ||
        type == kCGEventRightMouseDragged || type == kCGEventOtherMouseDragged) {
        
        struct timeval tv;
        gettimeofday(&tv, NULL);
        double now = tv.tv_sec + tv.tv_usec / 1000000.0;

        double min_interval = 1.0 / (double)g_MouseTargetPps;
        if (now - g_MouseLastMoveTime >= min_interval) {
            g_MouseLastMoveTime = now;
            ev.type = "mousePosition";
            ev.x = (int)location.x;
            ev.y = (int)location.y;
            shouldSend = true;
        }
    } else if (type == kCGEventLeftMouseDown || type == kCGEventLeftMouseUp ||
               type == kCGEventRightMouseDown || type == kCGEventRightMouseUp ||
               type == kCGEventOtherMouseDown || type == kCGEventOtherMouseUp) {
               
        ev.type = "mouseClick";
        ev.x = (int)location.x;
        ev.y = (int)location.y;
        ev.pressed = (type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown);
        
        int button_number = (int)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
        ev.button = "MB" + std::to_string(button_number + 1);
        shouldSend = true;
    } else if (type == kCGEventScrollWheel) {
        ev.type = "mouseScroll";
        ev.x = (int)location.x;
        ev.y = (int)location.y;
        ev.dy = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1);
        ev.dx = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2);
        shouldSend = true;
    }

    if (shouldSend) {
        auto callback = [ev](Napi::Env env, Napi::Function jsCallback) {
            Napi::Object eventObj = Napi::Object::New(env);
            eventObj.Set("type", Napi::String::New(env, ev.type));

            Napi::Object dataObj = Napi::Object::New(env);
            dataObj.Set("x", Napi::Number::New(env, ev.x));
            dataObj.Set("y", Napi::Number::New(env, ev.y));

            if (ev.type == "mouseClick") {
                dataObj.Set("button", Napi::String::New(env, ev.button));
                dataObj.Set("pressed", Napi::Boolean::New(env, ev.pressed));
            } else if (ev.type == "mouseScroll") {
                dataObj.Set("dx", Napi::Number::New(env, ev.dx));
                dataObj.Set("dy", Napi::Number::New(env, ev.dy));
            }

            eventObj.Set("data", dataObj);
            jsCallback.Call({ eventObj });
        };
        g_MouseCallback.NonBlockingCall(callback);
    }

    return event;
}

static void RunMouseMonitorLoop() {
    @autoreleasepool {
        CGEventMask event_mask =
            (1ULL << kCGEventMouseMoved) |
            (1ULL << kCGEventLeftMouseDown) |
            (1ULL << kCGEventLeftMouseUp) |
            (1ULL << kCGEventLeftMouseDragged) |
            (1ULL << kCGEventRightMouseDown) |
            (1ULL << kCGEventRightMouseUp) |
            (1ULL << kCGEventRightMouseDragged) |
            (1ULL << kCGEventOtherMouseDown) |
            (1ULL << kCGEventOtherMouseUp) |
            (1ULL << kCGEventOtherMouseDragged) |
            (1ULL << kCGEventScrollWheel);

        g_MouseEventTap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
            event_mask,
            MouseEventTapCallback,
            nullptr
        );

        if (!g_MouseEventTap) {
            NSLog(@"[MouseMonitor] Failed to create CGEventTap.");
            return;
        }

        g_MouseRunLoop = CFRunLoopGetCurrent();
        g_MouseRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, g_MouseEventTap, 0);
        CFRunLoopAddSource(g_MouseRunLoop, g_MouseRunLoopSource, kCFRunLoopDefaultMode);
        CGEventTapEnable(g_MouseEventTap, true);

        CFRunLoopRun();
    }
}

Napi::Value StartMouseMonitor(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    std::lock_guard<std::mutex> lock(g_MouseMutex);
    
    if (g_MouseActive) return Napi::Boolean::New(env, true);

    if (info.Length() < 2 || !info[0].IsFunction() || !info[1].IsNumber()) {
        Napi::TypeError::New(env, "Arguments expected: Function (callback), Number (pps)").ThrowAsJavaScriptException();
        return env.Undefined();
    }

    Napi::Function cb = info[0].As<Napi::Function>();
    g_MouseTargetPps = info[1].As<Napi::Number>().Int32Value();
    if (g_MouseTargetPps <= 0) g_MouseTargetPps = 20;

    g_MouseCallback = Napi::ThreadSafeFunction::New(env, cb, "MouseMonitorCallback", 0, 1);
    g_MouseActive = true;
    std::thread(RunMouseMonitorLoop).detach();

    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    if (!g_MouseEventTap) {
        g_MouseActive = false;
        g_MouseCallback.Release();
        g_MouseCallback = Napi::ThreadSafeFunction();
        return Napi::Boolean::New(env, false);
    }

    return Napi::Boolean::New(env, true);
}

Napi::Value StopMouseMonitor(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    std::lock_guard<std::mutex> lock(g_MouseMutex);
    
    if (!g_MouseActive) return Napi::Boolean::New(env, true);

    g_MouseActive = false;

    if (g_MouseRunLoop) {
        CFRunLoopStop(g_MouseRunLoop);
        g_MouseRunLoop = nullptr;
    }
    if (g_MouseEventTap) {
        CGEventTapEnable(g_MouseEventTap, false);
        CFRelease(g_MouseEventTap);
        g_MouseEventTap = nullptr;
    }
    if (g_MouseRunLoopSource) {
        CFRelease(g_MouseRunLoopSource);
        g_MouseRunLoopSource = nullptr;
    }
    if (g_MouseCallback) {
        g_MouseCallback.Release();
        g_MouseCallback = Napi::ThreadSafeFunction();
    }

    return Napi::Boolean::New(env, true);
}

// ====================================================
// Keyboard Monitoring (Global Event Tap)
// ====================================================

struct KeyboardEvent {
    std::string event;
    std::string key;
    std::string modifiers;
    std::string combo;
};

static Napi::ThreadSafeFunction g_KeyboardCallback;
static std::mutex g_KeyboardMutex;
static CFRunLoopRef g_KeyboardRunLoop = nullptr;
static CFMachPortRef g_KeyboardEventTap = nullptr;
static CFRunLoopSourceRef g_KeyboardRunLoopSource = nullptr;
static bool g_KeyboardActive = false;

static bool is_ctrl_pressed = false;
static bool is_alt_pressed = false;
static bool is_shift_pressed = false;
static bool is_cmd_pressed = false;

static CGEventRef KeyboardEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* refcon) {
    std::lock_guard<std::mutex> lock(g_KeyboardMutex);
    if (!g_KeyboardActive || !g_KeyboardCallback) return event;

    if (type == kCGEventFlagsChanged) {
        CGEventFlags flags = CGEventGetFlags(event);
        is_ctrl_pressed = (flags & kCGEventFlagMaskControl) != 0;
        is_alt_pressed = (flags & kCGEventFlagMaskAlternate) != 0;
        is_shift_pressed = (flags & kCGEventFlagMaskShift) != 0;
        is_cmd_pressed = (flags & kCGEventFlagMaskCommand) != 0;
    } else if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        int64_t key_code = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        
        auto it = keyCodeMap.find((int)key_code);
        std::string key_str = (it != keyCodeMap.end()) ? it->second : "Key_" + std::to_string(key_code);

        std::vector<std::string> mod_parts;
        if (is_ctrl_pressed) mod_parts.push_back("ctrl");
        if (is_alt_pressed) mod_parts.push_back("alt");
        if (is_shift_pressed) mod_parts.push_back("shift");
        if (is_cmd_pressed) mod_parts.push_back("cmd");

        std::string modifiers_str = "";
        for (size_t i = 0; i < mod_parts.size(); ++i) {
            if (i > 0) modifiers_str += " + ";
            modifiers_str += mod_parts[i];
        }

        std::string combo_str = modifiers_str;
        if (!combo_str.empty()) {
            combo_str += " + " + key_str;
        } else {
            combo_str = key_str;
        }

        KeyboardEvent ev;
        ev.event = (type == kCGEventKeyDown) ? "press" : "release";
        ev.key = key_str;
        ev.modifiers = modifiers_str;
        ev.combo = combo_str;

        auto callback = [ev](Napi::Env env, Napi::Function jsCallback) {
            Napi::Object eventObj = Napi::Object::New(env);
            eventObj.Set("event", Napi::String::New(env, ev.event));
            eventObj.Set("key", Napi::String::New(env, ev.key));
            eventObj.Set("modifiers", Napi::String::New(env, ev.modifiers));
            eventObj.Set("combo", Napi::String::New(env, ev.combo));
            jsCallback.Call({ eventObj });
        };
        g_KeyboardCallback.NonBlockingCall(callback);
    }

    return event;
}

static void RunKeyboardMonitorLoop() {
    @autoreleasepool {
        CGEventMask event_mask =
            (1ULL << kCGEventKeyDown) |
            (1ULL << kCGEventKeyUp) |
            (1ULL << kCGEventFlagsChanged);

        g_KeyboardEventTap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
            event_mask,
            KeyboardEventTapCallback,
            nullptr
        );

        if (!g_KeyboardEventTap) {
            NSLog(@"[KeyboardMonitor] Failed to create CGEventTap.");
            return;
        }

        g_KeyboardRunLoop = CFRunLoopGetCurrent();
        g_KeyboardRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, g_KeyboardEventTap, 0);
        CFRunLoopAddSource(g_KeyboardRunLoop, g_KeyboardRunLoopSource, kCFRunLoopDefaultMode);
        CGEventTapEnable(g_KeyboardEventTap, true);

        CFRunLoopRun();
    }
}

Napi::Value StartKeyboardMonitor(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    std::lock_guard<std::mutex> lock(g_KeyboardMutex);
    
    if (g_KeyboardActive) return Napi::Boolean::New(env, true);

    if (info.Length() < 1 || !info[0].IsFunction()) {
        Napi::TypeError::New(env, "Argument expected: Function (callback)").ThrowAsJavaScriptException();
        return env.Undefined();
    }

    Napi::Function cb = info[0].As<Napi::Function>();
    g_KeyboardCallback = Napi::ThreadSafeFunction::New(env, cb, "KeyboardMonitorCallback", 0, 1);
    g_KeyboardActive = true;
    std::thread(RunKeyboardMonitorLoop).detach();

    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    if (!g_KeyboardEventTap) {
        g_KeyboardActive = false;
        g_KeyboardCallback.Release();
        g_KeyboardCallback = Napi::ThreadSafeFunction();
        return Napi::Boolean::New(env, false);
    }

    return Napi::Boolean::New(env, true);
}

Napi::Value StopKeyboardMonitor(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    std::lock_guard<std::mutex> lock(g_KeyboardMutex);
    
    if (!g_KeyboardActive) return Napi::Boolean::New(env, true);

    g_KeyboardActive = false;

    if (g_KeyboardRunLoop) {
        CFRunLoopStop(g_KeyboardRunLoop);
        g_KeyboardRunLoop = nullptr;
    }
    if (g_KeyboardEventTap) {
        CGEventTapEnable(g_KeyboardEventTap, false);
        CFRelease(g_KeyboardEventTap);
        g_KeyboardEventTap = nullptr;
    }
    if (g_KeyboardRunLoopSource) {
        CFRelease(g_KeyboardRunLoopSource);
        g_KeyboardRunLoopSource = nullptr;
    }
    if (g_KeyboardCallback) {
        g_KeyboardCallback.Release();
        g_KeyboardCallback = Napi::ThreadSafeFunction();
    }

    return Napi::Boolean::New(env, true);
}

// ====================================================
// Mouse Controller (Emitting mouse actions)
// ====================================================

Napi::Value EmitMouseAction(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1 || !info[0].IsObject()) {
        Napi::TypeError::New(env, "Argument must be an object").ThrowAsJavaScriptException();
        return env.Undefined();
    }

    Napi::Object obj = info[0].As<Napi::Object>();

    double target_x = 0;
    double target_y = 0;
    bool has_x = false;
    bool has_y = false;

    if (obj.Has("x")) {
        Napi::Value x_val = obj.Get("x");
        if (x_val.IsNumber()) {
            target_x = x_val.As<Napi::Number>().DoubleValue();
            has_x = true;
        }
    }
    if (obj.Has("y")) {
        Napi::Value y_val = obj.Get("y");
        if (y_val.IsNumber()) {
            target_y = y_val.As<Napi::Number>().DoubleValue();
            has_y = true;
        }
    }

    CGPoint current_pos = CGPointZero;
    CGEventRef current_event = CGEventCreate(nullptr);
    if (current_event) {
        current_pos = CGEventGetLocation(current_event);
        CFRelease(current_event);
    }

    if (!has_x) target_x = current_pos.x;
    if (!has_y) target_y = current_pos.y;
    CGPoint target_pos = CGPointMake(target_x, target_y);

    std::string button_str = "";
    if (obj.Has("button")) {
        Napi::Value btn_val = obj.Get("button");
        if (btn_val.IsString()) {
            button_str = btn_val.As<Napi::String>().Utf8Value();
        }
    }

    std::string action_str = "";
    if (obj.Has("action")) {
        Napi::Value act_val = obj.Get("action");
        if (act_val.IsString()) {
            action_str = act_val.As<Napi::String>().Utf8Value();
        }
    }

    double scroll_x = 0;
    double scroll_y = 0;
    if (obj.Has("scrollX")) {
        Napi::Value sx_val = obj.Get("scrollX");
        if (sx_val.IsNumber()) scroll_x = sx_val.As<Napi::Number>().DoubleValue();
    }
    if (obj.Has("scrollY")) {
        Napi::Value sy_val = obj.Get("scrollY");
        if (sy_val.IsNumber()) scroll_y = sy_val.As<Napi::Number>().DoubleValue();
    }

    // Emit Scroll
    if (scroll_x != 0 || scroll_y != 0) {
        CGEventRef scroll_event = CGEventCreateScrollWheelEvent(
            nullptr, kCGScrollEventUnitLine, 2, (int32_t)scroll_y, (int32_t)scroll_x
        );
        if (scroll_event) {
            CGEventPost(kCGHIDEventTap, scroll_event);
            CFRelease(scroll_event);
        } else {
            Napi::Error::New(env, "Failed to create CGEvent scroll wheel event").ThrowAsJavaScriptException();
            return env.Undefined();
        }
    }

    // Emit Mouse Event
    if (!action_str.empty() || has_x || has_y) {
        CGMouseButton cg_button = kCGMouseButtonLeft;
        CGEventType down_type = kCGEventLeftMouseDown;
        CGEventType up_type = kCGEventLeftMouseUp;
        CGEventType drag_type = kCGEventLeftMouseDragged;

        if (button_str == "right") {
            cg_button = kCGMouseButtonRight;
            down_type = kCGEventRightMouseDown;
            up_type = kCGEventRightMouseUp;
            drag_type = kCGEventRightMouseDragged;
        } else if (button_str == "middle") {
            cg_button = kCGMouseButtonCenter;
            down_type = kCGEventOtherMouseDown;
            up_type = kCGEventOtherMouseUp;
            drag_type = kCGEventOtherMouseDragged;
        }

        CGEventRef event = nullptr;

        if (action_str == "down") {
            event = CGEventCreateMouseEvent(nullptr, down_type, target_pos, cg_button);
        } else if (action_str == "up") {
            event = CGEventCreateMouseEvent(nullptr, up_type, target_pos, cg_button);
        } else if (action_str == "drag") {
            event = CGEventCreateMouseEvent(nullptr, drag_type, target_pos, cg_button);
        } else if (action_str == "move" || (action_str.empty() && (has_x || has_y))) {
            event = CGEventCreateMouseEvent(nullptr, kCGEventMouseMoved, target_pos, kCGMouseButtonLeft);
        }

        if (event) {
            CGEventPost(kCGHIDEventTap, event);
            CFRelease(event);
        } else if (!action_str.empty()) {
            Napi::Error::New(env, "Failed to create CGEvent mouse event").ThrowAsJavaScriptException();
            return env.Undefined();
        }
    }

    Napi::Object result = Napi::Object::New(env);
    result.Set("x", Napi::Number::New(env, target_pos.x));
    result.Set("y", Napi::Number::New(env, target_pos.y));
    if (!button_str.empty()) result.Set("button", Napi::String::New(env, button_str));
    if (!action_str.empty()) result.Set("action", Napi::String::New(env, action_str));
    if (scroll_x != 0) result.Set("scrollX", Napi::Number::New(env, scroll_x));
    if (scroll_y != 0) result.Set("scrollY", Napi::Number::New(env, scroll_y));

    return result;
}

// ====================================================
// Keyboard Controller (Emitting keystrokes)
// ====================================================

Napi::Value EmitKeyboardAction(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1 || !info[0].IsObject()) {
        Napi::TypeError::New(env, "Argument must be an object").ThrowAsJavaScriptException();
        return env.Undefined();
    }

    Napi::Object obj = info[0].As<Napi::Object>();

    if (!obj.Has("key")) {
        Napi::TypeError::New(env, "Key must be specified in the object").ThrowAsJavaScriptException();
        return env.Undefined();
    }

    std::string key_str = obj.Get("key").As<Napi::String>().Utf8Value();
    std::string normalized_key = key_str;
    std::transform(normalized_key.begin(), normalized_key.end(), normalized_key.begin(), ::tolower);

    // Trim whitespace
    normalized_key.erase(normalized_key.begin(), std::find_if(normalized_key.begin(), normalized_key.end(), [](unsigned char ch) {
        return !std::isspace(ch);
    }));
    normalized_key.erase(std::find_if(normalized_key.rbegin(), normalized_key.rend(), [](unsigned char ch) {
        return !std::isspace(ch);
    }).base(), normalized_key.end());

    auto it = keyToKeyCode.find(normalized_key);
    if (it == keyToKeyCode.end()) {
        std::string err_msg = "Unknown key: '" + key_str + "'";
        Napi::Error::New(env, err_msg.c_str()).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    CGKeyCode key_code = it->second;

    std::string modifiers_str = "";
    if (obj.Has("modifiers")) {
        Napi::Value mods_val = obj.Get("modifiers");
        if (mods_val.IsString()) {
            modifiers_str = mods_val.As<Napi::String>().Utf8Value();
        }
    }

    CGEventFlags flags = parseModifiers(modifiers_str);

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGEventRef key_down_event = CGEventCreateKeyboardEvent(source, key_code, true);
    if (!key_down_event) {
        if (source) CFRelease(source);
        Napi::Error::New(env, "Failed to create CGEvent keyDown").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    CGEventSetFlags(key_down_event, flags);
    CGEventPost(kCGHIDEventTap, key_down_event);
    CFRelease(key_down_event);

    CGEventRef key_up_event = CGEventCreateKeyboardEvent(source, key_code, false);
    if (!key_up_event) {
        if (source) CFRelease(source);
        Napi::Error::New(env, "Failed to create CGEvent keyUp").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    CGEventSetFlags(key_up_event, flags);
    CGEventPost(kCGHIDEventTap, key_up_event);
    CFRelease(key_up_event);

    if (source) CFRelease(source);

    std::vector<std::string> combo_parts;
    std::string lower_mods = modifiers_str;
    std::transform(lower_mods.begin(), lower_mods.end(), lower_mods.begin(), ::tolower);

    if (lower_mods.find("ctrl") != std::string::npos || lower_mods.find("control") != std::string::npos) combo_parts.push_back("ctrl");
    if (lower_mods.find("alt") != std::string::npos || lower_mods.find("option") != std::string::npos || lower_mods.find("opt") != std::string::npos) combo_parts.push_back("alt");
    if (lower_mods.find("shift") != std::string::npos) combo_parts.push_back("shift");
    if (lower_mods.find("cmd") != std::string::npos || lower_mods.find("command") != std::string::npos) combo_parts.push_back("cmd");
    combo_parts.push_back(normalized_key);

    std::string combo_str = "";
    for (size_t i = 0; i < combo_parts.size(); ++i) {
        if (i > 0) combo_str += " + ";
        combo_str += combo_parts[i];
    }

    Napi::Object result = Napi::Object::New(env);
    result.Set("combo", Napi::String::New(env, combo_str));
    return result;
}

void InitInput(Napi::Env env, Napi::Object exports) {
    exports.Set(Napi::String::New(env, "startMouseMonitor"), Napi::Function::New(env, StartMouseMonitor));
    exports.Set(Napi::String::New(env, "stopMouseMonitor"), Napi::Function::New(env, StopMouseMonitor));
    exports.Set(Napi::String::New(env, "startKeyboardMonitor"), Napi::Function::New(env, StartKeyboardMonitor));
    exports.Set(Napi::String::New(env, "stopKeyboardMonitor"), Napi::Function::New(env, StopKeyboardMonitor));
    exports.Set(Napi::String::New(env, "emitMouseAction"), Napi::Function::New(env, EmitMouseAction));
    exports.Set(Napi::String::New(env, "emitKeyboardAction"), Napi::Function::New(env, EmitKeyboardAction));
}
