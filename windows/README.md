# windows

## Purpose

Unmodified `flutter create` scaffolding for a Windows desktop build. **Not a target this project
ships.**

## Files

- `CMakeLists.txt` — the top-level build.
- `runner/` — `main.cpp`, `flutter_window.cpp/.h`, `win32_window.cpp/.h`, `utils.cpp/.h`,
  `Runner.rc`, `resource.h`, `runner.exe.manifest`, and `resources/app_icon.ico`.
- `flutter/` — generated: `generated_plugin_registrant.cc/.h`, `generated_plugins.cmake`,
  `CMakeLists.txt`.

## Notes

- Nothing here has been hand-edited, and the app's payment, camera and analytics dependencies do
  not support Windows — see [../macos/README.md](../macos/README.md), which applies equally.
- `resources/app_icon.ico` is still Flutter's default, not the Astrolok mark.
