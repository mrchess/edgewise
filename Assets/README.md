# Assets

Drop a 1024×1024 PNG here as `AppIcon.png` and the build will use it for the app icon.

`Scripts/make-icon.swift` picks it up automatically and generates every size the
`.icns` needs. If the file is absent, the script draws a placeholder mark instead, so
the project always builds a complete app bundle.

Artwork that is **fully opaque** is treated as a full-bleed square: it gets inset to
82% and clipped to the macOS icon squircle, so it sits on the canvas the way
first-party icons do. Artwork that already has **transparency** is assumed to be
shaped correctly and is drawn as-is.
