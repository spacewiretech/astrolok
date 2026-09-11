# linux

## Purpose

Unmodified `flutter create` scaffolding for a Linux desktop build. **Not a target this project
ships.**

## Files

- `CMakeLists.txt` — the top-level build.
- `runner/` — `main.cc`, `my_application.cc`, `my_application.h`, `CMakeLists.txt`.
- `flutter/` — generated: `generated_plugin_registrant.cc/.h`, `generated_plugins.cmake`,
  `CMakeLists.txt`.

## Notes

- Nothing here has been hand-edited, and the app's payment, camera and analytics dependencies do
  not support Linux — see [../macos/README.md](../macos/README.md), which applies equally.
