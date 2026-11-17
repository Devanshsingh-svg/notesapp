# CustomNoteApp — Cross-Platform Flutter Workspace (Android + iPadOS)

Includes:
- **Impeller GPU Rendering & GLSL Shader (`shaders/paper_grain.frag`)**: Batched triangle-strip vector ribbons, Catmull-Rom smoothing, and world-locked graphite grain.
- **Unified Stylus & Touch Engine (`lib/engine/input_controller.dart`)**: Supports S-Pen, USI, DIGIROOT, Logitech Crayon, and touch with palm rejection and velocity-simulated pressure.
- **On-Device ML Kit Handwriting OCR (`lib/services/handwriting_ocr_service.dart`)**: Extracts handwritten text offscreen and indexes it automatically.
- **Offline SQLite FTS5 Search (`lib/services/notebook_search_service.dart`)**: Sub-millisecond prefix search with snippet highlights.
- **Portable `.cnote` ZIP Packaging (`lib/services/cnote_package_service.dart`)**: Exports and imports full multi-page notebooks.
- **Cloud APK Builder (`.github/workflows/build_apk.yml`)**: Automatically builds an installable Android `.apk` on GitHub Actions whenever you push changes.
