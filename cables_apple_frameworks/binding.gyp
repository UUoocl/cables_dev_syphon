{
  "targets": [
    {
      "target_name": "uvc_controller_core",
      "type": "static_library",
      "sources": [
        "UVCControllerCore/UVCController.m",
        "UVCControllerCore/UVCType.m",
        "UVCControllerCore/UVCValue.m"
      ],
      "include_dirs": [
        "UVCControllerCore/include"
      ],
      "conditions": [
        ["OS=='mac'", {
          "xcode_settings": {
            "MACOSX_DEPLOYMENT_TARGET": "14.0",
            "OTHER_CFLAGS": [
              "-fno-objc-arc"
            ]
          }
        }]
      ]
    },
    {
      "target_name": "apple_framework_bridge",
      "dependencies": [
        "<!(node -p \"require('node-addon-api').gyp\")",
        "uvc_controller_core"
      ],
      "sources": [
        "syphon_bridge.mm",
        "screencapturekit_bridge.mm",
        "vision_bridge.mm",
        "input_bridge.mm",
        "speech_bridge.mm",
        "active_app_bridge.mm",
        "hid_bridge.mm",
        "bmd_speed_editor.mm",
        "contour_shuttle_pro.mm",
        "contour_shuttle_xpress.mm",
        "8bitdo_xbox.mm",
        "XboxControllerCore.m",
        "soomfon_controller.mm",
        "stream_deck.mm",
        "uvc_bridge.mm"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")",
        "UVCControllerCore/include"
      ],
      "defines": [
        "NAPI_DISABLE_CPP_EXCEPTIONS"
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
            "-framework Vision",
            "-framework Speech",
            "-framework CoreAudio",
            "-framework AudioToolbox",
            "-framework IOKit"
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
              "-framework Speech",
              "-framework CoreAudio",
              "-framework AudioToolbox",
              "-framework IOKit",
              "-Wl,-rpath,@loader_path/../../frameworks",
              "-Wl,-rpath,@loader_path/../Frameworks"
            ]
          }
        }]
      ]
    }
  ]
}
