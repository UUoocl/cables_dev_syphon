#include "speech_bridge.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#include <vector>
#include <string>
#include <iostream>
#include <cmath>
#include <mutex>

// ====================================================
// Constants & Structures
// ====================================================

struct SpeechEventData {
    std::string type;
    std::string text;
    bool is_final;
    std::vector<std::pair<std::string, std::string>> devices;
    std::string status;
};

// Global Napi callback reference and mutex
static Napi::ThreadSafeFunction g_SpeechCallback;
static std::recursive_mutex g_SpeechMutex;

static NSBundle* GetMainAppBundle() {
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* path = [bundle bundlePath];
    NSRange range = [path rangeOfString:@"/Contents/Frameworks/"];
    if (range.location != NSNotFound) {
        NSString* mainPath = [path substringToIndex:range.location];
        NSBundle* outerBundle = [NSBundle bundleWithPath:mainPath];
        if (outerBundle != nil) {
            return outerBundle;
        }
    }
    return bundle;
}

std::vector<std::pair<std::string, std::string>> getAudioInputDevicesCpp() {
    std::vector<std::pair<std::string, std::string>> list;
    list.push_back({"Default System Microphone", "Default"});
    
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, nil, &size);
    if (status != noErr) return list;
    
    int count = size / sizeof(AudioDeviceID);
    std::vector<AudioDeviceID> devices(count);
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nil, &size, devices.data());
    if (status != noErr) return list;
    
    for (AudioDeviceID device : devices) {
        AudioObjectPropertyAddress streamAddress = {
            kAudioDevicePropertyStreams,
            kAudioObjectPropertyScopeInput,
            kAudioObjectPropertyElementMain
        };
        
        UInt32 streamSize = 0;
        status = AudioObjectGetPropertyDataSize(device, &streamAddress, 0, nil, &streamSize);
        if (status != noErr || streamSize == 0) {
            continue;
        }
        
        AudioObjectPropertyAddress nameAddress = {
            kAudioDevicePropertyDeviceNameCFString,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        CFStringRef nameString = nil;
        UInt32 nameSize = sizeof(CFStringRef);
        status = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &nameString);
        std::string name = "Unknown Input";
        if (status == noErr && nameString) {
            name = [(__bridge NSString*)nameString UTF8String];
            CFRelease(nameString);
        }
        
        AudioObjectPropertyAddress uidAddress = {
            kAudioDevicePropertyDeviceUID,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        CFStringRef uidString = nil;
        UInt32 uidSize = sizeof(CFStringRef);
        status = AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uidString);
        std::string uid = "Unknown UID";
        if (status == noErr && uidString) {
            uid = [(__bridge NSString*)uidString UTF8String];
            CFRelease(uidString);
        }
        
        list.push_back({name, uid});
    }
    
    return list;
}

AudioDeviceID getAudioDeviceIDCpp(const std::string& uid) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    
    UInt32 size = 0;
    OSStatus status = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, nil, &size);
    if (status != noErr) return 0;
    
    int count = size / sizeof(AudioDeviceID);
    std::vector<AudioDeviceID> devices(count);
    status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nil, &size, devices.data());
    if (status != noErr) return 0;
    
    for (AudioDeviceID device : devices) {
        AudioObjectPropertyAddress uidAddress = {
            kAudioDevicePropertyDeviceUID,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        
        CFStringRef uidString = nil;
        UInt32 uidSize = sizeof(CFStringRef);
        status = AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uidString);
        if (status == noErr && uidString) {
            std::string uidStr = [(__bridge NSString*)uidString UTF8String];
            CFRelease(uidString);
            if (uidStr == uid) {
                return device;
            }
        }
    }
    return 0;
}

@interface SpeechRecognizerEngine : NSObject {
    NSString* _currentLocale;
    NSString* _currentDeviceUID;
    double _silenceDuration;
    NSDate* _lastActivityTime;
    BOOL _isSilentState;
    NSString* _lastText;
    BOOL _isRecording;
}

@property (nonatomic, strong) SFSpeechRecognizer* speechRecognizer;
@property (nonatomic, strong) SFSpeechAudioBufferRecognitionRequest* recognitionRequest;
@property (nonatomic, strong) SFSpeechRecognitionTask* recognitionTask;
@property (nonatomic, strong) AVAudioEngine* audioEngine;

- (instancetype)init;
- (void)startRecordingWithLocale:(NSString*)locale deviceUID:(NSString*)deviceUID silenceDuration:(double)silenceDuration;
- (void)stopRecording;
- (void)setLocale:(NSString*)locale;
- (void)setAudioDevice:(NSString*)deviceUID;
- (void)setSilenceDuration:(double)seconds;
- (void)resetTranscription;
- (void)publishAudioDevices;
- (void)sendStatusEvent:(NSString*)status;

@end

static SpeechRecognizerEngine* g_engine = nil;

static OSStatus AudioDeviceListChangedCallback(AudioObjectID inObjectID, UInt32 inNumberAddresses, const AudioObjectPropertyAddress* inAddresses, void* inClientData) {
    SpeechRecognizerEngine* engine = (__bridge SpeechRecognizerEngine*)inClientData;
    [engine publishAudioDevices];
    return noErr;
}

@implementation SpeechRecognizerEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _audioEngine = [[AVAudioEngine alloc] init];
        _currentLocale = @"en-US";
        _currentDeviceUID = @"Default";
        _silenceDuration = 1.5;
        _isRecording = NO;
        
        NSString* speechDesc = [GetMainAppBundle() objectForInfoDictionaryKey:@"NSSpeechRecognitionUsageDescription"];
        if (speechDesc != nil) {
            [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
                // Requesting permission asynchronously
            }];
        }
        
        // Register CoreAudio listener for hotplugging input devices
        AudioObjectPropertyAddress address = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        AudioObjectAddPropertyListener(kAudioObjectSystemObject, &address, AudioDeviceListChangedCallback, (__bridge void*)self);
    }
    return self;
}

- (void)dealloc {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &address, AudioDeviceListChangedCallback, (__bridge void*)self);
    [self stopRecording];
}

- (void)startRecordingWithLocale:(NSString*)locale deviceUID:(NSString*)deviceUID silenceDuration:(double)silenceDuration {
    @synchronized (self) {
        _currentLocale = locale;
        _currentDeviceUID = deviceUID;
        _silenceDuration = silenceDuration;
        _isRecording = YES;
        
        [self startRecordingInternal];
    }
}

- (void)startRecordingInternal {
    NSString* speechDesc = [GetMainAppBundle() objectForInfoDictionaryKey:@"NSSpeechRecognitionUsageDescription"];
    if (speechDesc == nil) {
        [self sendStatusEvent:@"Missing Speech Permission Key in Info.plist"];
        return;
    }

    [self.audioEngine stop];
    [self.audioEngine.inputNode removeTapOnBus:0];
    
    if (self.recognitionTask) {
        [self.recognitionTask cancel];
        self.recognitionTask = nil;
    }
    
    self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:_currentLocale]];
    if (!self.speechRecognizer || !self.speechRecognizer.available) {
        [self sendStatusEvent:@"Recognizer Not Available"];
        return;
    }
    
    self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    self.recognitionRequest.shouldReportPartialResults = YES;
    
    if (self.speechRecognizer.supportsOnDeviceRecognition) {
        self.recognitionRequest.requiresOnDeviceRecognition = YES;
    }
    
    AVAudioInputNode* inputNode = self.audioEngine.inputNode;
    
    // Bind device ID if configured
    if (_currentDeviceUID && ![_currentDeviceUID isEqualToString:@"Default"]) {
        AudioDeviceID deviceID = getAudioDeviceIDCpp([_currentDeviceUID UTF8String]);
        if (deviceID != 0) {
            AudioUnit inputAudioUnit = inputNode.audioUnit;
            if (inputAudioUnit) {
                AudioUnitSetProperty(
                    inputAudioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceID,
                    sizeof(AudioDeviceID)
                );
            }
        }
    }
    
    AVAudioFormat* recordingFormat = [inputNode outputFormatForBus:0];
    if (recordingFormat.sampleRate <= 0 || recordingFormat.channelCount <= 0) {
        [self sendStatusEvent:@"Invalid Audio Input Format"];
        return;
    }
    
    _lastActivityTime = [NSDate date];
    _isSilentState = YES;
    _lastText = @"";
    
    [inputNode installTapOnBus:0 bufferSize:4096 format:recordingFormat block:^(AVAudioPCMBuffer* _Nonnull buffer, AVAudioTime* _Nonnull when) {
        @synchronized (self) {
            if (self.recognitionRequest) {
                float* channelData = buffer.floatChannelData[0];
                int frameLength = buffer.frameLength;
                if (channelData && frameLength > 0) {
                    float sum = 0;
                    for (int i = 0; i < frameLength; ++i) {
                        sum += channelData[i] * channelData[i];
                    }
                    float rms = sqrt(sum / frameLength);
                    float db = rms > 0.0001 ? 20.0f * log10f(rms) : -100.0f;
                    
                    BOOL wasSilent = _isSilentState;
                    if (db > -45.0f) { // Silence Threshold DB
                        _lastActivityTime = [NSDate date];
                        _isSilentState = NO;
                    }
                    
                    BOOL shouldReset = !wasSilent && ([[NSDate date] timeIntervalSinceDate:_lastActivityTime] > _silenceDuration);
                    if (shouldReset) {
                        _isSilentState = YES;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self resetTranscription];
                        });
                    }
                }
                
                [self.recognitionRequest appendAudioPCMBuffer:buffer];
            }
        }
    }];
    
    [self.audioEngine prepare];
    NSError* startError = nil;
    [self.audioEngine startAndReturnError:&startError];
    if (startError) {
        [self sendStatusEvent:@"Audio Engine Start Failed"];
        return;
    }
    
    self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult* _Nullable result, NSError* _Nullable error) {
        if (result) {
            NSString* text = result.bestTranscription.formattedString;
            _lastText = text;
            [self sendTranscriptionEvent:text isFinal:result.isFinal];
        }
        
        if (error || (result && result.isFinal)) {
            @synchronized (self) {
                if (self.recognitionRequest) {
                    [self.audioEngine stop];
                    [self.audioEngine.inputNode removeTapOnBus:0];
                    self.recognitionRequest = nil;
                    self.recognitionTask = nil;
                }
            }
        }
    }];
    
    [self sendStatusEvent:@"Running"];
}

- (void)stopRecording {
    @synchronized (self) {
        _isRecording = NO;
        
        if (self.audioEngine.isRunning) {
            [self.audioEngine stop];
            [self.audioEngine.inputNode removeTapOnBus:0];
        }
        
        if (_lastText && ![_lastText isEqualToString:@""]) {
            [self sendTranscriptionEvent:_lastText isFinal:YES];
            _lastText = @"";
        }
        
        [self.recognitionRequest endAudio];
        [self.recognitionTask cancel];
        self.recognitionRequest = nil;
        self.recognitionTask = nil;
        _isSilentState = YES;
        
        [self sendStatusEvent:@"Stopped"];
    }
}

- (void)setLocale:(NSString*)locale {
    @synchronized (self) {
        if ([_currentLocale isEqualToString:locale]) return;
        _currentLocale = locale;
        if (_isRecording) {
            [self startRecordingInternal];
        }
    }
}

- (void)setAudioDevice:(NSString*)deviceUID {
    @synchronized (self) {
        if ([_currentDeviceUID isEqualToString:deviceUID]) return;
        _currentDeviceUID = deviceUID;
        if (_isRecording) {
            [self startRecordingInternal];
        }
    }
}

- (void)setSilenceDuration:(double)seconds {
    @synchronized (self) {
        _silenceDuration = seconds;
    }
}

- (void)resetTranscription {
    @synchronized (self) {
        if (!_isRecording) return;
        
        if (_lastText && ![_lastText isEqualToString:@""]) {
            [self sendTranscriptionEvent:_lastText isFinal:YES];
            _lastText = @"";
        }
        
        [self.recognitionRequest endAudio];
        [self.recognitionTask cancel];
        self.recognitionTask = nil;
        
        self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:_currentLocale]];
        self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
        self.recognitionRequest.shouldReportPartialResults = YES;
        
        if (self.speechRecognizer.supportsOnDeviceRecognition) {
            self.recognitionRequest.requiresOnDeviceRecognition = YES;
        }
        
        self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult* _Nullable result, NSError* _Nullable error) {
            if (result) {
                NSString* text = result.bestTranscription.formattedString;
                _lastText = text;
                [self sendTranscriptionEvent:text isFinal:result.isFinal];
            }
            
            if (error || (result && result.isFinal)) {
                @synchronized (self) {
                    if (self.recognitionRequest) {
                        [self.audioEngine stop];
                        [self.audioEngine.inputNode removeTapOnBus:0];
                        self.recognitionRequest = nil;
                        self.recognitionTask = nil;
                    }
                }
            }
        }];
    }
}

- (void)publishAudioDevices {
    SpeechEventData event;
    event.type = "devices";
    event.devices = getAudioInputDevicesCpp();
    
    [self dispatchEvent:event];
}

- (void)sendTranscriptionEvent:(NSString*)text isFinal:(BOOL)isFinal {
    SpeechEventData event;
    event.type = "transcription";
    event.text = [text UTF8String];
    event.is_final = isFinal;
    
    [self dispatchEvent:event];
}

- (void)sendStatusEvent:(NSString*)status {
    SpeechEventData event;
    event.type = "status";
    event.status = [status UTF8String];
    
    [self dispatchEvent:event];
}

- (void)dispatchEvent:(const SpeechEventData&)ev {
    std::lock_guard<std::recursive_mutex> lock(g_SpeechMutex);
    if (!g_SpeechCallback) return;
    
    auto callback = [ev](Napi::Env env, Napi::Function jsCallback) {
        Napi::Object eventObj = Napi::Object::New(env);
        eventObj.Set("type", Napi::String::New(env, ev.type));
        
        if (ev.type == "transcription") {
            eventObj.Set("text", Napi::String::New(env, ev.text));
            eventObj.Set("isFinal", Napi::Boolean::New(env, ev.is_final));
        } else if (ev.type == "devices") {
            Napi::Array devArray = Napi::Array::New(env, ev.devices.size());
            for (size_t i = 0; i < ev.devices.size(); ++i) {
                Napi::Object devObj = Napi::Object::New(env);
                devObj.Set("name", Napi::String::New(env, ev.devices[i].first));
                devObj.Set("id", Napi::String::New(env, ev.devices[i].second));
                devArray.Set(i, devObj);
            }
            eventObj.Set("devices", devArray);
        } else if (ev.type == "status") {
            eventObj.Set("status", Napi::String::New(env, ev.status));
        }
        
        jsCallback.Call({ eventObj });
    };
    
    g_SpeechCallback.NonBlockingCall(callback);
}

@end

// ====================================================
// Napi Wrappers
// ====================================================

Napi::Value InitRecognizer(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 1 || !info[0].IsFunction()) {
        Napi::TypeError::New(env, "Callback function required").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Napi::Function cb = info[0].As<Napi::Function>();
    
    {
        std::lock_guard<std::recursive_mutex> lock(g_SpeechMutex);
        g_SpeechCallback = Napi::ThreadSafeFunction::New(env, cb, "SpeechRecognizerCallback", 0, 1);
        
        if (!g_engine) {
            g_engine = [[SpeechRecognizerEngine alloc] init];
        }
    }
    
    [g_engine publishAudioDevices];
    
    return env.Undefined();
}

Napi::Value Start(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    std::string locale = "en-US";
    if (info.Length() > 0 && info[0].IsString()) {
        locale = info[0].As<Napi::String>().Utf8Value();
    }
    
    std::string deviceUID = "Default";
    if (info.Length() > 1 && info[1].IsString()) {
        deviceUID = info[1].As<Napi::String>().Utf8Value();
    }
    
    double silenceDuration = 1.5;
    if (info.Length() > 2 && info[2].IsNumber()) {
        silenceDuration = info[2].As<Napi::Number>().DoubleValue();
    }
    
    if (g_engine) {
        NSString* loc = [NSString stringWithUTF8String:locale.c_str()];
        NSString* dev = [NSString stringWithUTF8String:deviceUID.c_str()];
        [g_engine startRecordingWithLocale:loc deviceUID:dev silenceDuration:silenceDuration];
    }
    
    return env.Undefined();
}

Napi::Value Stop(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (g_engine) {
        [g_engine stopRecording];
    }
    return env.Undefined();
}

Napi::Value SetLocale(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    std::string locale = "en-US";
    if (info.Length() > 0 && info[0].IsString()) {
        locale = info[0].As<Napi::String>().Utf8Value();
    }
    
    if (g_engine) {
        [g_engine setLocale:[NSString stringWithUTF8String:locale.c_str()]];
    }
    
    return env.Undefined();
}

Napi::Value SetAudioDevice(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    std::string deviceUID = "Default";
    if (info.Length() > 0 && info[0].IsString()) {
        deviceUID = info[0].As<Napi::String>().Utf8Value();
    }
    
    if (g_engine) {
        [g_engine setAudioDevice:[NSString stringWithUTF8String:deviceUID.c_str()]];
    }
    
    return env.Undefined();
}

Napi::Value SetSilenceDuration(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    double silenceDuration = 1.5;
    if (info.Length() > 0 && info[0].IsNumber()) {
        silenceDuration = info[0].As<Napi::Number>().DoubleValue();
    }
    
    if (g_engine) {
        [g_engine setSilenceDuration:silenceDuration];
    }
    
    return env.Undefined();
}

Napi::Value Reset(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (g_engine) {
        [g_engine resetTranscription];
    }
    return env.Undefined();
}

Napi::Value RefreshDevices(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (g_engine) {
        [g_engine publishAudioDevices];
    }
    return env.Undefined();
}

void InitSpeech(Napi::Env env, Napi::Object exports) {
    exports.Set(Napi::String::New(env, "initSpeechRecognizer"), Napi::Function::New(env, InitRecognizer));
    exports.Set(Napi::String::New(env, "startSpeechRecognizer"), Napi::Function::New(env, Start));
    exports.Set(Napi::String::New(env, "stopSpeechRecognizer"), Napi::Function::New(env, Stop));
    exports.Set(Napi::String::New(env, "setSpeechLocale"), Napi::Function::New(env, SetLocale));
    exports.Set(Napi::String::New(env, "setSpeechAudioDevice"), Napi::Function::New(env, SetAudioDevice));
    exports.Set(Napi::String::New(env, "setSpeechSilenceDuration"), Napi::Function::New(env, SetSilenceDuration));
    exports.Set(Napi::String::New(env, "resetSpeechRecognizer"), Napi::Function::New(env, Reset));
    exports.Set(Napi::String::New(env, "refreshSpeechAudioDevices"), Napi::Function::New(env, RefreshDevices));
}
