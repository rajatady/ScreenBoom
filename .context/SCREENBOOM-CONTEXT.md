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

## Part 9: Session 4 — Multi-Project Support, Design System, Recording Fix

### Multi-Project Architecture

Screenboom now supports multiple projects. Each project has its own directory with state and thumbnail.

**New files:**
- `ProjectInfo.swift` — Codable, Identifiable, Sendable, Equatable struct. Fields: `id`, `name`, `createdAt`, `lastOpenedAt`, optional video metadata (`videoWidth`, `videoHeight`, `videoDurationSeconds`, `sourceFileName`). Extensible — future optional fields decode gracefully from old JSON.
- `ProjectStore.swift` — `@Observable` class managing `[ProjectInfo]`, persisted to `projects.json`. Dependency-injected `baseDirectory` for test isolation. Path helpers: `projectDirectory(for:)`, `stateFileURL(for:)`, `thumbnailURL(for:)`. CRUD: `add`, `remove`, `update`, `touchLastOpened`. Always sorted by `lastOpenedAt` descending. `migrateIfNeeded()` moves legacy `project-state.json` → `projects/{uuid}/state.json` (idempotent).
- `WelcomeView.swift` — Welcome screen with two states: empty (app icon, title, tagline, import/record buttons) and project grid (LazyVGrid of ProjectCards with thumbnails, metadata chips, hover effects, context menus).
- `DesignSystem.swift` — Abstracted design tokens (`SB` namespace): `SB.Colors`, `SB.Typo`, `SB.Space`, `SB.Radius`. Reusable components: `SBCardModifier`, `SBSectionLabel`, `SBChip`, `SBPrimaryButton`, `SBSecondaryButton`, `SBPageBackground`, `SBPulsingDot`. All screens use this — change tokens to reskin the entire app.
- `ProjectStoreTests.swift` — 11 test cases covering ProjectInfo round-trip, forward compatibility, ProjectStore CRUD, sorting, path derivation, catalog persistence. All use temp directory via dependency injection.

**Disk layout:**
```
~/Library/Application Support/Screenboom/
    projects.json                    ← catalog
    projects/{uuid}/state.json       ← per-project SavedState
    projects/{uuid}/thumbnail.jpg    ← generated on closeProject
    projects/{uuid}/recording.mp4    ← recordings copied here from temp
```

### Project.swift Changes

- `SavedState`: `fileURL` → `legacyFileURL`. `write()` → `write(to:)`. `load()` → `load(from:)`. Parent directory auto-created on write.
- New properties: `currentProjectID: UUID?`, `store: ProjectStore?`, `onVideoLoaded: ((UUID, CGSize, Double) -> Void)?`
- `init()` is now empty — no `restoreState()`. WelcomeView drives loading.
- `writeStateNow()` writes to `store.stateFileURL(for: projectID)`. Guard on both being non-nil. Bookmark creation tries `.withSecurityScope` first, falls back to regular (for app-owned recordings).
- `loadProject(info:store:)` — loads SavedState from per-project path, restores video via bookmark (tries security-scoped, then regular), fires `onVideoLoaded` after track loading, calls `store.touchLastOpened`.
- `createProject(url:store:)` — creates ProjectInfo, adds to store, calls `loadVideo`.
- `createProject(session:store:)` — creates ProjectInfo, adds to store, calls `loadRecording`.
- `closeProject()` — calls `writeStateNow()`, generates thumbnail (JPEG at 33% mark via AVAssetImageGenerator, async fire-and-forget), clears all state including `currentProjectID`.
- `loadRecording(session:)` — copies video from temp to `projects/{uuid}/recording.mp4` so it persists beyond temp cleanup.

### ContentView.swift Changes

- Accepts `store: ProjectStore`.
- Shows `WelcomeView(project:store:)` when no project is open (`currentProjectID == nil || asset == nil`).
- Shows editor when both are non-nil.
- Removed `showingImporter`, `fileImporter`, `openWindow` (moved to WelcomeView).

### ScreenboomApp.swift Changes

- Added `@State private var projectStore = ProjectStore()`.
- Passes `store` to ContentView.
- `.onAppear`: `projectStore.migrateIfNeeded()`, wires `project.onVideoLoaded` callback to update ProjectInfo with video metadata.
- Recorder callback: `project.createProject(session:store:)` instead of `project.loadRecording(session:)`.

### Recording Bug Fix (ScreenRecorder.swift)

**Root cause:** `StreamOutput.stream(_:didOutputSampleBuffer:of:)` appended ALL sample buffers including ScreenCaptureKit's status-only frames (no pixel data). These corrupted the AVAssetWriter, causing `finishWriting()` to fail.

**Fix:**
1. Added `guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }` — only process frames with actual pixels.
2. Simplified guard to `guard assetWriter.status == .writing else { return }` — cleaner than the old `|| !sessionStarted` logic.
3. Added `StreamDelegate` (SCStreamDelegate) to catch stream errors via `didStopWithError`.
4. Added 100ms flush delay before `markAsFinished()`.
5. Better error messages including writer status code.
6. Default frame rate changed to 60fps.
7. Added `includeCamera: Bool` property (UI toggle present, implementation pending).
8. Added `refreshWindows()` for manual window list refresh.

### RecorderWindow.swift Redesign

- Uses design system throughout (`SB.Typo`, `SB.Space`, `SB.Colors`, `SBSectionLabel`, `SBPrimaryButton`, etc.).
- Window picker shows `"AppName — WindowTitle"` format.
- Refresh button on window picker.
- Camera overlay toggle (disabled, "Coming soon" label).
- Cursor tracking toggle with icon.
- Unified transition view for preparing/stopping states.
- Completed state shows metadata chips instead of text lines.

### Bugs Fixed (continued)
15. **Recording failed every time** → StreamOutput was appending status-only frames without pixel data → added `CMSampleBufferGetImageBuffer` guard
16. **Missing SCStreamDelegate** → stream errors were silently ignored → added StreamDelegate class
17. **Recorded projects couldn't reopen** → temp file bookmarks failed → copy recordings to project directory + dual bookmark strategy (security-scoped then regular)
18. **`Type` naming conflict** → `SB.Type` conflicted with Swift metatype expression → renamed to `SB.Typo`

---

## Part 10: Current File Structure

```
Screenboom/
├── ScreenboomApp.swift        — @main, Project + ProjectStore, undo/redo, recorder callback
├── ContentView.swift          — WelcomeView ↔ Editor toggle
├── WelcomeView.swift          — Empty state / project grid
├── Project.swift              — @Observable model: ALL state, multi-project, playback, segments, persistence, export
├── ProjectInfo.swift          — Project metadata struct
├── ProjectStore.swift         — Multi-project catalog manager
├── DesignSystem.swift         — Design tokens and reusable UI components
├── VideoPreviewView.swift     — NSViewRepresentable wrapping AVPlayerView
├── TimelineView.swift         — Timeline: thumbnails, segments, hover, playhead, zoom
├── ControlsPanel.swift        — Right sidebar: gradient, padding, corners, shadow, resolution, export
├── FrameRenderer.swift        — CIFilter pipeline: scale+crop, rounded corners, shadow, gradient
├── CompositionEngine.swift    — AVMutableComposition + export + speed ramp expansion
├── ScreenRecorder.swift       — ScreenCaptureKit recorder + StreamOutput + StreamDelegate
├── RecorderWindow.swift       — Recorder UI (configuration, recording, completed, failed states)
├── RecordingModels.swift      — CursorEvent, CursorMetadataFile, RecordingSession
├── CursorTracker.swift        — NSEvent global monitors for cursor + keyboard metadata
├── CursorOverlayEngine.swift  — Cursor processing: smoothing, rendering, click effects, ZoomRegion, auto-zoom, time remap
└── Assets.xcassets/
```

---

## Part 11: Session 5 — Imported Project Fix, Design System V2, Glass Tabs

### Imported Project Fix

**Root cause:** `bookmarkData(options: [.withSecurityScope])` AND `bookmarkData(options: [])` both silently fail for certain imported files (likely sandbox/entitlement mismatch). The bookmark is stored as nil, so reopening finds no bookmark.

**Fix:**
- Added `sourceURLPath: String?` to `SavedState` — stores the raw file path alongside the bookmark
- `writeStateNow()` now saves `sourceURL?.path` and logs bookmark creation failures via `os.Logger`
- `loadProject()` tries bookmark first (security-scoped, then regular), then falls back to file path
- For non-sandboxed apps, the path fallback always works

### Design System V2 (Airbnb-inspired + liquid glass)

Complete overhaul of the design system for warmth, delight, and glass aesthetics.

**Colors** — warm palette:
- Background: `Color(red: 0.09, green: 0.09, blue: 0.10)` — warm charcoal, not cold gray
- Accent: `Color(red: 1.0, green: 0.35, blue: 0.37)` — coral (Airbnb-inspired)
- Text: warm whites (`0.95`, `0.62`, `0.40` for primary/secondary/tertiary)
- Semantic: warm success/warning/destructive colors

**Typography** — all `.rounded` design:
- Every font uses `.design(.rounded)` for warmth
- Timer uses `.ultraLight` weight for elegance

**New components:**
- `SBGlassTabs` — liquid glass segmented control with material backgrounds, hover effects, spring animation. Used for background presets (Dark/Light/Ocean) in ControlsPanel.
- `SBIconButton` — circular icon button with `.ultraThickMaterial` background, scale spring on hover, destructive variant. Used for hover-reveal card actions.
- `SBGlassPanel` — `.ultraThinMaterial` background with subtle leading edge highlight. Used for ControlsPanel sidebar.

**Updated components:**
- `SBPrimaryButton` — capsule shape, custom hover glow + shadow, spring scale
- `SBSecondaryButton` — capsule shape with border, opacity-based hover
- `SBCardModifier` — `.ultraThinMaterial` fill, gradient border (brighter top-left), `.continuous` corner style
- `SBChip` — capsule shape instead of rounded rect
- `SBPageBackground` — dual ambient glow (coral top-left, purple bottom-right)

**Animation tokens** (`SB.Anim`):
- `springSnappy` — 0.3s, bounce 0.15
- `springGentle` — 0.4s, bounce 0.1
- `springBouncy` — 0.5s, bounce 0.25
- `fadeQuick` — 0.15s ease-out
- `fadeMedium` — 0.25s ease-in-out

**New radius:** `SB.Radius.pill = 100` for capsule shapes

### WelcomeView Redesign

- **No context menus** — replaced with hover-reveal icon buttons (pencil for rename, trash for delete)
- Hover reveals action icons in top-right of card thumbnail (like Airbnb's heart icon)
- Inline rename: pencil icon → text field replaces name, press Enter to commit
- Delete: trash icon → confirmation dialog
- Cards are 250-320pt adaptive grid, 160pt thumbnail height
- Spring animations on hover (`withAnimation(SB.Anim.springSnappy)`)
- Namespace passed through for `matchedGeometryEffect` hero transitions

### ContentView Redesign

- `@Namespace` for hero transitions between card thumbnail and editor video preview
- `ZStack` with asymmetric transitions (scale 0.97 in, 1.02 out)
- Glass-backed toolbar (`.ultraThinMaterial`)
- Back button uses `SBSecondaryButton` instead of plain button

### ControlsPanel Redesign

- Uses `SBGlassPanel` for glass sidebar background
- Section labels use `SBSectionLabel`
- Color presets use `SBGlassTabs` instead of buttons (fixes text wrapping in 280px panel)
- Preset detection: compares current gradient colors to presets to highlight active tab
- Slider rows with label/value display, accent-tinted
- Export button uses `SBPrimaryButton`

### RecorderWindow Updates

- Explicit `foregroundStyle(SB.Colors.textPrimary)` on all text
- Accent-tinted progress views and toggles
- All spacing uses `SB.Space` tokens

### CI/CD

- Added `.github/workflows/release.yml` — GitHub Actions workflow for DMG releases
- Triggers on `v*` tag push
- Builds Release binary on macOS runner
- Creates DMG with Applications symlink (drag-to-install)
- Uploads DMG to GitHub Release with auto-generated notes

### Bugs Fixed (continued)
19. **Imported projects wouldn't reopen** → bookmark nil, added `sourceURLPath` fallback
20. **Preset buttons text wrapping** → replaced with `SBGlassTabs` glass segmented control
21. **`os.Logger` for diagnostics** → `print()` doesn't show in Xcode console, `Logger` does

---

## Part 12: Session 6 — Cursor Intelligence, Auto-Zoom, Click Effects

### New File: `CursorOverlayEngine.swift`

Central processing engine for cursor intelligence. All `nonisolated static` for CIFilter handler thread safety.

**Data types**: `SmoothedCursorPoint`, `CursorClick`, `CursorSettings` (Codable), `CursorStyle` enum (arrow/pointer/crosshair/circleDot), `AutoZoomSensitivity` enum (subtle/balanced/dramatic), `ZoomKeyframe`, `CursorOverlayState` (@unchecked Sendable — immutable pre-computed state), `TimeRemapEntry`, `TimeRemapTable`.

**Key algorithms**:
1. **Centripetal Catmull-Rom smoothing** (alpha=0.5) — smooths raw 120Hz cursor events into fluid positions, re-sampled at output frame rate
2. **Binary search per-frame lookup** — O(log n) cursor position at any timestamp
3. **Cursor image pre-rendering** — NSCursor.arrow/.pointingHand/.crosshair rendered to CIImage once, repositioned per frame
4. **Circle-dot custom cursor** — CGContext-rendered ring + center dot
5. **Click ripple effects** — expanding ring animation using smoothstep easing, rendered via CGContext per frame
6. **Auto-zoom keyframe generation** — clusters clicks by temporal proximity per sensitivity preset, generates zoom-in/hold/zoom-out keyframes with smoothstep interpolation
7. **Coordinate mapping** — NSEvent (bottom-left) → video (top-left) → CIImage (bottom-left) triple flip
8. **Export time remapping** — re-samples cursor events at composition time (accounting for speed changes)

### Changes to Existing Files

**RecordingModels.swift**: Added `CodablePoint` struct and `captureOrigin: CodablePoint?` to `CursorMetadataFile` (optional for backward compat with existing recordings).

**CursorTracker.swift**: Added `captureOrigin: CGPoint` property. Passed to `writeMetadata()` → stored in JSON.

**ScreenRecorder.swift**: Sets `cursorTracker.captureOrigin` from display frame or window frame before starting tracker.

**FrameRenderer.swift**: `makeVideoComposition` now accepts `cursorOverlayState: CursorOverlayState? = nil`. Pipeline is now:
```
source → [auto-zoom crop] → scale+position → rounded corners → [cursor+click overlay] → shadow → background → final crop
```

**Project.swift**:
- New properties: `cursorSettings`, `cursorOverlayState`, `cursorMetadata`, `hasCursorData`
- New methods: `loadCursorMetadata()`, `rebuildCursorOverlay()`
- `loadRecording()` now copies cursor JSON to project dir + calls `loadCursorMetadata()`
- `loadProject()` checks for `recording.cursor.json` in project dir
- `rebuildPlayer()` and `updateVisuals()` pass `cursorOverlayState` to FrameRenderer
- `runExport()` builds `TimeRemapTable` and creates export-remapped cursor state
- `closeProject()` clears cursor state
- `SavedState` extended with 10 optional cursor settings fields (backward compatible)

**CompositionEngine.swift**: Added `buildTimeRemapTable(segments:)` — walks expanded speed-ramped segments to build composition → source time mapping at 60 samples/second.

**ControlsPanel.swift**: Three new sections (conditional on `hasCursorData`):
- **Cursor**: toggle, style tabs (Arrow/Pointer/Cross/Dot), size slider (0.5x-3.0x)
- **Click Effect**: toggle, ring size slider
- **Auto Zoom**: toggle, sensitivity tabs (Subtle/Balanced/Dramatic), zoom level slider (1.5x-4.0x)

### Bugs Fixed (continued)
22. **CGContext API names** → `strokeEllipseIn` → `strokeEllipse(in:)`
23. **MainActor isolation** → `nonisolated` on all `AutoZoomSensitivity`/`CursorStyle` computed properties
24. **Duplicate safe subscript** → removed private extension, inlined bounds checks
25. **Cursor metadata not persisted** → copy `.cursor.json` alongside recording to project dir

---

## Part 13: Session 7 — Zoom Track on Timeline, Keyboard Auto-Zoom, Export Quality, Toolbar Restructure

### Keyboard Input Tracking for Auto-Zoom

CursorTracker now monitors `.keyDown` events (throttled to 4/sec via `keyInterval = 1.0/4.0`). Records cursor position at key event time — we care about WHERE typing happens, not WHAT. `CursorEvent.EventType` gained `.keyDown` case. CursorOverlayEngine merges clicks + key interactions into unified `InteractionPoint` list for zoom clustering, so typing activity triggers zoom focus just like clicks.

### Export Quality Fix

**Problem**: H.264 at 15 Mbps was too low for screen recordings with sharp text. Text edges appeared grainy/mushy.

**Fix** (CompositionEngine.swift):
- Switched `AVVideoCodecType.h264` → `.hevc` (hardware-accelerated on Apple Silicon, much better for screen content)
- Bitrate scales with resolution: `min(80_000_000, max(20_000_000, pixelCount * 15))`
  - 720p: 20 Mbps, 1080p: ~31 Mbps, 1440p: ~55 Mbps, 4K: 80 Mbps
- Added `AVVideoMaxKeyFrameIntervalKey: 30` for better keyframe distribution
- Removed H.264-specific `AVVideoProfileLevelH264HighAutoLevel`

### ZoomRegion — First-Class Editable Object

`ZoomRegion` (Codable, Identifiable, Sendable, Equatable) replaces ephemeral auto-generated keyframes:
```swift
struct ZoomRegion {
    var id: UUID
    var startTime: Double      // source time: zoom-in begins
    var endTime: Double        // source time: zoom-out completes
    var zoomLevel: CGFloat     // peak zoom (1.1–4.0x)
    var focusX: Double         // focus in source video coords
    var focusY: Double
    var isEnabled: Bool
}
```

**Architecture flow**:
1. `generateAutoZoomRegions()` clusters clicks + keyboard interactions → `[ZoomRegion]`
2. Regions stored in `Project.zoomRegions` (persisted in SavedState as `[SavedZoomRegion]`)
3. `rebuildCursorOverlay()` passes regions to `CursorOverlayEngine.prepare(zoomRegions:)`
4. Engine converts regions → keyframes via `zoomKeyframes(from:sensitivity:)` for render pipeline
5. Each region independently editable (zoom level, focus point, enable/disable, delete)
6. `extractInteractions(from:)` extracts both clicks and key events from metadata

### Zoom Track on Timeline

**TimelineView.swift** — new `zoomTrack(width:)` view pinned to bottom of ScrollView, 36pt height, conditional on `hasCursorData && !zoomRegions.isEmpty`.

**Visual**: Each region is a `TrapezoidShape` (custom Shape — ramp up, flat peak, ramp down):
- Peak height proportional to zoom level (normalized: `(zoomLevel - 1.0) / 3.0`)
- Ramp fractions derived from sensitivity's `zoomInDuration`/`zoomOutDuration`
- Fill: coral accent, `0.25` opacity normal / `0.45` selected
- Stroke: accent, dashed when disabled
- Mono zoom label at center (e.g., "2.0x") when region width > 30pt
- Playhead and hover indicator extend through both tracks (full `geo.size.height`)

**Interaction**: `DragGesture` splits behavior by Y position:
- Top part (segments): `handleTimelineInteraction` — selects segment, deselects zoom region
- Bottom part (zoom track): three modes based on click position:
  - Near left edge (12px hit zone) → **resize start** (drag to change zoom-in time)
  - Near right edge (12px hit zone) → **resize end** (drag to change zoom-out time)
  - Inside region → **move** (drag to reposition, preserves duration)
  - Empty area → deselect and seek
- `activeZoomDrag` state tracks ongoing drag mode (`.resizeStart`/`.resizeEnd`/`.move`)
- Drag continues regardless of Y position once started (no mode-switch mid-drag)
- Minimum region duration: 0.3s, clamped to video bounds
- Clicking a region seeks to its **peak (midpoint)** so preview shows the full zoom effect
- Resize cursor (`NSCursor.resizeLeftRight`) shown on edge hover
- Visual grab handles (3px coral accent bars with glow) on selected region edges
- Minimum trapezoid height: 12px (always visible/clickable even at low zoom)

### Restructured ControlsPanel (Airbnb + Liquid Glass)

Complete rewrite into **two-tier architecture**:

**`glassCard {}` wrapper**: `.ultraThinMaterial` background, `SB.Radius.md` continuous corners, gradient border (white 0.08 top → 0.02 bottom, 0.5pt stroke), clipped.

**Inspector section** (top, contextual): Shows when a zoom region is selected. Uses `.thinMaterial` (more opaque) with coral accent left border (3pt). Contains:
- "Zoom Region" section label
- Start time slider (0 to video duration, step 0.1s)
- End time slider (0 to video duration, step 0.1s)
- Zoom Level slider (1.1x–4.0x, step 0.1)
- `ZoomFocusPicker` — interactive mini-preview of video with:
  - Draggable crosshair (coral dot + crosshair lines)
  - Dashed rectangle showing visible crop area at current zoom level
  - Semi-transparent fill showing zoom coverage
  - Drag gesture → `setZoomRegionFocus(x:y:for:)` with bounds clamping
- Enable/disable toggle
- Delete button (destructive style — red label, red-tinted capsule bg)

**Global sections** (always present):
1. **Appearance** card: Background (color pickers + glass tabs), Layout (padding/corner radius), Shadow (radius/opacity)
2. **Cursor** card (conditional on `hasCursorData`): Cursor toggle + style tabs + size slider, Click Effect toggle + ring size
3. **Zoom** card (conditional on `hasCursorData`): Auto Zoom toggle + sensitivity tabs + Default Zoom slider (1.5x–4.0x) + Regenerate button
4. **Output** card: Resolution picker
5. **Export** card: Export button / progress

**Slider helper**: `sliderRow` with label/value display. Separate `sliderValueText()` handles both float (`"%.1fx"`) and integer (`"%d%%"`) formatting with optional multiplier.

### Project.swift Zoom Region Methods

```swift
func generateAutoZoomRegions()         // clusters interactions → [ZoomRegion], stores, rebuilds
func deleteZoomRegion(_ id: UUID)       // removes, clears selection, rebuilds
func toggleZoomRegion(_ id: UUID)       // flips isEnabled, rebuilds
func setZoomRegionLevel(_ level, for:)  // clamps 1.1–4.0, rebuilds
func setZoomRegionFocus(x:y:for:)       // clamps focus so crop stays in bounds, rebuilds
func seekToZoomRegion(_ id: UUID)       // seeks preview to region's start time
```

### SavedState Extensions

```swift
var zoomRegions: [SavedZoomRegion]?     // persisted zoom regions

struct SavedZoomRegion: Codable {
    var id: String, startTime: Double, endTime: Double
    var zoomLevel: Double, focusX: Double, focusY: Double
    var isEnabled: Bool
}
```

All backward compatible — old JSON decodes fine (optional fields).

### ContentView Height Adjustment

Timeline height: `project.hasCursorData ? 240 : 200` — extra 40pt accommodates the zoom track.

### Bugs Fixed (continued)
26. **Grainy export** → H.264 15Mbps insufficient → HEVC with resolution-scaled bitrate (20–80 Mbps)

---

## Part 13.5: Session 8 — Quality Fix, Zoom Interactions, Auto Undo/Redo

### Rendering Quality Fix (THE BIG ONE)

**Problem**: Preview AND export looked like 360p despite being 1080p — extremely grainy.

**Root cause** (FrameRenderer.swift): `CIContext` was missing `.highQualityDownsample: true`. Without it, Core Image uses draft-quality nearest-neighbor sampling. Also, scaling used `CGAffineTransform` which is bilinear (blurry for screen content).

**Fix**:
- CIContext: Added `.highQualityDownsample: true` and `.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!`
- Scaling: Replaced `CGAffineTransform(scaleX:y:)` with `CIFilter.lanczosScaleTransform()` — dramatically sharper for screen content (text, UI elements)

### Zoom Region Drag Resize & Move

**TimelineView.swift** — `ZoomDrag` state machine for interactive zoom region manipulation:
- `ZoomDrag` struct with modes: `.resizeStart`, `.resizeEnd`, `.move`
- `handleZoomDragStart`: Edge detection (12px zones) determines drag mode, selects region
- `handleZoomDragContinue`: Updates region times based on drag mode
- Minimum region duration: 0.3s, clamped to video bounds
- Visual grab handles (3px coral accent bars with glow) on selected region edges
- `NSCursor.resizeLeftRight` shown on edge hover via `onContinuousHover`
- `isNearZoomRegionEdge()` helper for cursor change detection

### Start/End Time Sliders in Inspector

**ControlsPanel.swift** — Added Start and End time sliders to zoom region inspector:
- Range: 0 to video duration, step 0.1s
- Calls `project.setZoomRegionTimes(start:end:for:)` with 0.3s minimum enforcement

### Preview Live Update

**Project.swift** — `updateVisuals()` now force re-seeks when paused:
```swift
if dur > 0 && !isPlaying {
    seek(toFraction: playheadTime / dur)
}
```
AVPlayer doesn't re-render the current frame when `videoComposition` changes while paused. Force re-seek makes zoom level/focus changes visible instantly in preview.

`setZoomRegionLevel` and `setZoomRegionFocus` now call `seekToZoomRegionPeak()` before `updateVisuals()` — preview jumps to the region's peak so user sees the full zoom effect.

### Default Zoom Level

Changed `CursorSettings.autoZoomLevel` default from 1.3 to 2.0. Old default produced 3px-tall invisible trapezoids on the timeline. Added "Default Zoom" slider (1.5x–4.0x) back to Auto Zoom section in ControlsPanel.

### Keyboard Monitoring — Accessibility Permission

**CursorTracker.swift** — Global `.keyDown` monitoring requires macOS Accessibility permission. Without it, the monitor handler silently never fires (mouse events work without permission — keyboard events are restricted as anti-keylogging protection).

**Fix**:
- Added `import ApplicationServices`
- `startTracking()` checks `AXIsProcessTrusted()` before setting up key monitor
- If not trusted, calls `AXIsProcessTrustedWithOptions` to prompt user (opens System Settings > Privacy & Security > Accessibility)
- Added `isKeyboardMonitoringAvailable` property for UI feedback
- **User must re-record** after granting permission — old recordings don't have keyDown data

### Hoverable "+" to Add Zoom Regions Manually

**TimelineView.swift** — Zoom track now always visible when cursor data exists (not only when regions exist). Hover over empty areas shows a ghost dashed rectangle with "+" icon (2-second region preview). Clicking adds a new zoom region at that position.

- `@State var zoomTrackHoverTime: Double?` tracks hover position in empty zoom track areas
- `project.addZoomRegion(at:)` creates a region with default zoom level, centered focus, auto-selects it
- Ghost "+" uses dashed stroke + accent fill at 12% opacity, animates in/out

### Context Menu on Timeline

Right-click context menu on the timeline ZStack:
- If zoom region selected: Enable/Disable, Zoom Level submenu (1.5x–4.0x), Duplicate, Delete
- Always (when cursor data exists): "Add Zoom Region Here" at playhead position

### Zoom Region Height — Half-Height Baseline

**Old**: `(zoomLevel - 1.0) / 3.0` → 1.0x = 0% height (clamped to 12px). 1.3x was barely visible.

**New**: `0.5 + 0.5 * normalizedZoom` → 1.0x = 50% track height (~15pt), 4.0x = 100%. All zoom levels clearly visible and selectable.

### New Project Methods

```swift
func addZoomRegion(at time: Double)    // manual placement, 2s default duration, centered focus
func duplicateZoomRegion(_ id: UUID)   // copies region right after original
```

### Automatic Undo/Redo System

**Replaced manual `pushUndo()` pattern with fully automatic undo capture.**

**Old system**: `UndoSnapshot` only captured `splitPoints` and `segments`. Required manual `pushUndo()` before each mutation. Zoom regions, visual settings, cursor settings — none had undo.

**New system**: `EditingSnapshot` captures ALL editing state:
- Timeline: splitPoints, segments (start, end, speed, enabled)
- Appearance: padding, cornerRadius, shadowRadius, shadowOpacity, gradient colors, output size, showThumbnails
- Cursor & Zoom: full `CursorSettings`, all `[ZoomRegion]`
- Position: playheadTime

**How it works**:
1. `saveState()` is called after every mutation (for persistence). It now auto-captures undo entries.
2. On first change in a batch, captures `preChangeSnapshot` from `lastCommittedSnapshot`
3. After 500ms of no changes (debounce), commits the pre-change state to `undoStack`
4. Rapid slider drags → ONE undo entry (the state before the drag started)
5. `isRestoringFromUndo` flag prevents circular capture during Cmd+Z restore

**Contract**: ANY mutation that calls `saveState()` (directly or via `updateVisuals()`) gets automatic undo/redo. No manual calls needed — ever. This covers all current AND future mutations.

**To add undo for new properties**: Add to `EditingSnapshot`, `captureSnapshot()`, and `restoreFromSnapshot()`. That's it.

### Bugs Fixed (continued)
27. **Preview not updating when adjusting zoom** → force re-seek in `updateVisuals()` when paused
28. **360p quality in preview AND export** → `CIContext .highQualityDownsample: true` + Lanczos scaling
29. **Auto-zoom regions invisible at 1.3x** → default zoom 2.0x + half-height baseline + min 12px
30. **Keyboard monitoring silently failing** → requires Accessibility permission, added AX check + prompt
31. **Undo only covered splits/segments** → automatic `EditingSnapshot` captures ALL editing state

---

## Part 14: Session 9 — Floating Recorder Toolbar, Region Selection, NSPanel Architecture

### Old Recorder Removed

The old `RecorderWindow.swift` was a full-size SwiftUI `Window` dialog (400pt wide). Problems:
- Not sticky — disappeared when switching apps/desktops
- Got recorded in screen captures (no `sharingType = .none`)
- Showed "Record Again" / "Open in Editor" after completion instead of auto-opening
- No area/region selection — only Display and Window modes
- Too large for a recorder control

**Deleted**: `RecorderWindow.swift`
**Removed**: `Window("Screen Recorder", id: "recorder")` scene from `ScreenboomApp.swift`

### New: `RecorderPanel.swift` — NSPanel + Lifecycle Manager

**`RecorderFloatingPanel`** (NSPanel subclass):
- `isReleasedWhenClosed = false` — CRITICAL for Swift/ARC (prevents double-free EXC_BAD_ACCESS)
- `level = .floating` — always on top
- `sharingType = .none` — invisible to ScreenCaptureKit
- `styleMask = [.nonactivatingPanel, .borderless, .fullSizeContentView]` — no title bar, doesn't steal focus
- `hidesOnDeactivate = false` — stays visible when switching apps
- `isMovableByWindowBackground = true` — draggable anywhere
- `canBecomeKey = true`, `canBecomeMain = false` — accepts clicks, doesn't steal main
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`

**`RecorderPanelManager`** (`@Observable`):
- `show(recorder:onComplete:)` — creates panel with NSHostingView wrapping RecorderBarView
- `dismiss()` — invalidates resize timer, closes panel
- Auto-resize timer (0.05s) keeps panel width synced to SwiftUI content size changes
- Positioned center-top of main screen, 60pt from top
- Injected via `.environment(recorderPanelManager)` from ScreenboomApp

### New: `RecorderBarView.swift` — Compact Horizontal Glass Bar

Replaces RecorderWindow. Horizontal floating bar hosted inside the NSPanel.

**Layout**: `closeButton | divider | SBGlassTabs (Display/Window/Region) | divider | contextArea | divider | startButton`

**States**:
- **Permission**: spinner + "Requesting permission..."
- **Config**: close (SBIconButton) + mode tabs (SBGlassTabs, 220pt) + source picker/region controls + start button
- **Recording**: pulsing dot + timer (18pt mono light) + stop button
- **Processing**: spinner + text
- **Failed**: warning icon + message + retry + close
- **Completed**: NO UI — immediately fires `onComplete(session)` + dismisses panel

**Design system usage**:
- `SBGlassTabs` for Display/Window/Region mode selector
- `SBIconButton` for close X
- `SBChip` for region dimensions
- `SBPulsingDot` for recording indicator
- Thin dividers (1px white 0.08 opacity) separate logical groups
- `SB.Radius.xl` bar corners, `.ultraThinMaterial` + gradient border
- `SB.Space.xl` horizontal / `SB.Space.lg` vertical padding

**Source picker**: Menu with display icon or window icon, chevron, glass background. Shows display resolution or window "App — Title" label.

**Region controls**: dimension chip + "Select Area" / "Reselect" button with accent tint. Start button disabled until region selected.

### New: `RegionSelectionOverlay.swift` — Full-Screen Region Selector

**`RegionSelectorManager`** (`@Observable`):
- `startSelection(onSelected:)` — creates overlay on ALL screens (not just primary)
- `teardownWindows()` — invalidates views, closes windows safely
- Persists last region size to UserDefaults (`RegionSelection.lastWidth/Height`)
- Default: 1280×720, reopens at last-used size
- Converts view coords (top-left origin) to Quartz screen coords (bottom-left) for ScreenCaptureKit

**`RegionSelectionWindow`** (NSWindow subclass):
- `isReleasedWhenClosed = false` — prevents double-free with ARC
- `level = .floating + 1` (above recorder panel)
- `sharingType = .none`, borderless, `canBecomeKey = true`, `canBecomeMain = false`

**`RegionSelectionView`** (NSView, `isFlipped = true`):
- Opens with pre-positioned resizable rectangle (centered, last-used size)
- 8 drag handles: 4 corners (coral accent squares) + 4 edges (white squares)
- Drag inside to move, drag handles to resize, click outside to reposition
- Rule-of-thirds grid lines inside selection
- Dimension label below ("1280 × 720"), hint bar at top
- Enter to confirm, Escape to cancel
- Min size 100×100, clamped to screen bounds
- Cursor changes: resize on edges, open-hand inside, crosshair outside
- `isInvalidated` flag — all event handlers (`mouseDown`, `mouseMoved`, `keyDown`, `draw`) guarded

**Critical crash fix** (EXC_BAD_ACCESS):
- `keyDown` NEVER calls callbacks synchronously — marks `isInvalidated = true`, nils closures, defers callback via `DispatchQueue.main.async`
- This ensures `keyDown` fully returns before any window teardown happens
- `isReleasedWhenClosed = false` on both NSPanel subclasses prevents ARC double-free

### Modified: `ScreenRecorder.swift`

- `CaptureMode` gained `.region` case (now: Display, Window, Region)
- Added `var selectedRegion: CGRect?` property
- `startRecording()` region mode: uses display filter + `config.sourceRect` set to selected region, `config.width/height` to region dimensions
- Cursor tracker: `captureOrigin` set to `selectedRegion.origin` in region mode
- `displayName` for recordings: "Region WxH" format

### Modified: `ScreenboomApp.swift`

- Removed `Window("Screen Recorder", id: "recorder")` scene
- Added `@State private var recorderPanelManager = RecorderPanelManager()`
- Injected via `.environment(recorderPanelManager)` on ContentView

### Modified: `WelcomeView.swift`

- Removed `@Environment(\.openWindow) private var openWindow`
- Added `@Environment(RecorderPanelManager.self) private var recorderPanelManager`
- `showRecorder()` helper: creates ScreenRecorder, calls `recorderPanelManager.show(recorder:onComplete:)`
- On completion: `project.createProject(session:store:)` + `NSApp.activate(ignoringOtherApps: true)` to bring main window front

### AppKit/Swift Gotchas Learned

32. **NSPanel `isReleasedWhenClosed` double-free**: NSPanel defaults `isReleasedWhenClosed = true`. `close()` sends ObjC `release`. ARC also releases when Swift reference goes out of scope → double-free → EXC_BAD_ACCESS code=1. **Fix**: `isReleasedWhenClosed = false` on ALL NSWindow/NSPanel subclasses in Swift.
33. **Event handler teardown crash**: Calling `window.close()` / `window.orderOut()` / `window.contentView = nil` from within the window's own event handler (`keyDown`, `mouseUp`) deallocates the view while it's still on the call stack → EXC_BAD_ACCESS. **Fix**: Set `isInvalidated = true` immediately, nil closures, defer callback via `DispatchQueue.main.async`. Teardown runs on next run loop after event handler has fully returned.
34. **Region overlay must cover all screens**: `NSScreen.main` is the primary display, not the display the user is working on. User may be on screen 3. Overlay must iterate `NSScreen.screens` to cover all displays.

---

## Part 15: Session 10 — View/ViewModel Separation, Countdown, Implicit Region, Coordinate Fixes

### New: `RecorderFlowController.swift` — State Machine + Orchestrator

**View/ViewModel separation** following MVVM pattern. The flow controller is the central coordinator:

```
RecorderBarView (pure view) → RecorderFlowController (state machine) → ScreenRecorder (service)
```

**`RecorderFlowController`** (`@Observable`):
- **States**: `idle → requestingPermission → configuring → [selectingRegion] → countdown(3,2,1) → preparing → recording → stopping → completed(RecordingSession) → failed(String)`
- Owns `ScreenRecorder` (private — view never touches it)
- Owns `RegionSelectorManager` (region selection lifecycle)
- Owns `CountdownPanelManager` (countdown overlay lifecycle)
- `captureMode` didSet: auto-triggers region selection when switching to `.region` with no selection, auto-cancels when switching away
- `canStart` computed: configuring AND (not region OR region selected)
- `initiateRecording()` → starts 3-second countdown
- `stopRecording()` async → stops recording, transitions to completed/failed
- `teardown()` with `isTearingDown` flag — prevents callbacks during disposal
- `targetScreen()` — determines countdown screen by matching `CGDirectDisplayID` for region mode

### New: `CountdownPanel.swift` — Floating 3-2-1 Overlay

**`CountdownFloatingPanel`** (NSPanel subclass):
- `isReleasedWhenClosed = false`, `sharingType = .none`, `ignoresMouseEvents = true` (click-through)
- `canBecomeKey = false`, `canBecomeMain = false`
- Users can interact with other apps during countdown

**`CountdownPanelManager`**: `show(on: NSScreen)`, `updateCount(_ count: Int)`, `dismiss()`

**`CountdownOverlayView`**: 80pt ultraLight rounded number, dark circle backdrop (55% black, 25px blur), `.contentTransition(.numericText())` animation

**Countdown flow**: `initiateRecording()` → `startCountdown(from: 3)` → Timer fires at 1s intervals → `3, 2, 1` → `beginActualRecording()`. Cancellable via `cancelCountdown()`.

### Modified: `RecorderBarView.swift` — Pure View

Now reads from `RecorderFlowController` instead of managing `ScreenRecorder` directly:
- `@State var flow: RecorderFlowController` (was `recorder: ScreenRecorder`)
- Region area: clickable dimension chip (re-triggers selection), spinner during selection
- Countdown state: large accent number + "Recording starts in N..." + cancel button
- No business logic — flow controller handles all state transitions

### Modified: `RecorderPanel.swift` — Creates Flow Controller

`RecorderPanelManager.show()` no longer takes a `ScreenRecorder`:
- Creates `RecorderFlowController` internally
- `dismiss()` calls `flowController?.teardown()` before closing panel

### Modified: `RegionSelectionOverlay.swift` — Edge-Band Handles + Cancel Callbacks

**Edge-band detection** replaces point-based hit zones:
```swift
// Entire edge (16px band) is a resize zone — not just a 32px midpoint
let nearLeft   = abs(point.x - r.minX) < edgeBand
let nearRight  = abs(point.x - r.maxX) < edgeBand
let nearTop    = abs(point.y - r.minY) < edgeBand
let nearBottom = abs(point.y - r.maxY) < edgeBand
// Corner priority → edge → nil (deep inside = body move)
```

**Cancel callbacks**: `startSelection(onSelected:onCancelled:)` — added optional `onCancelled` parameter. `cancelSelection()` fires callback, `forceClose()` tears down silently.

**Implicit region**: Flow controller auto-triggers `beginRegionSelection()` on mode switch to `.region` if no region selected. No "Select Area" button needed.

**Y-FLIP BUG FIX**: `handleSelection()` was converting view coords (top-left) to Quartz (bottom-left) before passing to SCK, but `SCStreamConfiguration.sourceRect` uses **display-relative top-left** coords (same as the view). The Y-flip caused the recording to capture 10-20% higher than selected.

**Fix**: Pass viewRect directly — no Y-flip. The view is `isFlipped = true` so its coordinates already match SCK's expected format.

### Modified: `ScreenRecorder.swift` — Region Cursor Tracking + Debug Logging

- Added `import os` and `Logger` (`recLog`)
- Cursor tracker now receives `displayHeight` and `backingScaleFactor` before starting
- Region mode cursor `captureOrigin`: matches NSScreen by `CGDirectDisplayID`, converts from display-relative top-left to global Cocoa bottom-left:
  ```swift
  tracker.captureOrigin = CGPoint(
      x: sf.origin.x + region.origin.x,
      y: sf.origin.y + (sf.height - region.origin.y - region.height)
  )
  ```
- Extensive `[CURSOR DEBUG]` and `[REGION DEBUG]` logging for coordinate diagnostics

### Modified: `CursorOverlayEngine.swift` — Coordinate Fix + Retina Hotspot

**Cocoa→video coordinate conversion fix**:
- Old: `videoY = sourceSize.height - (event.y - captureOrigin.y)` — wrong when display origin ≠ 0
- New: `videoY = displayHeight - event.y - captureOrigin.y` — correct for all screen configurations
- `displayHeight` read from `CursorMetadataFile` (with fallback for old recordings)

**Retina cursor hotspot fix**:
- `NSCursor.hotSpot` is in POINT coordinates, but `cursor.image` CGImage is at Retina pixel resolution
- Old: `scaledHotspot = CGPoint(x: hotspot.x * size, y: hotspot.y * size)` — 2x offset on Retina
- New: `scaledHotspot = CGPoint(x: hotspot.x * size * backingScale, y: hotspot.y * size * backingScale)`

### Modified: `CursorTracker.swift` + `RecordingModels.swift`

- `CursorTracker`: Added `displayHeight: CGFloat` and `backingScaleFactor: CGFloat` properties, written to metadata JSON
- `CursorMetadataFile`: Added optional `displayHeight: Double?` and `backingScaleFactor: Double?` fields (backward compatible)

### Modified: `WelcomeView.swift`

- `showRecorder()` simplified — no longer creates ScreenRecorder externally:
  ```swift
  recorderPanelManager.show { session in
      project.createProject(session: session, store: store)
      NSApp.activate(ignoringOtherApps: true)
  }
  ```

### Bugs Fixed (continued)
35. **Cursor position mismatch** → `videoY = sourceH - (cocoaY - quartzOriginY)` mixed coordinate systems → fixed to `displayH - cocoaY - quartzOriginY`, store displayHeight in CursorMetadataFile
36. **Cursor hotspot Retina mismatch** → NSCursor.hotSpot is in points but CGImage is at 2x Retina pixels → scale hotspot by backingScaleFactor
37. **Region capture Y-offset** → handleSelection flipped Y to Quartz (bottom-left) but SCK sourceRect uses top-left → pass viewRect directly (display-relative top-left). Compute Cocoa coords separately for cursor tracking.
38. **Edge handle only at midpoint** → old point-based hit zones (32px at edge center) → edge-band detection (entire edge, 16px band)

---

### Current File Structure

```
Screenboom/
├── ScreenboomApp.swift            — @main, Project + ProjectStore + RecorderPanelManager + ExportPanelManager
├── ContentView.swift              — WelcomeView ↔ Editor toggle, toolbar with Export button
├── WelcomeView.swift              — Empty state / project grid, showRecorder()
├── Project.swift                  — @Observable model: ALL state, multi-project, playback, segments, persistence, export
├── ProjectInfo.swift              — Project metadata struct
├── ProjectStore.swift             — Multi-project catalog manager
├── DesignSystem.swift             — Design tokens, reusable components (SBIconTabBar, SBGlassCard, SBSliderRow, SBComingSoonPlaceholder)
├── EditorSettingsController.swift — ViewModel: EditorTab enum, read-through props, binding factories, action methods
├── ControlsPanel.swift            — Thin shell: SBIconTabBar + content router (~100 lines), ZoomFocusPicker
├── AppearanceTabView.swift        — Background + Layout + Shadow tab
├── CursorTabView.swift            — Cursor style/size + Click effects tab
├── ZoomTabView.swift              — Auto-zoom settings tab
├── ContextualInspectorView.swift  — Zoom region inspector + Segment inspector (contextual, slides in)
├── ExportPanel.swift              — ExportFloatingPanel (NSPanel) + ExportPanelManager + ExportPopupView
├── VideoPreviewView.swift         — NSViewRepresentable wrapping AVPlayerView
├── TimelineView.swift             — Timeline: thumbnails, segments, hover, playhead, zoom track
├── FrameRenderer.swift            — CIFilter pipeline: scale+crop, rounded corners, shadow, gradient
├── CompositionEngine.swift        — AVMutableComposition + export + speed ramp expansion
├── ScreenRecorder.swift           — ScreenCaptureKit recorder (Display/Window/Region) + StreamOutput + StreamDelegate
├── RecorderFlowController.swift   — Recording state machine (permission → config → countdown → record)
├── RecorderPanel.swift            — RecorderFloatingPanel (NSPanel) + RecorderPanelManager
├── RecorderBarView.swift          — Compact horizontal glass recorder bar (pure view)
├── CountdownPanel.swift           — Floating 3-2-1 countdown overlay (click-through, invisible to recording)
├── RegionSelectionOverlay.swift   — Full-screen region selector (all screens, edge-band resize, persisted size)
├── RecordingModels.swift          — CursorEvent, CursorMetadataFile, RecordingSession
├── CursorTracker.swift            — NSEvent global monitors for cursor + keyboard metadata
├── CursorOverlayEngine.swift      — Cursor processing: smoothing, rendering, click effects, ZoomRegion, auto-zoom
└── Assets.xcassets/
```

---

## Part 16: Session 11 — Controls Panel Refactor, Tabbed Editor, Export Popup, Preview Always 4K

### ControlsPanel Refactor — ViewModel + Tabs

**Problem**: ControlsPanel was a 620-line monolith binding directly to Project. All business logic inline, untestable. Single scrolling list of glass cards — no hierarchy.

**Solution**: Extracted into ViewModel + tabbed editor panel with contextual inspector.

### New: `EditorSettingsController.swift` — ViewModel

`@Observable` class wrapping Project mutations:
- `EditorTab` enum: `.appearance`, `.cursor`, `.zoom`, `.audio`, `.annotations`, `.subtitles`
- `selectedTab` state, `availableTabs` (hides cursor/zoom without cursor data)
- Read-through computed properties: `hasCursorData`, `selectedZoomRegion`, `selectedSegment`, `hasInspectorContent`
- Static `backgroundPresets` + `currentPreset` detection
- Action methods: `applyPreset()`, `setCursorEnabled()`, `setCursorStyle()`, `setCursorSize()`, `setClickEffectEnabled()`, `setClickEffectRadius()`, `setAutoZoomEnabled()`, `setAutoZoomSensitivity()`, `regenerateZoomRegions()`, `dismissInspector()`, `toggleSegment()`, `setSegmentSpeed()`, `setOutputResolution()`
- Binding factories: `gradientColor1Binding()`, `gradientColor2Binding()`, `paddingBinding()`, `cornerRadiusBinding()`, `shadowRadiusBinding()`, `shadowOpacityBinding()`, `autoZoomLevelBinding()`
- Key: ViewModel does NOT duplicate state. Reads through to Project, wraps mutations with correct side-effect chains.

### New: Tab Views

**`AppearanceTabView.swift`**: Three `SBGlassCard` sections — Background (color pickers + preset glass tabs), Layout (padding/corner radius sliders), Shadow (radius/opacity sliders).

**`CursorTabView.swift`**: Two `SBGlassCard` sections — Cursor (toggle, style tabs, size slider), Click Effect (toggle, ring size slider).

**`ZoomTabView.swift`**: One `SBGlassCard` — Auto Zoom toggle, sensitivity tabs, default zoom slider, regenerate button.

### New: `ContextualInspectorView.swift`

Slides in above tab content with `.transition(.move(edge: .top).combined(with: .opacity))`:
- **Zoom region selected** → start/end sliders, zoom level, focus picker, enable toggle, delete button
- **Segment selected** → speed tabs (0.5x/1x/2x/4x) + custom slider, enable toggle, duration label
- **Nothing selected** → hidden
- Styling: `.thinMaterial`, 3pt coral accent left border, dismiss X button

### New: `ExportPanel.swift`

Follows RecorderPanel NSPanel pattern:
- `ExportFloatingPanel` (NSPanel): `isReleasedWhenClosed = false`, borderless, floating
- `ExportPanelManager` (@Observable): `show(project:)` / `dismiss()`, centered in main window
- `ExportPopupView`: Resolution glass tabs, H.264 MP4 format label, export button + progress bar
- `.ultraThickMaterial` background, `SB.Radius.lg` corners, shadow

### Modified: `ControlsPanel.swift`

Gutted from 620 → ~100 lines. Now:
- `SBIconTabBar` (36pt vertical strip, left edge)
- Content router switching on `controller.selectedTab`
- `ContextualInspectorView` above tab content
- Coming Soon placeholder for Audio/Annotations/Subtitles tabs
- `ZoomFocusPicker` remains here

### Modified: `ContentView.swift`

- Creates `EditorSettingsController` when entering editor (via `onChange(of: showEditor)`)
- Toolbar: Back button (left) + Export button (right, `SBPrimaryButton`)
- Export progress shown inline in toolbar when exporting
- Panel width: 316pt (36 tab bar + 280 content)
- `@Environment(ExportPanelManager.self)` for export popup

### Modified: `ScreenboomApp.swift`

- Added `@State private var exportPanelManager = ExportPanelManager()`
- Injected via `.environment(exportPanelManager)` on ContentView

### Modified: `DesignSystem.swift`

New components:
- `SBIconTabBar<Tab>` — generic vertical icon strip with accent indicator bar, hover tooltips, disabled state (30% opacity)
- `SBComingSoonPlaceholder` — centered icon (48pt, 20% opacity) + title + description + "Coming Soon" chip
- `SBGlassCard` — reusable glass card wrapper (`.ultraThinMaterial` + gradient border)
- `SBSliderRow` — label/value/slider helper with format string support

### Preview Always 4K

**Problem**: Changing export resolution also changed preview quality.

**Fix**: Split `renderSettings` into two:
- `previewSettings` — hardcoded 3840×2160, used by `rebuildPlayer()` and `updateVisuals()`
- `exportSettings` — user-selected resolution, used only by `runExport()`
- Changing export resolution no longer triggers preview rebuild — just persists the setting via `saveState()`

### Tests

`EditorSettingsControllerTests.swift` — 14 tests using Swift Testing:
- Tab availability (cursor hidden without data, coming soon flags)
- Preset application and detection
- Segment toggle and speed clamping (0.25–32.0)
- Zoom region deletion clears selection
- Inspector content detection (zoom region, segment, empty)
- Dismiss inspector clears both selections
- Cursor style and click effect updates
- Output resolution updates

All 40 tests pass (14 new + 26 existing).

### Bugs Fixed (continued)
39. **Export broken by ControlsPanel refactor** → No — clean extraction, all bindings tested
40. **Preview quality changed with export resolution** → split into `previewSettings` (4K) and `exportSettings` (user-selected)

---

## Part 17: Current Status

### Confirmed Working:
- All editor features (split, disable, speed, background, padding, corners, shadow, export) ✓
- Multi-project support (create, open, close, delete, rename, migrate) ✓
- Design system V2 (Airbnb + glass) with SBIconTabBar, SBGlassCard, SBSliderRow ✓
- GitHub Actions DMG release workflow (v0.2.0 released) ✓
- Cursor intelligence engine (smoothing, rendering, click effects, auto-zoom) ✓
- Zoom track on timeline (trapezoid shapes, click/drag/resize/move, context menu) ✓
- Tabbed editor panel (Appearance/Cursor/Zoom + Coming Soon tabs) ✓
- EditorSettingsController ViewModel (testable, read-through to Project) ✓
- Contextual inspector (zoom region + segment, slides in/out) ✓
- Export popup (NSPanel, centered, resolution picker, H.264 label) ✓
- Export button in toolbar (replaces sidebar export section) ✓
- Preview always renders at 4K regardless of export resolution ✓
- Keyboard input tracking for auto-zoom (requires Accessibility permission) ✓
- H.264 export with resolution-scaled bitrate (20-80 Mbps) ✓
- High-quality rendering (Lanczos + highQualityDownsample) ✓
- Manual zoom region placement (hover "+" on timeline) ✓
- Automatic undo/redo for ALL editing state (Cmd+Z / Cmd+Shift+Z) ✓
- Zoom region persistence (SavedZoomRegion) ✓
- Floating recorder toolbar (NSPanel, always-on-top, invisible to recording) ✓
- Region capture mode (resizable selection, persisted size, all screens) ✓
- View/ViewModel separation (RecorderFlowController + EditorSettingsController) ✓
- 3-second countdown before recording (all modes, floating overlay) ✓
- 14 ViewModel unit tests + 26 existing tests = 40 total ✓
- Build succeeds ✓

### Gap to Screen Studio Parity

**Tier 1 — Must-Have:**
1. Webcam overlay (PiP bubble) — AVCaptureSession + composited in FrameRenderer
2. System audio + microphone — ScreenCaptureKit audio stream + AVAudioEngine
3. Background variety — wallpapers, images, solid colors, mesh gradients (not just 2-color gradient)
4. Window-following crop (smart framing) — track active window bounds over time
5. Cursor interpolation across segment cuts — bridge cursor position at disabled segment boundaries

**Tier 2 — Expected:**
6. Keyboard shortcut overlay — floating key pills composited in FrameRenderer
7. Click highlight (spotlight/dim effect) — dim everything except click area
8. Export presets — Twitter/YouTube/Slack/GIF one-click profiles
9. Scroll inertia smoothing — momentum smoothing on scroll events
10. Animated intro/outro — fade-in/out from background

**Tier 3 — Polish:**
11. Multi-segment backgrounds — different background per segment
12. Aspect ratio presets — 16:9, 9:16, 1:1, 4:3
13. GIF export — frame sampling + palette quantization
14. Cursor motion trail — subtle trail during fast moves
15. Annotations — text, arrows, highlights (placeholder tab exists)
