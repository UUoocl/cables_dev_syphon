#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <AppKit/AppKit.h>
#include <napi.h>
#include <vector>
#include <mutex>
#include "screencapturekit_bridge.h"

static SCStream *g_AudioStream = nil;
static id g_AudioDelegate = nil;
static dispatch_queue_t g_AudioQueue = nil;
static Napi::ThreadSafeFunction g_AudioCallback;
static std::mutex g_AudioCallbackMutex;
static bool g_AudioCaptureActive = false;

@interface AudioCaptureDelegate : NSObject <SCStreamOutput>
@end

@implementation AudioCaptureDelegate

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    // NSLog(@"[Audio Capture Delegate] didOutputSampleBuffer called, type: %ld", (long)type);
    if (type == SCStreamOutputTypeAudio) {
        @autoreleasepool {
            CMAudioFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
            if (!formatDesc) {
                NSLog(@"[Audio Capture Delegate] CMAudioFormatDescriptionRef is null");
                return;
            }
            const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
            if (!asbd) {
                NSLog(@"[Audio Capture Delegate] AudioStreamBasicDescription is null");
                return;
            }
            
            if (asbd->mFormatID != kAudioFormatLinearPCM) {
                NSLog(@"[Audio Capture Delegate] Format is not Linear PCM: %u", (unsigned int)asbd->mFormatID);
                return;
            }
            
            size_t bufferListSizeNeeded = 0;
            OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                &bufferListSizeNeeded,
                NULL,
                0,
                NULL,
                NULL,
                kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                NULL
            );
            
            if (status != noErr || bufferListSizeNeeded == 0) {
                NSLog(@"[Audio Capture Delegate] GetAudioBufferList size query failed: %d", (int)status);
                return;
            }
            
            AudioBufferList *audioBufferList = (AudioBufferList *)malloc(bufferListSizeNeeded);
            if (!audioBufferList) {
                NSLog(@"[Audio Capture Delegate] malloc failed for size: %zu", bufferListSizeNeeded);
                return;
            }
            
            CMBlockBufferRef blockBuffer = NULL;
            status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                NULL,
                audioBufferList,
                bufferListSizeNeeded,
                NULL,
                NULL,
                kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                &blockBuffer
            );
            
            if (status != noErr || !blockBuffer) {
                NSLog(@"[Audio Capture Delegate] GetAudioBufferList failed: %d", (int)status);
                free(audioBufferList);
                return;
            }
            
            int numChannels = asbd->mChannelsPerFrame;
            int numFrames = (int)CMSampleBufferGetNumSamples(sampleBuffer);
            // NSLog(@"[Audio Capture Delegate] Received Audio Frame: Channels=%d, Frames=%d, SampleRate=%f", numChannels, numFrames, asbd->mSampleRate);
            
            auto leftChannel = std::make_shared<std::vector<float>>(numFrames, 0.0f);
            auto rightChannel = std::make_shared<std::vector<float>>(numFrames, 0.0f);
            
            if (asbd->mFormatFlags & kAudioFormatFlagIsNonInterleaved) {
                if (audioBufferList->mNumberBuffers > 0) {
                    float* samplesL = (float*)audioBufferList->mBuffers[0].mData;
                    if (samplesL) {
                        memcpy(leftChannel->data(), samplesL, numFrames * sizeof(float));
                    }
                }
                if (audioBufferList->mNumberBuffers > 1) {
                    float* samplesR = (float*)audioBufferList->mBuffers[1].mData;
                    if (samplesR) {
                        memcpy(rightChannel->data(), samplesR, numFrames * sizeof(float));
                    }
                } else if (audioBufferList->mNumberBuffers > 0) {
                    memcpy(rightChannel->data(), leftChannel->data(), numFrames * sizeof(float));
                }
            } else {
                if (audioBufferList->mNumberBuffers > 0) {
                    float* samples = (float*)audioBufferList->mBuffers[0].mData;
                    if (samples) {
                        for (int i = 0; i < numFrames; i++) {
                            (*leftChannel)[i] = samples[i * numChannels + 0];
                            if (numChannels > 1) {
                                (*rightChannel)[i] = samples[i * numChannels + 1];
                            } else {
                                (*rightChannel)[i] = samples[i * numChannels + 0];
                            }
                        }
                    }
                }
            }
            
            CFRelease(blockBuffer);
            free(audioBufferList);
            
            // Thread-safe V8 callback
            std::lock_guard<std::mutex> lock(g_AudioCallbackMutex);
            if (g_AudioCaptureActive && g_AudioCallback) {
                auto callback = [leftChannel, rightChannel, numFrames](Napi::Env env, Napi::Function jsCallback) {
                    // NSLog(@"[Audio Capture Delegate] Thread-safe callback executing in JS thread for %d frames", numFrames);
                    Napi::Float32Array leftArray = Napi::Float32Array::New(env, numFrames);
                    Napi::Float32Array rightArray = Napi::Float32Array::New(env, numFrames);
                    
                    memcpy(leftArray.Data(), leftChannel->data(), numFrames * sizeof(float));
                    memcpy(rightArray.Data(), rightChannel->data(), numFrames * sizeof(float));
                    
                    jsCallback.Call({ leftArray, rightArray });
                };
                napi_status nstatus = g_AudioCallback.NonBlockingCall(callback);
                if (nstatus != napi_ok) {
                    NSLog(@"[Audio Capture Delegate] NonBlockingCall failed with status: %d", nstatus);
                }
            } else {
                // NSLog(@"[Audio Capture Delegate] Callback inactive: active=%d, callbackSet=%d", g_AudioCaptureActive, (g_AudioCallback ? 1 : 0));
            }
        }
    }
}

@end

// getAudioSources()
Napi::Array GetAudioSources(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    NSArray<NSRunningApplication *> *apps = [[NSWorkspace sharedWorkspace] runningApplications];
    NSMutableArray<NSRunningApplication *> *filteredApps = [NSMutableArray array];
    
    for (NSRunningApplication *app in apps) {
        if (app.activationPolicy == NSApplicationActivationPolicyRegular) {
            [filteredApps addObject:app];
        }
    }
    
    Napi::Array arr = Napi::Array::New(env, [filteredApps count]);
    for (NSUInteger i = 0; i < [filteredApps count]; i++) {
        NSRunningApplication *app = [filteredApps objectAtIndex:i];
        Napi::Object obj = Napi::Object::New(env);
        
        NSString *name = app.localizedName ? app.localizedName : @"Unknown App";
        NSString *bundleId = app.bundleIdentifier ? app.bundleIdentifier : @"";
        
        obj.Set("name", Napi::String::New(env, [name UTF8String]));
        obj.Set("bundleId", Napi::String::New(env, [bundleId UTF8String]));
        obj.Set("pid", Napi::Number::New(env, app.processIdentifier));
        
        arr.Set(i, obj);
    }
    
    return arr;
}

// startAudioCapture(pid, callback)
Napi::Value StartAudioCapture(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (NSClassFromString(@"SCStream") == nil) {
        Napi::TypeError::New(env, "ScreenCaptureKit is not supported on this macOS version").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    // Check screen recording permission
    if (!CGPreflightScreenCaptureAccess()) {
        NSLog(@"[Audio Capture] Screen Recording permission NOT granted. Requesting access...");
        CGRequestScreenCaptureAccess();
        return Napi::Boolean::New(env, false);
    }
    
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsFunction()) {
        Napi::TypeError::New(env, "Arguments expected: Number (pid), Function (callback)").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    int targetPid = info[0].As<Napi::Number>().Int32Value();
    Napi::Function cb = info[1].As<Napi::Function>();
    
    // Stop any existing capture
    {
        std::lock_guard<std::mutex> lock(g_AudioCallbackMutex);
        g_AudioCaptureActive = false;
        if (g_AudioCallback) {
            g_AudioCallback.Release();
            g_AudioCallback = Napi::ThreadSafeFunction();
        }
    }
    if (g_AudioStream) {
        [g_AudioStream stopCaptureWithCompletionHandler:^(NSError *error) {
            if (error) NSLog(@"[Audio Capture] Stop failed: %@", error);
        }];
        g_AudioStream = nil;
        g_AudioDelegate = nil;
    }
    
    // Initialize callback
    {
        std::lock_guard<std::mutex> lock(g_AudioCallbackMutex);
        g_AudioCaptureActive = true;
        g_AudioCallback = Napi::ThreadSafeFunction::New(
            env,
            cb,
            "AudioCaptureCallback",
            0,
            1
        );
    }
    
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent *shareableContent, NSError *error) {
        if (error || !shareableContent) {
            NSLog(@"[Audio Capture] Failed to get shareable content: %@", error);
            return;
        }
        
        if (shareableContent.displays.count == 0) {
            NSLog(@"[Audio Capture] No displays found");
            return;
        }
        
        SCDisplay *display = shareableContent.displays.firstObject;
        
        SCRunningApplication *targetApp = nil;
        for (SCRunningApplication *app in shareableContent.applications) {
            if (app.processID == targetPid) {
                targetApp = app;
                break;
            }
        }
        
        if (!targetApp) {
            NSLog(@"[Audio Capture] Target PID %d not found in shareable content applications list", targetPid);
            return;
        }
        
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display includingApplications:@[targetApp] exceptingWindows:@[]];
        
        SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
        config.capturesAudio = YES;
        config.excludesCurrentProcessAudio = YES;
        config.sampleRate = 48000;
        config.channelCount = 2;
        
        // Minimize video CPU/GPU usage
        config.width = 16;
        config.height = 16;
        config.minimumFrameInterval = CMTimeMake(1, 2);
        
        g_AudioStream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:nil];
        g_AudioDelegate = [[AudioCaptureDelegate alloc] init];
        
        if (!g_AudioQueue) {
            g_AudioQueue = dispatch_queue_create("gl.cables.audioCaptureQueue", DISPATCH_QUEUE_SERIAL);
        }
        
        NSError *streamError = nil;
        BOOL success = [g_AudioStream addStreamOutput:g_AudioDelegate type:SCStreamOutputTypeAudio sampleHandlerQueue:g_AudioQueue error:&streamError];
        if (!success || streamError) {
            NSLog(@"[Audio Capture] Failed to add stream output: %@", streamError);
            return;
        }
        
        [g_AudioStream startCaptureWithCompletionHandler:^(NSError *startError) {
            if (startError) {
                NSLog(@"[Audio Capture] Start capture failed: %@", startError);
            } else {
                NSLog(@"[Audio Capture] Capture started successfully for PID %d", targetPid);
            }
        }];
    }];
    
    return Napi::Boolean::New(env, true);
}

// stopAudioCapture()
Napi::Value StopAudioCapture(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    {
        std::lock_guard<std::mutex> lock(g_AudioCallbackMutex);
        g_AudioCaptureActive = false;
        if (g_AudioCallback) {
            g_AudioCallback.Release();
            g_AudioCallback = Napi::ThreadSafeFunction();
        }
    }
    
    if (g_AudioStream) {
        [g_AudioStream stopCaptureWithCompletionHandler:^(NSError *error) {
            if (error) {
                NSLog(@"[Audio Capture] Stop capture error: %@", error);
            } else {
                NSLog(@"[Audio Capture] Capture stopped successfully");
            }
        }];
        g_AudioStream = nil;
        g_AudioDelegate = nil;
    }
    
    return env.Undefined();
}

// getWindowList()
Napi::Array GetWindowList(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID
    );
    
    if (!windowList) {
        return Napi::Array::New(env, 0);
    }
    
    CFIndex count = CFArrayGetCount(windowList);
    NSMutableArray *filteredList = [NSMutableArray array];
    
    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef dict = (CFDictionaryRef)CFArrayGetValueAtIndex(windowList, i);
        
        // Filter windows: must be normal windows (layer 0)
        CFNumberRef layerRef = (CFNumberRef)CFDictionaryGetValue(dict, kCGWindowLayer);
        int layer = 0;
        if (layerRef) {
            CFNumberGetValue(layerRef, kCFNumberIntType, &layer);
        }
        
        if (layer != 0) {
            continue;
        }
        
        CFStringRef ownerNameRef = (CFStringRef)CFDictionaryGetValue(dict, kCGWindowOwnerName);
        CFStringRef windowNameRef = (CFStringRef)CFDictionaryGetValue(dict, kCGWindowName);
        CFNumberRef pidRef = (CFNumberRef)CFDictionaryGetValue(dict, kCGWindowOwnerPID);
        CFNumberRef windowIdRef = (CFNumberRef)CFDictionaryGetValue(dict, kCGWindowNumber);
        
        NSString *ownerName = ownerNameRef ? (__bridge NSString *)ownerNameRef : @"";
        NSString *windowName = windowNameRef ? (__bridge NSString *)windowNameRef : @"";
        
        // Skip windows without titles or owner names
        if ([windowName length] == 0 && [ownerName length] == 0) {
            continue;
        }
        
        int pid = 0;
        if (pidRef) {
            CFNumberGetValue(pidRef, kCFNumberIntType, &pid);
        }
        
        uint32_t windowId = 0;
        if (windowIdRef) {
            CFNumberGetValue(windowIdRef, kCFNumberSInt32Type, &windowId);
        }
        
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        [item setObject:ownerName forKey:@"ownerName"];
        [item setObject:windowName forKey:@"title"];
        [item setObject:@(pid) forKey:@"pid"];
        [item setObject:@(windowId) forKey:@"id"];
        
        [filteredList addObject:item];
    }
    
    CFRelease(windowList);
    
    Napi::Array arr = Napi::Array::New(env, [filteredList count]);
    for (NSUInteger i = 0; i < [filteredList count]; i++) {
        NSDictionary *item = [filteredList objectAtIndex:i];
        Napi::Object obj = Napi::Object::New(env);
        
        obj.Set("ownerName", Napi::String::New(env, [[item objectForKey:@"ownerName"] UTF8String]));
        obj.Set("title", Napi::String::New(env, [[item objectForKey:@"title"] UTF8String]));
        obj.Set("pid", Napi::Number::New(env, [[item objectForKey:@"pid"] intValue]));
        obj.Set("id", Napi::Number::New(env, [[item objectForKey:@"id"] unsignedIntValue]));
        
        arr.Set(i, obj);
    }
    
    return arr;
}

void InitAudioCapture(Napi::Env env, Napi::Object exports) {
    exports.Set(Napi::String::New(env, "getAudioSources"), Napi::Function::New(env, GetAudioSources));
    exports.Set(Napi::String::New(env, "startAudioCapture"), Napi::Function::New(env, StartAudioCapture));
    exports.Set(Napi::String::New(env, "stopAudioCapture"), Napi::Function::New(env, StopAudioCapture));
    exports.Set(Napi::String::New(env, "getWindowList"), Napi::Function::New(env, GetWindowList));
}
