#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <IOSurface/IOSurface.h>
#import <CoreVideo/CoreVideo.h>
#import <Syphon/Syphon.h>
#include <napi.h>
#include <mutex>
#include "screencapturekit_bridge.h"

static id<MTLDevice> g_Device = nil;
static id<MTLCommandQueue> g_CommandQueue = nil;

// Syphon Server State
static SyphonMetalServer* g_SyphonServer = nil;
static id<MTLTexture> g_ServerTexture = nil;
static int g_ServerWidth = 0;
static int g_ServerHeight = 0;

// Syphon Client State
static SyphonMetalClient* g_SyphonClient = nil;
static Napi::ThreadSafeFunction g_ClientCallback;
static NSArray* g_ServersList = nil;

static IOSurfaceRef g_ClientSurface = NULL;
static id<MTLTexture> g_ClientTexture = nil;
static int g_ClientWidth = 0;
static int g_ClientHeight = 0;

void InitializeMetal() {
    if (!g_Device) {
        g_Device = MTLCreateSystemDefaultDevice();
        g_CommandQueue = [g_Device newCommandQueue];
    }
}

// Convert NSDictionary to Napi::Object
Napi::Object NSDictionaryToNapiObject(Napi::Env env, NSDictionary* dict) {
    Napi::Object obj = Napi::Object::New(env);
    for (id key in dict) {
        if ([key isKindOfClass:[NSString class]]) {
            id val = [dict objectForKey:key];
            if ([val isKindOfClass:[NSString class]]) {
                obj.Set(Napi::String::New(env, [key UTF8String]), Napi::String::New(env, [val UTF8String]));
            } else if ([val isKindOfClass:[NSNumber class]]) {
                obj.Set(Napi::String::New(env, [key UTF8String]), Napi::Number::New(env, [val doubleValue]));
            }
        }
    }
    return obj;
}

// Convert Napi::Object to NSDictionary
NSDictionary* NapiObjectToNSDictionary(Napi::Object obj) {
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    Napi::Array keys = obj.GetPropertyNames();
    for (uint32_t i = 0; i < keys.Length(); i++) {
        Napi::Value keyVal = keys[i];
        std::string keyStr = keyVal.As<Napi::String>().Utf8Value();
        NSString* nsKey = [NSString stringWithUTF8String:keyStr.c_str()];
        
        Napi::Value val = obj.Get(keyVal);
        if (val.IsString()) {
            [dict setObject:[NSString stringWithUTF8String:val.As<Napi::String>().Utf8Value().c_str()] forKey:nsKey];
        } else if (val.IsNumber()) {
            [dict setObject:[NSNumber numberWithDouble:val.As<Napi::Number>().DoubleValue()] forKey:nsKey];
        }
    }
    return dict;
}

// getServers()
// Returns list of Syphon Servers
Napi::Array GetServers(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    g_ServersList = [[SyphonServerDirectory sharedDirectory] servers];
    Napi::Array arr = Napi::Array::New(env, [g_ServersList count]);
    
    for (NSUInteger i = 0; i < [g_ServersList count]; i++) {
        NSDictionary* dict = [g_ServersList objectAtIndex:i];
        arr.Set(i, NSDictionaryToNapiObject(env, dict));
    }
    return arr;
}

// initServer(name)
Napi::Value InitServer(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    InitializeMetal();
    
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "String expected for name").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    std::string nameStr = info[0].As<Napi::String>().Utf8Value();
    NSString* nsName = [NSString stringWithUTF8String:nameStr.c_str()];
    
    if (g_SyphonServer) {
        [g_SyphonServer stop];
        g_SyphonServer = nil;
    }
    
    g_SyphonServer = [[SyphonMetalServer alloc] initWithName:nsName device:g_Device options:nil];
    
    return Napi::Boolean::New(env, g_SyphonServer != nil);
}

// stopServer()
Napi::Value StopServer(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (g_SyphonServer) {
        [g_SyphonServer stop];
        g_SyphonServer = nil;
    }
    g_ServerTexture = nil;
    g_ServerWidth = 0;
    g_ServerHeight = 0;
    return env.Undefined();
}

// publishFrame(buffer, width, height)
Napi::Value PublishFrame(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_SyphonServer) {
        return Napi::Boolean::New(env, false);
    }
    
    if (info.Length() < 3 || !info[0].IsBuffer() || !info[1].IsNumber() || !info[2].IsNumber()) {
        Napi::TypeError::New(env, "Arguments expected: Buffer (ioSurface), Number (width), Number (height)").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Napi::Buffer<char> buffer = info[0].As<Napi::Buffer<char>>();
    if (buffer.Length() < sizeof(IOSurfaceRef)) {
        Napi::TypeError::New(env, "Invalid buffer length for IOSurfaceRef").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    IOSurfaceRef surface = *reinterpret_cast<IOSurfaceRef*>(buffer.Data());
    int width = info[1].As<Napi::Number>().Int32Value();
    int height = info[2].As<Napi::Number>().Int32Value();
    
    if (!surface || width <= 0 || height <= 0) {
        return Napi::Boolean::New(env, false);
    }
    
    @autoreleasepool {
        MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                       width:width
                                                                                      height:height
                                                                                   mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead;
        
        id<MTLTexture> mtlTexture = [g_Device newTextureWithDescriptor:desc iosurface:surface plane:0];
        if (!mtlTexture) {
            return Napi::Boolean::New(env, false);
        }
        
        id<MTLCommandBuffer> commandBuffer = [g_CommandQueue commandBuffer];
        if (commandBuffer) {
            [g_SyphonServer publishFrameTexture:mtlTexture onCommandBuffer:commandBuffer imageRegion:NSMakeRect(0, 0, width, height) flipped:YES];
            [commandBuffer commit];
        }
    }
    
    return Napi::Boolean::New(env, true);
}

// publishPixelFrame(buffer, width, height)
Napi::Value PublishPixelFrame(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_SyphonServer) {
        return Napi::Boolean::New(env, false);
    }
    
    if (info.Length() < 3 || !info[0].IsBuffer() || !info[1].IsNumber() || !info[2].IsNumber()) {
        Napi::TypeError::New(env, "Arguments expected: Buffer (pixels), Number (width), Number (height)").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Napi::Buffer<char> buffer = info[0].As<Napi::Buffer<char>>();
    int width = info[1].As<Napi::Number>().Int32Value();
    int height = info[2].As<Napi::Number>().Int32Value();
    
    if (width <= 0 || height <= 0) {
        return Napi::Boolean::New(env, false);
    }
    
    if (buffer.Length() < width * height * 4) {
        Napi::TypeError::New(env, "Invalid buffer length for pixel data").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    InitializeMetal();
    
    @autoreleasepool {
        if (!g_ServerTexture || g_ServerWidth != width || g_ServerHeight != height) {
            g_ServerTexture = nil;
            g_ServerWidth = width;
            g_ServerHeight = height;
            
            MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
            desc.usage = MTLTextureUsageShaderRead;
            g_ServerTexture = [g_Device newTextureWithDescriptor:desc];
            if (!g_ServerTexture) {
                return Napi::Boolean::New(env, false);
            }
        }
        
        [g_ServerTexture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                           mipmapLevel:0
                             withBytes:buffer.Data()
                           bytesPerRow:width * 4];
        
        id<MTLCommandBuffer> commandBuffer = [g_CommandQueue commandBuffer];
        if (commandBuffer) {
            [g_SyphonServer publishFrameTexture:g_ServerTexture onCommandBuffer:commandBuffer imageRegion:NSMakeRect(0, 0, width, height) flipped:NO];
            [commandBuffer commit];
        }
    }
    
    return Napi::Boolean::New(env, true);
}

Napi::Value InitClient(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    InitializeMetal();
    
    if (info.Length() < 2 || (!info[0].IsObject() && !info[0].IsString()) || !info[1].IsFunction()) {
        Napi::TypeError::New(env, "Arguments expected: Object/String (serverDescription or UUID), Function (callback)").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Napi::Function cb = info[1].As<Napi::Function>();
    
    NSString* targetUUID = nil;
    if (info[0].IsString()) {
        targetUUID = [NSString stringWithUTF8String:info[0].As<Napi::String>().Utf8Value().c_str()];
    } else if (info[0].IsObject()) {
        Napi::Object obj = info[0].As<Napi::Object>();
        Napi::Value uuidVal = obj.Get("SyphonServerDescriptionUUID");
        if (!uuidVal.IsString()) {
            uuidVal = obj.Get("SyphonServerDescriptionUUIDKey");
        }
        if (uuidVal.IsString()) {
            targetUUID = [NSString stringWithUTF8String:uuidVal.As<Napi::String>().Utf8Value().c_str()];
        }
    }
    
    NSDictionary* description = nil;
    if (targetUUID) {
        if (g_ServersList) {
            for (NSDictionary* dict in g_ServersList) {
                NSString* uuid = [dict objectForKey:SyphonServerDescriptionUUIDKey];
                if ([uuid isEqualToString:targetUUID]) {
                    description = dict;
                    break;
                }
            }
        }
        if (!description) {
            NSArray* currentServers = [[SyphonServerDirectory sharedDirectory] servers];
            for (NSDictionary* dict in currentServers) {
                NSString* uuid = [dict objectForKey:SyphonServerDescriptionUUIDKey];
                if ([uuid isEqualToString:targetUUID]) {
                    description = dict;
                    break;
                }
            }
        }
    }
    
    if (!description && info[0].IsObject()) {
        NSLog(@"[Syphon Bridge] Warning: Server description not found in list, reconstructing...");
        description = NapiObjectToNSDictionary(info[0].As<Napi::Object>());
    }
    
    NSLog(@"[Syphon Bridge] InitClient starting...");
    NSLog(@"[Syphon Bridge] g_Device is: %@", g_Device);
    NSLog(@"[Syphon Bridge] description dictionary is: %@", description);
    
    if (g_SyphonClient) {
        [g_SyphonClient stop];
        g_SyphonClient = nil;
    }
    
    g_ClientCallback = Napi::ThreadSafeFunction::New(
        env,
        cb,
        "SyphonClientCallback",
        0,
        1
    );
    
    g_SyphonClient = [[SyphonMetalClient alloc] initWithServerDescription:description
                                                                   device:g_Device
                                                                  options:nil
                                                          newFrameHandler:^(SyphonMetalClient *client) {
        @autoreleasepool {
            id<MTLTexture> syphonTexture = [client newFrameImage];
            if (!syphonTexture) {
                NSLog(@"[Syphon Bridge] newFrameImage returned nil!");
                return;
            }
            
            int width = (int)syphonTexture.width;
            int height = (int)syphonTexture.height;
            
            if (!g_ClientSurface || g_ClientWidth != width || g_ClientHeight != height) {
                if (g_ClientSurface) {
                    CFRelease(g_ClientSurface);
                    g_ClientSurface = NULL;
                }
                g_ClientTexture = nil;
                
                g_ClientWidth = width;
                g_ClientHeight = height;
                
                NSDictionary *properties = @{
                    (id)kIOSurfaceWidth: @(width),
                    (id)kIOSurfaceHeight: @(height),
                    (id)kIOSurfaceBytesPerElement: @(4),
                    (id)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
                };
                g_ClientSurface = IOSurfaceCreate((CFDictionaryRef)properties);
                if (!g_ClientSurface) {
                    NSLog(@"[Syphon Bridge] Failed to create IOSurface");
                    return;
                }
                
                MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                width:width
                                                                                               height:height
                                                                                            mipmapped:NO];
                desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
                g_ClientTexture = [g_Device newTextureWithDescriptor:desc iosurface:g_ClientSurface plane:0];
                if (!g_ClientTexture) {
                    NSLog(@"[Syphon Bridge] Failed to wrap IOSurface in Metal texture");
                    return;
                }
            }
            
            InitializeMetal();
            id<MTLCommandBuffer> commandBuffer = [g_CommandQueue commandBuffer];
            id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
            [blitEncoder copyFromTexture:syphonTexture
                             sourceSlice:0
                             sourceLevel:0
                            sourceOrigin:MTLOriginMake(0, 0, 0)
                              sourceSize:MTLSizeMake(width, height, 1)
                               toTexture:g_ClientTexture
                        destinationSlice:0
                        destinationLevel:0
                       destinationOrigin:MTLOriginMake(0, 0, 0)];
            [blitEncoder endEncoding];
            [commandBuffer commit];
            [commandBuffer waitUntilCompleted];
            
            // Retain the surface while we pass it to JS process
            CFRetain(g_ClientSurface);
            
            auto callback = [](Napi::Env env, Napi::Function jsCallback, IOSurfaceRef surfaceRef) {
                // Wrap the pointer into an 8-byte Buffer
                Napi::Buffer<IOSurfaceRef> buf = Napi::Buffer<IOSurfaceRef>::New(env, 1);
                *buf.Data() = surfaceRef;
                
                // Set finalizer to release the retained surface once JS garbage collects the Buffer
                buf.AddFinalizer([](Napi::Env env, IOSurfaceRef ref) {
                    if (ref) {
                        CFRelease(ref);
                    }
                }, surfaceRef);
                
                int w = (int)IOSurfaceGetWidth(surfaceRef);
                int h = (int)IOSurfaceGetHeight(surfaceRef);
                
                jsCallback.Call({ buf, Napi::Number::New(env, w), Napi::Number::New(env, h) });
            };
            
            g_ClientCallback.NonBlockingCall(g_ClientSurface, callback);
        }
    }];
    
    BOOL valid = g_SyphonClient != nil && g_SyphonClient.isValid;
    NSLog(@"[Syphon Bridge] InitClient finished. g_SyphonClient: %@, isValid: %s", g_SyphonClient, valid ? "YES" : "NO");
    return Napi::Boolean::New(env, valid);
}

// stopClient()
Napi::Value StopClient(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (g_SyphonClient) {
        [g_SyphonClient stop];
        g_SyphonClient = nil;
    }
    g_ClientCallback.Release();
    
    if (g_ClientSurface) {
        CFRelease(g_ClientSurface);
        g_ClientSurface = NULL;
    }
    g_ClientTexture = nil;
    g_ClientWidth = 0;
    g_ClientHeight = 0;
    
    return env.Undefined();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set(Napi::String::New(env, "getServers"), Napi::Function::New(env, GetServers));
    exports.Set(Napi::String::New(env, "initServer"), Napi::Function::New(env, InitServer));
    exports.Set(Napi::String::New(env, "stopServer"), Napi::Function::New(env, StopServer));
    exports.Set(Napi::String::New(env, "publishFrame"), Napi::Function::New(env, PublishFrame));
    exports.Set(Napi::String::New(env, "publishPixelFrame"), Napi::Function::New(env, PublishPixelFrame));
    exports.Set(Napi::String::New(env, "initClient"), Napi::Function::New(env, InitClient));
    exports.Set(Napi::String::New(env, "stopClient"), Napi::Function::New(env, StopClient));
    
    InitAudioCapture(env, exports);
    
    return exports;
}

NODE_API_MODULE(apple_framework_bridge, Init)
