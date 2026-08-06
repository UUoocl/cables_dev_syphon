{
  "targets": [
    {
      "target_name": "syphon_bridge",
      "sources": [
        "syphon_bridge.mm"
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
            "-F<(module_root_dir)/../reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal/lib",
            "-framework Syphon",
            "-framework Metal",
            "-framework IOSurface",
            "-framework CoreVideo",
            "-framework Foundation"
          ],
          "xcode_settings": {
            "FRAMEWORK_SEARCH_PATHS": [
              "<(module_root_dir)/../reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal/lib"
            ],
            "OTHER_CFLAGS": [
              "-fobjc-arc",
              "-F<(module_root_dir)/../reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal/lib"
            ],
            "OTHER_CPLUSPLUSFLAGS": [
              "-fobjc-arc",
              "-F<(module_root_dir)/../reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal/lib"
            ],
            "OTHER_LDFLAGS": [
              "-F<(module_root_dir)/../reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal/lib",
              "-framework Syphon",
              "-framework Metal",
              "-framework IOSurface",
              "-framework CoreVideo",
              "-framework Foundation",
              "-Wl,-rpath,@loader_path/../../../reference/syphon-server-plugin/.deps/obs-deps-2025-08-23-universal/lib",
              "-Wl,-rpath,@loader_path/../Frameworks"
            ]
          }
        }]
      ]
    }
  ]
}
