#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Vision/Vision.h>
#include <napi.h>
#include <v8.h>
#include <string>
#include <vector>
#include <unordered_map>
#include "vision_bridge.h"

// Helper to check if V8 is shutting down or terminating execution
inline bool IsIsolateTerminating() {
    v8::Isolate* isolate = v8::Isolate::GetCurrent();
    return isolate && isolate->IsExecutionTerminating();
}

// ----------------------------------------------------
// Asynchronous Worker: Person Segmentation
// ----------------------------------------------------
class SegmentationWorker : public Napi::AsyncWorker {
public:
    SegmentationWorker(Napi::Env env, Napi::Buffer<uint8_t>& pixelBuf, int width, int height, std::string quality)
        : Napi::AsyncWorker(env), _deferred(Napi::Promise::Deferred::New(env)), _width(width), _height(height), _quality(quality) {
        _pixels.assign(pixelBuf.Data(), pixelBuf.Data() + pixelBuf.Length());
    }
    
    Napi::Promise Promise() {
        return _deferred.Promise();
    }
    
    void Execute() override {
        @autoreleasepool {
            CVPixelBufferRef pixelBuffer = NULL;
            NSDictionary *options = @{
                (id)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES),
                (id)kCVPixelBufferMetalCompatibilityKey: @(YES),
                (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
            };
            
            CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, _width, _height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pixelBuffer);
            if (status != kCVReturnSuccess || !pixelBuffer) {
                SetError("Failed to create CVPixelBuffer inside worker (status: " + std::to_string(status) + ")");
                return;
            }
            
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
            // Swap Red and Blue channels from RGBA (Cables/WebGL) to BGRA (CoreVideo/macOS preferred)
            for (int i = 0; i < _width * _height; i++) {
                baseAddress[i * 4]     = _pixels[i * 4 + 2]; // B
                baseAddress[i * 4 + 1] = _pixels[i * 4 + 1]; // G
                baseAddress[i * 4 + 2] = _pixels[i * 4];     // R
                baseAddress[i * 4 + 3] = _pixels[i * 4 + 3]; // A
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            
            VNGeneratePersonSegmentationRequest *request = [[VNGeneratePersonSegmentationRequest alloc] init];
            if (_quality == "accurate") {
                request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
            } else if (_quality == "fast") {
                request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelFast;
            } else {
                request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelBalanced;
            }
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8;
            
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];
            NSError *error = nil;
            BOOL success = [handler performRequests:@[request] error:&error];
            CVPixelBufferRelease(pixelBuffer);
            
            if (!success || error) {
                NSString *errDesc = error ? error.localizedDescription : @"Unknown error";
                SetError("Vision segmentation failed: " + std::string([errDesc UTF8String]));
                return;
            }
            
            VNPixelBufferObservation *observation = request.results.firstObject;
            if (!observation) {
                SetError("Vision returned no results");
                return;
            }
            
            CVPixelBufferRef maskBuffer = observation.pixelBuffer;
            CVPixelBufferLockBaseAddress(maskBuffer, kCVPixelBufferLock_ReadOnly);
            
            _maskW = CVPixelBufferGetWidth(maskBuffer);
            _maskH = CVPixelBufferGetHeight(maskBuffer);
            void *maskData = CVPixelBufferGetBaseAddress(maskBuffer);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer);
            
            _outputMask.resize(_maskW * _maskH);
            if (bytesPerRow == _maskW) {
                memcpy(_outputMask.data(), maskData, _maskW * _maskH);
            } else {
                for (size_t y = 0; y < _maskH; y++) {
                    memcpy(_outputMask.data() + y * _maskW, (uint8_t *)maskData + y * bytesPerRow, _maskW);
                }
            }
            
            CVPixelBufferUnlockBaseAddress(maskBuffer, kCVPixelBufferLock_ReadOnly);
        }
    }
    
    void OnOK() override {
        if (IsIsolateTerminating()) return;
        
        Napi::Env env = Env();
        Napi::HandleScope scope(env);
        
        Napi::Buffer<uint8_t> returningBuf = Napi::Buffer<uint8_t>::Copy(env, _outputMask.data(), _outputMask.size());
        
        Napi::Object resultObj = Napi::Object::New(env);
        resultObj.Set("maskBuffer", returningBuf);
        resultObj.Set("width", Napi::Number::New(env, _maskW));
        resultObj.Set("height", Napi::Number::New(env, _maskH));
        
        _deferred.Resolve(resultObj);
    }
    
    void OnError(const Napi::Error& err) override {
        if (IsIsolateTerminating()) return;
        _deferred.Reject(err.Value());
    }
    
private:
    Napi::Promise::Deferred _deferred;
    int _width;
    int _height;
    std::string _quality;
    std::vector<uint8_t> _pixels;
    size_t _maskW = 0;
    size_t _maskH = 0;
    std::vector<uint8_t> _outputMask;
};

Napi::Value ProcessSegmentation(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 4 || !info[0].IsBuffer() || !info[1].IsNumber() || !info[2].IsNumber() || !info[3].IsString()) {
        Napi::TypeError::New(env, "Arguments expected: Buffer (pixels), Number (width), Number (height), String (quality)").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Napi::Buffer<uint8_t> buffer = info[0].As<Napi::Buffer<uint8_t>>();
    int width = info[1].As<Napi::Number>().Int32Value();
    int height = info[2].As<Napi::Number>().Int32Value();
    std::string quality = info[3].As<Napi::String>().Utf8Value();
    
    if (width <= 0 || height <= 0 || buffer.Length() < width * height * 4) {
        Napi::TypeError::New(env, "Invalid buffer length for given dimensions").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    SegmentationWorker* worker = new SegmentationWorker(env, buffer, width, height, quality);
    worker->Queue();
    return worker->Promise();
}


// ----------------------------------------------------
// Asynchronous Worker: 2D Human Pose Detection
// ----------------------------------------------------
class PoseWorker : public Napi::AsyncWorker {
public:
    PoseWorker(Napi::Env env, Napi::Buffer<uint8_t>& pixelBuf, int width, int height, float minConfidence)
        : Napi::AsyncWorker(env), _deferred(Napi::Promise::Deferred::New(env)), _width(width), _height(height), _minConfidence(minConfidence) {
        _pixels.assign(pixelBuf.Data(), pixelBuf.Data() + pixelBuf.Length());
    }
    
    Napi::Promise Promise() {
        return _deferred.Promise();
    }
    
    void Execute() override {
        @autoreleasepool {
            CVPixelBufferRef pixelBuffer = NULL;
            NSDictionary *options = @{
                (id)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES),
                (id)kCVPixelBufferMetalCompatibilityKey: @(YES),
                (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
            };
            
            CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, _width, _height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pixelBuffer);
            if (status != kCVReturnSuccess || !pixelBuffer) {
                SetError("Failed to create CVPixelBuffer inside worker (status: " + std::to_string(status) + ")");
                return;
            }
            
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
            for (int i = 0; i < _width * _height; i++) {
                baseAddress[i * 4]     = _pixels[i * 4 + 2]; // B
                baseAddress[i * 4 + 1] = _pixels[i * 4 + 1]; // G
                baseAddress[i * 4 + 2] = _pixels[i * 4];     // R
                baseAddress[i * 4 + 3] = _pixels[i * 4 + 3]; // A
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            
            VNDetectHumanBodyPoseRequest *request = [[VNDetectHumanBodyPoseRequest alloc] init];
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];
            NSError *error = nil;
            BOOL success = [handler performRequests:@[request] error:&error];
            CVPixelBufferRelease(pixelBuffer);
            
            if (!success || error) {
                NSString *errDesc = error ? error.localizedDescription : @"Unknown error";
                SetError("Vision body pose detection failed: " + std::string([errDesc UTF8String]));
                return;
            }
            
            NSArray *observations = request.results;
            for (VNHumanBodyPoseObservation *observation in observations) {
                NSError *keypointError = nil;
                NSDictionary<VNHumanBodyPoseObservationJointName, VNRecognizedPoint *> *recognizedPoints = 
                    [observation recognizedPointsForJointsGroupName:VNHumanBodyPoseObservationJointsGroupNameAll error:&keypointError];
                
                std::unordered_map<std::string, std::vector<float>> poseMap;
                if (recognizedPoints && !keypointError) {
                    for (VNHumanBodyPoseObservationJointName jointName in recognizedPoints) {
                        VNRecognizedPoint *point = [recognizedPoints objectForKey:jointName];
                        if (point && point.confidence >= _minConfidence) {
                            poseMap[[jointName UTF8String]] = { (float)point.x, (float)point.y, (float)point.confidence };
                        }
                    }
                }
                _poses.push_back(poseMap);
            }
        }
    }
    
    void OnOK() override {
        if (IsIsolateTerminating()) return;
        
        Napi::Env env = Env();
        Napi::HandleScope scope(env);
        
        Napi::Array posesArray = Napi::Array::New(env, _poses.size());
        for (size_t i = 0; i < _poses.size(); i++) {
            Napi::Object poseObj = Napi::Object::New(env);
            for (auto const& [jointName, vals] : _poses[i]) {
                Napi::Object ptObj = Napi::Object::New(env);
                ptObj.Set("x", Napi::Number::New(env, vals[0]));
                ptObj.Set("y", Napi::Number::New(env, vals[1]));
                ptObj.Set("confidence", Napi::Number::New(env, vals[2]));
                
                poseObj.Set(jointName, ptObj);
            }
            posesArray.Set(i, poseObj);
        }
        
        _deferred.Resolve(posesArray);
    }
    
    void OnError(const Napi::Error& err) override {
        if (IsIsolateTerminating()) return;
        _deferred.Reject(err.Value());
    }
    
private:
    Napi::Promise::Deferred _deferred;
    int _width;
    int _height;
    float _minConfidence;
    std::vector<uint8_t> _pixels;
    std::vector<std::unordered_map<std::string, std::vector<float>>> _poses;
};

Napi::Value DetectHumanPose(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 4 || !info[0].IsBuffer() || !info[1].IsNumber() || !info[2].IsNumber() || !info[3].IsNumber()) {
        Napi::TypeError::New(env, "Arguments expected: Buffer (pixels), Number (width), Number (height), Number (minConfidence)").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Napi::Buffer<uint8_t> buffer = info[0].As<Napi::Buffer<uint8_t>>();
    int width = info[1].As<Napi::Number>().Int32Value();
    int height = info[2].As<Napi::Number>().Int32Value();
    float minConfidence = info[3].As<Napi::Number>().FloatValue();
    
    if (width <= 0 || height <= 0 || buffer.Length() < width * height * 4) {
        Napi::TypeError::New(env, "Invalid buffer length for given dimensions").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    PoseWorker* worker = new PoseWorker(env, buffer, width, height, minConfidence);
    worker->Queue();
    return worker->Promise();
}


// ----------------------------------------------------
// Asynchronous Worker: 3D Human Pose Detection
// ----------------------------------------------------
class Pose3dWorker : public Napi::AsyncWorker {
public:
    Pose3dWorker(Napi::Env env, Napi::Buffer<uint8_t>& pixelBuf, int width, int height)
        : Napi::AsyncWorker(env), _deferred(Napi::Promise::Deferred::New(env)), _width(width), _height(height) {
        _pixels.assign(pixelBuf.Data(), pixelBuf.Data() + pixelBuf.Length());
    }
    
    Napi::Promise Promise() {
        return _deferred.Promise();
    }
    
    void Execute() override {
        @autoreleasepool {
            CVPixelBufferRef pixelBuffer = NULL;
            NSDictionary *options = @{
                (id)kCVPixelBufferCGImageCompatibilityKey: @(YES),
                (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @(YES),
                (id)kCVPixelBufferMetalCompatibilityKey: @(YES),
                (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
            };
            
            CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, _width, _height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)options, &pixelBuffer);
            if (status != kCVReturnSuccess || !pixelBuffer) {
                SetError("Failed to create CVPixelBuffer inside worker (status: " + std::to_string(status) + ")");
                return;
            }
            
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
            for (int i = 0; i < _width * _height; i++) {
                baseAddress[i * 4]     = _pixels[i * 4 + 2]; // B
                baseAddress[i * 4 + 1] = _pixels[i * 4 + 1]; // G
                baseAddress[i * 4 + 2] = _pixels[i * 4];     // R
                baseAddress[i * 4 + 3] = _pixels[i * 4 + 3]; // A
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            
            if (@available(macOS 14.0, *)) {
                VNDetectHumanBodyPose3DRequest *request = [[VNDetectHumanBodyPose3DRequest alloc] init];
                VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];
                NSError *error = nil;
                BOOL success = [handler performRequests:@[request] error:&error];
                CVPixelBufferRelease(pixelBuffer);
                
                if (!success || error) {
                    NSString *errDesc = error ? error.localizedDescription : @"Unknown error";
                    SetError("Vision 3D body pose detection failed: " + std::string([errDesc UTF8String]));
                    return;
                }
                
                NSArray *observations = request.results;
                for (VNHumanBodyPose3DObservation *observation in observations) {
                    NSError *jointError = nil;
                    NSDictionary<VNHumanBodyPose3DObservationJointName, VNRecognizedPoint3D *> *recognizedPoints = 
                        [observation recognizedPointsForJointsGroupName:VNHumanBodyPose3DObservationJointsGroupNameAll error:&jointError];
                    
                    std::unordered_map<std::string, std::vector<float>> poseMap;
                    if (recognizedPoints && !jointError) {
                        for (VNHumanBodyPose3DObservationJointName jointName in recognizedPoints) {
                            VNRecognizedPoint3D *point = [recognizedPoints objectForKey:jointName];
                            if (point) {
                                simd_float4 pos = point.position.columns[3];
                                poseMap[[jointName UTF8String]] = { pos.x, pos.y, pos.z, 1.0f };
                            }
                        }
                    }
                    
                    _poses.push_back({ poseMap, (float)observation.bodyHeight });
                }
            } else {
                CVPixelBufferRelease(pixelBuffer);
                SetError("VNDetectHumanBodyPose3DRequest requires macOS 14.0 or higher");
            }
        }
    }
    
    void OnOK() override {
        if (IsIsolateTerminating()) return;
        
        Napi::Env env = Env();
        Napi::HandleScope scope(env);
        
        Napi::Array posesArray = Napi::Array::New(env, _poses.size());
        for (size_t i = 0; i < _poses.size(); i++) {
            Napi::Object poseObj = Napi::Object::New(env);
            for (auto const& [jointName, vals] : _poses[i].joints) {
                Napi::Object ptObj = Napi::Object::New(env);
                ptObj.Set("x", Napi::Number::New(env, vals[0]));
                ptObj.Set("y", Napi::Number::New(env, vals[1]));
                ptObj.Set("z", Napi::Number::New(env, vals[2]));
                ptObj.Set("confidence", Napi::Number::New(env, vals[3]));
                
                poseObj.Set(jointName, ptObj);
            }
            poseObj.Set("bodyHeight", Napi::Number::New(env, _poses[i].bodyHeight));
            posesArray.Set(i, poseObj);
        }
        
        _deferred.Resolve(posesArray);
    }
    
    void OnError(const Napi::Error& err) override {
        if (IsIsolateTerminating()) return;
        _deferred.Reject(err.Value());
    }
    
private:
    struct Pose3dData {
        std::unordered_map<std::string, std::vector<float>> joints;
        float bodyHeight;
    };
    
    Napi::Promise::Deferred _deferred;
    int _width;
    int _height;
    std::vector<uint8_t> _pixels;
    std::vector<Pose3dData> _poses;
};

Napi::Value DetectHumanPose3d(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    if (info.Length() < 3 || !info[0].IsBuffer() || !info[1].IsNumber() || !info[2].IsNumber()) {
        Napi::TypeError::New(env, "Arguments expected: Buffer (pixels), Number (width), Number (height)").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Napi::Buffer<uint8_t> buffer = info[0].As<Napi::Buffer<uint8_t>>();
    int width = info[1].As<Napi::Number>().Int32Value();
    int height = info[2].As<Napi::Number>().Int32Value();
    
    if (width <= 0 || height <= 0 || buffer.Length() < width * height * 4) {
        Napi::TypeError::New(env, "Invalid buffer length for given dimensions").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    
    Pose3dWorker* worker = new Pose3dWorker(env, buffer, width, height);
    worker->Queue();
    return worker->Promise();
}

void InitVision(Napi::Env env, Napi::Object exports) {
    exports.Set(Napi::String::New(env, "processSegmentation"), Napi::Function::New(env, ProcessSegmentation));
    exports.Set(Napi::String::New(env, "detectHumanPose"), Napi::Function::New(env, DetectHumanPose));
    exports.Set(Napi::String::New(env, "detectHumanPose3d"), Napi::Function::New(env, DetectHumanPose3d));
}
