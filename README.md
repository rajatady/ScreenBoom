<p align="center">
  <img src=".context/icon.png" alt="Screenboom" width="128" height="128">
</p>

<h1 align="center">Screenboom</h1>

<p align="center"><strong>Make your screen recordings look professional. Native macOS, zero dependencies, fully open source.</strong></p>

Record your screen with QuickTime or Cmd+Shift+5, import the MP4 into Screenboom, add a gradient background, padding, rounded corners, and drop shadow — export a polished video that looks like it came out of Screen Studio. No subscriptions, no watermarks, no Electron.

Built with Swift 6.2, SwiftUI, and AVFoundation. ~700 lines of rendering pipeline. Ships as a single native binary.

## Why Screenboom?

Screen Studio costs $89. It's great software, but not everyone can or wants to pay for it. OpenScreen exists but runs on Electron. If you're on a Mac and want something native, lightweight, and fast — this is it.

Screenboom is a native macOS app. No web views, no bundled Chromium, no 300MB download. It uses the same AVFoundation and CoreImage pipeline that Apple's own tools use. Your GPU does the work.

## Features

**Visual Effects**
- Gradient background — two-color diagonal gradient with presets (Dark, Light, Blue) or custom colors
- Padding — adjustable spacing around the recording (0–200px)
- Rounded corners — smooth corner radius (0–60px)
- Drop shadow — configurable blur radius and opacity

**Timeline Editing**
- Split segments at any point on the timeline
- Disable segments — playback and export skip them entirely
- Per-segment speed control — 0.25x to 32x
- Smooth speed ramping — gradual transitions between segments with different speeds (smoothstep easing, both in preview and export)
- Hover preview — scrub the timeline by hovering without committing the playhead

**Editor**
- Drag-and-drop or file picker import
- Real-time preview with all effects applied
- Undo/Redo (Cmd+Z / Cmd+Shift+Z)
- State persistence — your project survives app restarts
- Thumbnail and solid-color timeline view modes
- Multiple output resolutions (720p, 1080p, 1440p, 4K)

**Export**
- Polished MP4 with all visual effects baked in
- Source frame rate preserved (no dropped frames)
- Speed changes with smooth ramps at boundaries

## Getting Started

### Requirements

- macOS 26.0+ (Tahoe)
- Xcode 26.0+
- Apple Silicon or Intel Mac

### Build & Run

```bash
git clone https://github.com/rajatady/ScreenBoom.git
cd screenboom
xcodebuild -project Screenboom.xcodeproj -scheme Screenboom -configuration Debug build
```

Or open `Screenboom.xcodeproj` in Xcode and hit Cmd+R.

### Usage

1. Record your screen with QuickTime or Cmd+Shift+5
2. Open Screenboom and drag in the MP4 (or use File > Open)
3. Adjust background, padding, corners, and shadow in the right panel
4. Split and edit segments on the timeline
5. Hit Export

## Architecture

8 Swift files, no external dependencies.

| File | Purpose |
|------|---------|
| `Project.swift` | Core model — all state, playback, segments, persistence, undo/redo, export |
| `TimelineView.swift` | Timeline UI — thumbnails, segment clips, hover preview, playhead, zoom |
| `FrameRenderer.swift` | CIFilter per-frame render pipeline — gradient, padding, rounded corners, shadow |
| `CompositionEngine.swift` | AVMutableComposition builder with speed ramp expansion for export |
| `ControlsPanel.swift` | Right sidebar — all visual settings and export button |
| `ContentView.swift` | Import screen (drag-and-drop) and editor layout (HSplitView) |
| `VideoPreviewView.swift` | NSViewRepresentable wrapping AVPlayerView |
| `ScreenboomApp.swift` | App entry point with undo/redo commands |

**How rendering works:** Each frame goes through a CIFilter pipeline — source video is scaled and positioned into a padded recording rect, rounded corners are applied via a grayscale luminance mask (`CIBlendWithMask`), then composited over a pre-computed shadow and diagonal gradient background. The same pipeline drives both the real-time preview and the export.

## Roadmap

- [ ] Built-in screen recorder (ScreenCaptureKit) — no more QuickTime dependency
- [ ] Cursor tracking — separate cursor metadata for smooth cursor rendering
- [ ] Auto-zoom — click detection, dwell tracking, smooth camera follow
- [ ] Cursor effects — click indicators, cursor scaling, trail effects
- [ ] Audio support — system audio and microphone
- [ ] Webcam overlay — picture-in-picture with customizable shape and position
- [ ] Background options — wallpapers, images, solid colors (not just gradients)
- [ ] Annotations — text, arrows, highlights
- [ ] Keyboard shortcut overlay — show key presses on screen
- [ ] Export presets — optimized for Twitter, YouTube, Slack, etc.

## Tech Stack

- **Swift 6.2** with strict concurrency (`MainActor` isolation by default)
- **SwiftUI** for all UI, AppKit interop only for AVPlayerView
- **AVFoundation** — raw AVAsset for preview, AVMutableComposition for export
- **CoreImage** — per-frame CIFilter pipeline for all visual effects
- **AVAssetExportSession** — export with CIFilter video composition
- **JSON persistence** — project state saved to `~/Library/Application Support/Screenboom/`

## Why This Exists

I use this myself. Every client demo, every product walkthrough — it goes through Screenboom. That's the whole reason it'll keep getting updates.

— [Rajat](https://github.com/rajatady)

## Contributing

PRs welcome. Check the roadmap above, pick something, and open an issue before starting so we don't duplicate work.

## License

MIT — free for personal and commercial use. No restrictions, no watermarks, no catches.
