<p align="center">
  <img src="assets/icon.png" alt="Screenboom" width="128" height="128">
</p>

<h1 align="center">Screenboom</h1>

<p align="center"><strong>The native, free, and open-source alternative to Screen Studio for macOS.</strong></p>

<p align="center">Make your screen recordings look professional — gradient backgrounds, padding, rounded corners, drop shadow, timeline editing, smooth speed ramping — all from a lightweight native macOS app. No subscriptions, no watermarks, no Electron.</p>

Record your screen with the built-in recorder or QuickTime, import the MP4 into Screenboom, polish it, and export. That's it.

Built with Swift 6.2, SwiftUI, and AVFoundation. Ships as a single native binary.

> **[Download the latest release](https://github.com/rajatady/ScreenBoom/releases/latest)** — grab the `.dmg` from the Releases page.

## Why Screenboom?

Screen Studio costs $89. It's great software, but not everyone can or wants to pay for it. If you're on a Mac and want something native, lightweight, and fast — this is it.

Screenboom is a native macOS app. No web views, no bundled Chromium, no 300MB download. It uses the same AVFoundation and CoreImage pipeline that Apple's own tools use. Your GPU does the work.

## Features

**Visual Effects**
- Background styles — solid color, two-color gradient, mesh gradient (4-corner blend), 10 wallpaper presets, or custom image
- Frame styles — border, gradient border, neon glow, browser chrome, macOS window bar
- Padding — adjustable spacing around the recording (0–200px)
- Rounded corners — smooth corner radius (0–60px)
- Drop shadow — configurable blur radius and opacity

**Timeline Editing**
- Split segments at any point on the timeline
- Disable segments — playback and export skip them entirely
- Per-segment speed control — 0.25x to 32x
- Smooth speed ramping — gradual transitions between segments with different speeds (smoothstep easing, both in preview and export)
- Hover preview — scrub the timeline by hovering without committing the playhead

**Cursor Intelligence**
- Smooth cursor rendering from recorded metadata (Catmull-Rom interpolation)
- Multiple cursor styles — Arrow, Pointer, Crosshair, Circle Dot
- Click ripple effects with customizable color and radius
- Auto-zoom — detects click and keyboard activity clusters, zooms into areas of focus
- Editable zoom regions on the timeline — resize, move, adjust zoom level and focus point
- Cursor interpolation across cuts — smooth bridging at disabled segment boundaries

**Screen Recorder**
- Built-in ScreenCaptureKit recorder — record any display or window
- 30/60 fps capture
- Cursor and keyboard metadata tracking for auto-zoom intelligence

**Multi-Project Editor**
- Manage multiple projects from a welcome screen
- Drag-and-drop or file picker import
- Real-time preview with all effects applied
- Inline rename and delete with hover-reveal actions
- Automatic Undo/Redo for all editing state (Cmd+Z / Cmd+Shift+Z)
- State persistence — projects survive app restarts
- Thumbnail and solid-color timeline view modes
- Multiple output resolutions (720p, 1080p, 1440p, 4K)

**Export**
- H.264 export with resolution-scaled bitrate (20–80 Mbps), 60fps throttle
- Lanczos downscaling for sharp text and UI in screen content
- Source frame rate preserved (no dropped frames)
- Speed changes with smooth ramps at boundaries
- All visual effects (backgrounds, frames, cursor, zoom) applied in export

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

1. Open Screenboom and either **record your screen** or **import an MP4**
2. Adjust background, padding, corners, and shadow in the right panel
3. Split and edit segments on the timeline
4. Hit Export

## Architecture

No external dependencies. Pure Swift + Apple frameworks.

| File | Purpose |
|------|---------|
| `Project.swift` | Core model — all state, multi-project, playback, segments, persistence, undo/redo |
| `ProjectStore.swift` | Multi-project catalog manager — CRUD, migration, persistence |
| `DesignSystem.swift` | Design tokens and reusable UI components |
| `WelcomeView.swift` | Welcome screen — empty state, project grid, hover-reveal actions |
| `ScreenRecorder.swift` | ScreenCaptureKit recorder — display/window capture, AVAssetWriter pipeline |
| `TimelineView.swift` | Timeline UI — thumbnails, segment clips, hover preview, playhead, zoom |
| `BackgroundModels.swift` | Background types, frame styles, wallpaper presets, CodableColor |
| `FrameRenderer.swift` | CIFilter per-frame render pipeline — backgrounds, frames, corners, shadow, cursor |
| `CompositionEngine.swift` | AVMutableComposition builder with speed ramp expansion for export |
| `ControlsPanel.swift` | Tabbed editor panel — appearance, cursor, zoom tabs |
| `ContentView.swift` | Welcome ↔ editor toggle with animated transitions |
| `VideoPreviewView.swift` | NSViewRepresentable wrapping AVPlayerView |

**How rendering works:** Each frame goes through a CIFilter pipeline — source video is scaled and positioned into a padded recording rect, rounded corners applied via luminance mask (`CIBlendWithMask`), cursor and click effects composited, frame overlay added, then composited over shadow and background. Backgrounds and frames are pre-computed once per settings change (cached for mesh/wallpaper). The same pipeline drives both real-time preview (always 4K) and export.

## Roadmap

- [x] Built-in screen recorder (ScreenCaptureKit)
- [x] Multi-project support with welcome screen
- [x] Cursor intelligence — smooth cursor rendering from metadata
- [x] Auto-zoom — click and keyboard detection, editable zoom regions on timeline
- [x] Cursor effects — click ripple indicators, multiple cursor styles
- [x] Background variety — solid, gradient, mesh, wallpapers, custom images
- [x] Frame styles — border, glow, browser chrome, macOS window
- [x] Cursor interpolation across cuts — smooth bridging at segment boundaries
- [ ] Audio support — system audio and microphone
- [ ] Webcam overlay — picture-in-picture with customizable shape and position
- [ ] Annotations — text, arrows, highlights
- [ ] Keyboard shortcut overlay — show key presses on screen
- [ ] Export presets — optimized for Twitter, YouTube, Slack, etc.

## Tech Stack

- **Swift 6.2** with strict concurrency (`MainActor` isolation by default)
- **SwiftUI** for all UI, AppKit interop only for AVPlayerView
- **AVFoundation** — raw AVAsset for preview, AVMutableComposition for export
- **CoreImage** — per-frame CIFilter pipeline for all visual effects
- **AVAssetReader+Writer** — export with CIFilter video composition (respects speed-ramped compositions)
- **JSON persistence** — project state saved to `~/Library/Application Support/Screenboom/`

## Why This Exists

I use this myself. Every client demo, every product walkthrough — it goes through Screenboom. That's the whole reason it'll keep getting updates.

— [Rajat](https://github.com/rajatady)

## Contributing

PRs welcome. Check the roadmap above, pick something, and open an issue before starting so we don't duplicate work.

## License

MIT — free for personal and commercial use. No restrictions, no watermarks, no catches.
