# Screenboom — Sacred Context (Full History)

> This document is the COMPLETE memory of the Screenboom project. If you are a future Claude session reading this, you have ZERO in-memory context. Everything you need is here. Read it fully before doing anything.

---

## Part 1: The Full Conversation History — How We Got Here

### The Original Ask

Rajat wanted to build a **complete Screen Studio clone** — a screen recorder, editor, and exporter with 1:1 feature mapping. His exact words: "No fluff, no let's take the simple approach, no let's build in phases. No let's make it work simply first. The complete app, with all the features and editor and exporter."

He needed to record his Mac screen **right now** — specifically recording between a Chrome window and a native Figma window. Then edit and export a polished video to send to a client.

### My Initial Assessment

I confirmed his setup: macOS 26.2, M3 Pro, Metal 4, Swift 6.2, Xcode 26.2. I laid out what I could build. I was honest about challenges: ~8000+ lines, runtime bugs, auto-zoom tuning.

### The "Things You Don't Know"

I explained Screen Studio's implicit features: cursor smoothing (Bézier interpolation on raw cursor metadata), auto-zoom (5 systems: click, dwell, hysteresis, easing, boundary clamping), recording more than export (full-res with virtual camera viewport), cursor interpolation across cuts, speed ramping, background treatment (the core visual identity), click indicators, cursor scaling/fading.

### The Pragmatic Compromise

We agreed on the **quick editor path**:
1. Record with QuickTime/Cmd+Shift+5 (cursor baked into pixels)
2. Build a focused editor: import MP4, split/delete/speed segments, background/padding/rounded corners/shadow, export
3. No cursor intelligence (data not available in imported MP4)
4. Background treatment alone makes it look professional

**The full recorder is still the ultimate goal** — Rajat only accepted this sequencing because he needed to send a video TODAY.

### Initial Build

Rajat created the Xcode project ("Screenboom"). I wrote 8 source files, **BUILD SUCCEEDED** first try.

### Session 1 Iteration Cycle

1. **Timeline zoom**: 1x-20x slider + horizontal ScrollView
2. **State persistence**: SavedState Codable JSON, security-scoped bookmarks, debounced saves
3. **Timeline interaction bugs**: Two iterations — first separated gestures (broke scrubbing), then unified model where every click/drag both seeks AND selects

---

## Part 2: Session 2 — Major Architecture Changes

### Disabled Segments: Simpler Than Dual Timeline

Rajat initially asked for a dual timeline (reference above, active below). But then proposed a **much simpler approach**: keep one timeline, playback auto-skips disabled segments, scrubbing works everywhere.

**Implementation**:
- **Player uses raw asset directly** (not AVMutableComposition) for preview — all frames accessible including disabled segments
- Added `handlePlaybackSegmentLogic(at:)` — time observer skips disabled segments during playback, adjusts `player.rate` per segment speed
- `togglePlayback()` — if starting play from disabled segment, skips to next enabled
- Export still uses composition (only enabled segments, speed baked in via `scaleTimeRange`)
- Removed `currentComposition` property — player no longer needs it

### Hover Preview on Timeline

Rajat wanted hover to scrub the preview without moving the red playhead.

**Implementation**:
- Added `playheadTime: Double` to Project — the committed position (set by clicks, playback)
- `currentTime` = volatile, whatever the player is showing (hover position, or playhead during playback)
- Red playhead displays at `playheadTime`
- `onContinuousHover` on the timeline ZStack — seeks preview on hover, sets `currentTime` immediately
- On hover end: just clears the visual indicator, does NOT snap back (so preview stays at last hovered frame — critical for Split workflow)
- White semi-transparent hover indicator line

### Split Precision — Three Bugs Found and Fixed

**Bug 1: `seek(toFraction:)` used `playerItem.duration`**
`playerItem.duration` can be `.indefinite` after `rebuildPlayer()` creates a new item. Fixed to use `project.duration` (always correctly loaded).

**Bug 2: `currentTime` lagged behind the visual**
Set by async time observer at 30fps. Fixed by setting `currentTime` immediately in hover and click handlers (before the seek, not waiting for observer).

**Bug 3: Split used wrong time (THE MAIN BUG)**
When mouse moves from timeline to Split button, `onContinuousHover` fires for every position crossed on the way out. `currentTime` gets updated to some random position as the mouse leaves the timeline, NOT where the user intended.

**Fix**: Split button uses `playheadTime` (committed by clicking on timeline), not `currentTime` (volatile):
```swift
Button("Split") {
    project.addSplit(at: project.playheadTime)
}
```

### Disabled State Lost on Split — rebuildSegments Bug

**The bug**: `rebuildSegments()` used exact boundary matching to find existing segments. When splitting `[0-10]` disabled segment at time 5, new segments `[0-5]` and `[5-10]` couldn't match `[0-10]` exactly. Both defaulted to `isEnabled: true`. **Every split destroyed disabled state of ALL segments.**

**Fix**: Containment lookup — find old segment that CONTAINS the new range:
```swift
let existing = segments.first {
    $0.startTime <= times[i] + 0.02 && $0.endTime >= times[i + 1] - 0.02
}
```

Also removed unnecessary `rebuildPlayer()` calls from `rebuildSegments()`, `toggleSegment()`, `setSpeed()` — with raw-asset playback, the player doesn't need rebuilding when segments change.

### Rendering Artifacts — Bleeding Edges and Jitter

**Bleeding lines at top/bottom**: `clampedToExtent()` repeated edge pixels of every video frame infinitely. During fast scrolling, high-contrast edge pixels smeared outward past the rounded corner mask.

**Fix**: Removed `clampedToExtent()`, replaced with `.cropped(to: videoRect)` after positioning. Hard boundary, no repeated pixels.

**Frame jitter/flickering**: `frameDuration` hardcoded to 30fps. Source recording from Cmd+Shift+5 on M3 Pro is 60fps. Composition dropped every other frame.

**Fix**: Match source frame rate via `track.nominalFrameRate`.

### Export Missing Visual Effects

Export used manual AVAssetReader+Writer pipeline which didn't apply CIFilter video compositions properly. **Fixed by replacing with `AVAssetExportSession`** which properly renders CIFilter effects:
```swift
let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
session.outputURL = url
session.outputFileType = .mp4
session.videoComposition = videoComp
await session.export()
```

### Title Bar Feature

Rajat requested a thin 4-5px decorative bar at top of the rendered video to make it look like a macOS window.

**Implementation** in FrameRenderer:
- 5px semi-transparent white bar (`alpha: 0.08`) at top of recording rect
- Video content positioned in `videoRect` (below title bar)
- Bar is inside the rounded corner mask

### Timeline Visual Improvements

- **Split gaps with rounded corners**: 4px gaps between segments at split points, each segment clip has rounded corners
- `segmentShapes` mask applied to thumbnail strip
- `segmentVisualFrame` helper computes per-segment position with gap insets
- Removed yellow split markers (gaps ARE the markers)
- Subtle borders on all segments (0.5px gray), thicker accent border on selected
- Speed badge moved to bottom of segment
- Red playhead glow (shadow)
- Toggle for thumbnail vs solid color timeline view (`showThumbnails` property)

### Undo/Redo System

Added undo/redo to Project with Cmd+Z/Cmd+Shift+Z:
- `undoStack` and `redoStack` arrays of `SavedState`
- `pushUndoState()` called before mutations
- `undo()` and `redo()` restore from stacks
- Wired up in ScreenboomApp.swift via `.commands` modifier

### Speed Options Expanded

Speed picker now includes: 0.25x, 0.5x, 0.75x, 1x, 1.2x, 1.4x, 1.6x, 1.8x, 2x, 3x, 4x, 6x, 8x, 16x, 24x, 32x

---

## Part 3: Current Architecture

### Tech Stack
- **Swift 6.2**, Xcode 26.2, macOS 26.2 (Tahoe), M3 Pro, Metal 4
- **SwiftUI** with AppKit interop (NSViewRepresentable for AVPlayerView)
- **AVFoundation**: Raw AVAsset for preview, AVMutableComposition for export, AVVideoComposition with CIFilter handler
- **CoreImage**: Per-frame render pipeline
- **@Observable** (Observation framework), NOT SwiftData
- **JSON persistence** in ~/Library/Application Support/Screenboom/

### Xcode Project Config
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all code is MainActor by default, use `nonisolated` to opt out
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` — concurrency errors become warnings
- `PBXFileSystemSynchronizedRootGroup` — files in `Screenboom/` auto-discovered, no .pbxproj edits
- `ENABLE_USER_SELECTED_FILES = readwrite` — changed from `readonly` for NSSavePanel export
- `ENABLE_APP_SANDBOX = YES`
- Bundle ID: `com.trymagically.Screenboom`

### File Structure
```
/Users/kumardivyarajat/WebstormProjects/screenboom/
├── Screenboom.xcodeproj/
├── Screenboom/
│   ├── ScreenboomApp.swift      — @main, creates Project, WindowGroup, undo/redo commands
│   ├── ContentView.swift        — Import view (drag+drop, file picker) OR editor (HSplitView)
│   ├── Project.swift            — @Observable model: ALL state, playback, segments, persistence, export, undo/redo
│   ├── VideoPreviewView.swift   — NSViewRepresentable wrapping AVPlayerView
│   ├── TimelineView.swift       — Timeline: thumbnails, segment clips with gaps, hover preview, playhead, zoom
│   ├── ControlsPanel.swift      — Right sidebar: gradient, padding, corners, shadow, resolution, export
│   ├── FrameRenderer.swift      — CIFilter pipeline: title bar, scale+crop source, rounded corners, shadow, gradient
│   ├── CompositionEngine.swift  — Build AVMutableComposition for export, AVAssetExportSession export
│   └── Assets.xcassets/
├── SCREENBOOM-CONTEXT.md        — THIS FILE
├── ScreenboomTests/
└── ScreenboomUITests/
```

### Key Architecture Decisions

**Preview uses raw asset, export uses composition**:
- Preview: `AVPlayerItem(asset: rawAsset)` with `AVVideoComposition` for visual effects. All frames accessible. Time observer handles skipping disabled segments and speed adjustment.
- Export: `CompositionEngine.buildComposition()` assembles only enabled segments with speed via `scaleTimeRange`. `AVAssetExportSession` applies CIFilter video composition.

**Two time properties**:
- `playheadTime` — committed position, set by clicking timeline or during playback. Red playhead displays this. Split button uses this.
- `currentTime` — volatile, whatever the player is showing. Updated by hover, playback, clicks. Time display shows this.

### Render Pipeline (FrameRenderer.swift)

Pre-computed per settings change:
- `calculateRecordingRect()` — where source fits within padded output
- `createRoundedRectMask()` — grayscale CGContext image, white inside rounded rect
- `createShadow()` — blur mask, offset down 8px, CIColorMatrix for black-with-alpha
- `createGradient()` — CILinearGradient diagonal
- Title bar: 5px semi-transparent white bar at top of recording rect
- `videoRect` = recording rect minus title bar height

Per-frame in CIFilter handler:
- Scale source to fit videoRect (NOT recRect — title bar takes top 5px)
- Position centered, crop to videoRect (NO `clampedToExtent` — causes bleeding)
- Composite title bar over video
- Apply rounded corners via CIBlendWithAlphaMask
- Composite: recording over shadow over gradient background
- Crop to output rect

Frame rate: matches source via `track.nominalFrameRate` (not hardcoded 30fps)

### Timeline Interaction Model

**Click/drag** (`handleTimelineInteraction`):
1. Compute `fraction = x / width`, `sourceTime = fraction * duration`
2. Find segment at sourceTime → select it
3. Set `playheadTime = sourceTime` and `currentTime = sourceTime` (immediate, no async wait)
4. Seek player to fraction

**Hover** (`onContinuousHover`):
1. Compute fraction, set `currentTime = fraction * dur` (immediate)
2. Seek player to fraction (preview updates)
3. On hover end: clear visual indicator only, DON'T snap back (preview stays)

**Split**: Uses `playheadTime` (committed position), NOT `currentTime` (volatile)

**Playback**: Time observer updates both `currentTime` and `playheadTime`, calls `handlePlaybackSegmentLogic` to skip disabled and adjust speed

### Segment Management

`rebuildSegments()` — called after add/remove split:
- Uses **containment lookup** (NOT exact boundary match) to find parent segment
- New segments inherit speed/isEnabled from the old segment that contains them
- Does NOT call `rebuildPlayer()` (unnecessary with raw-asset playback)

`toggleSegment()` / `setSpeed()`:
- Just update the array and save state
- Do NOT call `rebuildPlayer()` — time observer reads segments directly

---

## Part 4: Bugs Fixed (Full List)

1. **Segment tap swallowed by DragGesture** → unified interaction model
2. **Seeking broke after segment fix** → all overlays `allowsHitTesting(false)`
3. **Async seek build error** → added `await`
4. **`seek(toFraction:)` used `playerItem.duration`** → use `project.duration` (always correct)
5. **`currentTime` lagged behind visual** → set immediately in handlers before async seek
6. **Split at wrong position (mouse crossing timeline to button)** → Split uses `playheadTime` not `currentTime`
7. **Disabled state lost on split** → containment lookup in `rebuildSegments()` instead of exact boundary match
8. **Unnecessary `rebuildPlayer()` calls** → removed from segment mutation methods
9. **Bleeding edge artifacts** → removed `clampedToExtent()`, crop to videoRect instead
10. **Frame jitter from 30fps hardcode** → match source `nominalFrameRate`
11. **Export missing visual effects** → replaced AVAssetReader+Writer with `AVAssetExportSession`

---

## Part 5: Rajat's Preferences & Working Style

- **No fluff, no phases**: Wants the complete thing. Accepted editor-first only because of immediate deadline.
- **Values time above all**: Don't waste cycles. Tell him what you need FIRST. He's spent 6+ hours on what was supposed to be 1 hour — he's frustrated.
- **DO NOT CODE WITHOUT PERMISSION**: He explicitly said "do not code at all without my permission" after multiple bugs were introduced by speculative fixes. **Always explain the problem and proposed fix, get his OK, THEN code.**
- **Implicit UX matters**: Things should "just work" like Screen Studio. Think cohesively.
- **He'll interrupt**: Listen to interruptions. Don't continue down wrong paths.
- **Sacred context**: This document is sacred. Capture EVERYTHING.
- **From his CLAUDE.md**: "Never jump to coding. ALWAYS Think very very carefully before implementing."
- **His company**: trymagically (bundle ID com.trymagically.Screenboom)

---

## Part 6: Screen Studio Deep Knowledge (for V2)

### What Screen Studio Records
- Video frames via ScreenCaptureKit with `showsCursor: false` (NO cursor in raw video)
- Cursor X,Y positions at high frequency as SEPARATE METADATA (via CGEvent taps)
- Click timestamps and positions, scroll events
- All in proprietary project format, NOT in exported MP4

### Why Imported MP4s Can't Have Cursor Intelligence
- QuickTime/Cmd+Shift+5 bakes cursor INTO pixel data
- No separate metadata exists
- Must build our own recorder to get cursor metadata

---

## Part 7: Build & Run

```bash
# Build
xcodebuild -project /Users/kumardivyarajat/WebstormProjects/screenboom/Screenboom.xcodeproj -scheme Screenboom -configuration Debug build

# Or Cmd+R in Xcode
```

State file: `~/Library/Application Support/Screenboom/project-state.json`

---

## Part 8: Session 3 — Speed Ramping, Corner Radius Fix, Disabled Frame Fix

### Title Bar Removed
User tested and didn't like the 5px decorative bar. Removed — video now fills full recording rect.

### Corner Radius Fix (THE ROOT CAUSE)
Corner radius NEVER worked since initial build. The mask was a **grayscale image** (`CGImageAlphaInfo.none`), but the CIFilter was `CIBlendWithAlphaMask` which uses the **alpha channel** (not luminance). No alpha channel → alpha = 1 everywhere → no rounding visible.

**Fix**: Changed `CIBlendWithAlphaMask` → `CIBlendWithMask`. The latter uses **luminance** (brightness) to blend — white = show video, black = show background. Exactly what the grayscale mask provides.

### Smooth Speed Ramping at Segment Transitions

**Preview (Project.swift)**:
- Timer-based ramp at 60fps, 0.3s duration, smoothstep easing (`t² × (3 - 2t)`)
- `startSpeedRamp(to:)` gradually interpolates `player.rate` from current to target
- `handlePlaybackSegmentLogic` calls `startSpeedRamp` instead of instant `player.rate` change
- Ramp cancels on: pause, player rebuild, disabled segment skip
- If new boundary hit mid-ramp, starts fresh ramp from current interpolated rate

**Export (CompositionEngine.swift)**:
- `expandWithRamps()` pre-processes segments before composition building
- At each boundary with different speeds, creates a 0.3s ramp zone (0.15s per side)
- Each half-zone split into 5 micro-segments with smoothstep-interpolated speeds
- Total 10 micro-steps per boundary, same insertion + `scaleTimeRange` mechanism
- Edge cases: short segments limit ramp to half segment duration

### Disabled Frame Flash Fix
Speed ramping caused brief flash of disabled frames — time observer at 30fps couldn't catch boundary crossing fast enough.

**Fix**: Added `addBoundaryTimeObserver(forTimes:)` at the start time of every disabled segment. Fires at the **exact** frame boundary, instantly seeks past disabled content.
- `updateBoundaryObservers()` called from: `rebuildPlayer()`, `toggleSegment()`, `rebuildSegments()`, `restoreSnapshot()`
- Boundary observer removed when player rebuilt or segments change

### Bugs Fixed (continued from Part 4)
12. **Corner radius invisible** → wrong CIFilter (`CIBlendWithAlphaMask` → `CIBlendWithMask`)
13. **Disabled frame flash during playback** → boundary time observers for precise skip
14. **Title bar removed** — user didn't like it

---

## Part 9: Current Status & What Needs Testing

### Confirmed Working (user tested):
- Bleeding artifacts fix ✓
- Padding ✓
- Shadow radius ✓
- Shadow opacity ✓
- Export with visual effects ✓
- Corner radius ✓
- Smooth speed ramping (preview + export) ✓
- Disabled frame flash fix ✓
- Title bar removed ✓

### What To Do Next
1. V2 recorder with cursor intelligence
2. Any additional polish/features user requests
