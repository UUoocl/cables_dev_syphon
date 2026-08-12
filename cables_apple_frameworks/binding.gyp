{
  "targets": [
    {
      "target_name": "apple_framework_bridge",
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
        "stream_deck.mm"
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
