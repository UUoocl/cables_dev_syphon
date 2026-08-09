{
  "targets": [
    {
      "target_name": "apple_framework_bridge",
      "sources": [
        "syphon_bridge.mm",
        "screencapturekit_bridge.mm",
        "vision_bridge.mm"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")"
      ],
      "defines": [
        "NAPI_DISABLE_CPP_EXCEPTIONS"
      ],
      "dependencies": [
        "<!(node -p \"require('node-addon-api').gyp\")"
      ],
      "conditions": [
        ["OS=='mac'", {
          "libraries": [
            "-F<(module_root_dir)/frameworks",
            "-framework Syphon",
            "-framework Metal",
            "-framework IOSurface",
            "-framework CoreVideo",
            "-framework Foundation",
            "-framework ScreenCaptureKit",
            "-framework AVFoundation",
            "-framework CoreMedia",
            "-framework AppKit",
            "-framework Vision"
          ],
          "xcode_settings": {
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "FRAMEWORK_SEARCH_PATHS": [
              "<(module_root_dir)/frameworks"
            ],
            "OTHER_CFLAGS": [
              "-fobjc-arc",
              "-F<(module_root_dir)/frameworks"
            ],
            "OTHER_CPLUSPLUSFLAGS": [
              "-fobjc-arc",
              "-F<(module_root_dir)/frameworks"
            ],
            "OTHER_LDFLAGS": [
              "-F<(module_root_dir)/frameworks",
              "-framework Syphon",
              "-framework Metal",
              "-framework IOSurface",
              "-framework CoreVideo",
              "-framework Foundation",
              "-framework ScreenCaptureKit",
              "-framework AVFoundation",
              "-framework CoreMedia",
              "-framework AppKit",
              "-framework Vision",
              "-Wl,-rpath,@loader_path/../../frameworks",
              "-Wl,-rpath,@loader_path/../Frameworks"
            ]
          }
        }]
      ]
    }
  ]
}
