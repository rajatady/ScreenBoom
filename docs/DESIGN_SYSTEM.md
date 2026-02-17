# Screenboom Design System

Screenboom uses a centralized design system (`SB.*`) that works like Tailwind for SwiftUI — every visual property (color, font, spacing, radius, shadow, animation) is a named token. Raw values are forbidden in view files and enforced by automated compliance tests.

## File Structure

```
Screenboom/DesignSystem/
  SBTokens.swift       — All token definitions (SB.Colors, SB.Typo, SB.Icons, etc.)
  SBComponents.swift   — Reusable view components (buttons, cards, tabs, chips)
  SBModifiers.swift    — View modifier extensions (.sbShadow, .sbPageBackground)
  SBFormatters.swift   — Duration formatting helpers
```

## Token Namespaces

### `SB.Colors` — Color Palette

Warm dark palette with coral accents. All UI colors come from here.

| Token | Value | Use |
|-------|-------|-----|
| `background` | `#171718` | App background |
| `surface` | `#212121` | Card/panel backgrounds |
| `surfaceRaised` | `#292929` | Elevated surfaces |
| `surfaceHover` | `#303030` | Hover state surfaces |
| `surfaceOverlay` | black 50% | Overlays, dimming layers |
| `border` | white 7% | Default borders |
| `borderHover` | white 13% | Hover borders |
| `borderSubtle` | white 4% | Very subtle borders |
| `textPrimary` | white 95% | Primary text, button labels on dark bg |
| `textSecondary` | white 62% | Secondary text, labels |
| `textTertiary` | white 40% | Tertiary text, disabled |
| `accent` | `#FF5A5E` | Coral accent — buttons, selection, brand |
| `accentSubtle` | accent 12% | Accent backgrounds |
| `accentHover` | `#FF474D` | Accent hover state |
| `success` | `#4DD98C` | Success indicators |
| `warning` | `#FFC747` | Warnings |
| `destructive` | `#FF4D4D` | Destructive actions |
| `accentNS` | NSColor bridge | For AppKit/CGContext drawing |
| `playhead` | = accent | Timeline playhead |

```swift
// Good
Text("Hello").foregroundStyle(SB.Colors.textPrimary)

// Bad
Text("Hello").foregroundStyle(.white)
Text("Hello").foregroundStyle(.secondary)
```

### `SB.Typo` — Typography

All fonts use `.rounded` design for warmth. Monospaced for data/numbers.

| Token | Size/Weight | Use |
|-------|-------------|-----|
| `heroTitle` | 32 bold rounded | Welcome screen title |
| `pageTitle` | 22 bold rounded | Page headers, panel titles |
| `sectionTitle` | 15 semibold rounded | Section headers |
| `subtitle` | 15 medium rounded | Subtitle descriptions |
| `body` | 13 regular rounded | Body text |
| `bodyMedium` | 13 medium rounded | Emphasized body text |
| `bodySmall` | 12 regular rounded | Smaller body text |
| `caption` | 11 regular rounded | Captions, labels |
| `captionMedium` | 11 medium rounded | Emphasized captions |
| `label` | 12 semibold rounded | Button labels |
| `mono` | 10 medium mono | Data chips, small values |
| `monoMd` | 12 medium mono | Region dimensions |
| `microMono` | 9 medium mono | Zoom region labels |
| `timer` | 48 ultraLight mono | Large timers |
| `timerSm` | 18 light mono | Recording duration |
| `countdown` | 80 ultraLight rounded | Countdown overlay |
| `counterLg` | 28 light rounded | Inline countdown |

```swift
// Good
Text("Duration").font(SB.Typo.caption)
Text("00:15.3").font(SB.Typo.mono)

// Bad
Text("Duration").font(.caption)
Text("00:15.3").font(.system(size: 10, weight: .medium, design: .monospaced))
```

### `SB.Icons` — Icon Font Sizing

Standardized icon sizes. Use instead of `.font(.system(size: N))` on `Image(systemName:)`.

| Token | Size/Weight | Use |
|-------|-------------|-----|
| `xs` | 10 medium | Dismiss buttons, micro icons |
| `sm` | 12 semibold | List row icons, chevrons |
| `md` | 14 medium | Tab bar icons, feature icons |
| `base` | 16 medium | Option swatches, standard icons |
| `lg` | 18 medium | Section header icons |
| `hero` | 48 ultraLight | Coming soon placeholders, empty states |

```swift
// Good
Image(systemName: "xmark").font(SB.Icons.xs)
Image(systemName: "waveform").font(SB.Icons.hero)

// Bad
Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
```

### `SB.Space` — Spacing Scale

Consistent spacing for padding, gaps, and margins.

| Token | Value | Use |
|-------|-------|-----|
| `xxs` | 2pt | Internal component padding |
| `xs` | 4pt | Tight spacing, icon gaps |
| `sm` | 8pt | Compact padding, small gaps |
| `md` | 12pt | Default padding, section gaps |
| `lg` | 16pt | Generous padding, card padding |
| `xl` | 24pt | Large sections |
| `xxl` | 32pt | Page margins |
| `xxxl` | 48pt | Hero spacing |

```swift
// Good
.padding(.horizontal, SB.Space.lg)
HStack(spacing: SB.Space.sm) { ... }

// Bad
.padding(.horizontal, 16)
HStack(spacing: 8) { ... }
```

### `SB.Radius` — Corner Radii

Rounder than typical macOS. Use consistently for shape rounding.

| Token | Value | Use |
|-------|-------|-----|
| `xxs` | 2pt | Accent bars, indicator handles |
| `xs` | 4pt | Timeline shapes, zoom picker |
| `sm` | 8pt | Tabs, small cards |
| `md` | 12pt | Glass cards, panels |
| `lg` | 16pt | Large cards, modals |
| `xl` | 24pt | Floating bars, large panels |
| `pill` | 100pt | Capsule shapes |

```swift
// Good
RoundedRectangle(cornerRadius: SB.Radius.md)

// Bad
RoundedRectangle(cornerRadius: 12)
```

### `SB.Shadows` — Shadow Presets

Use the `.sbShadow()` modifier instead of raw `.shadow(color:radius:y:)`.

| Token | Use |
|-------|-----|
| `subtle` | Icon buttons, small elements |
| `card` | Glass cards at rest |
| `cardHover` | Glass cards on hover |
| `float` | Floating bars (recorder, panels) |
| `popup` | Export panel, modals |
| `playhead` | Timeline playhead glow |
| `glow(color)` | Accent glows (crosshairs, handles) |
| `button(color)` | Button rest shadow |
| `buttonHover(color)` | Button hover shadow |

```swift
// Good
.sbShadow(SB.Shadows.card)
.sbShadow(SB.Shadows.glow(SB.Colors.accent))

// Bad
.shadow(color: .black.opacity(0.12), radius: 8, y: 3)
```

### `SB.Glass` — Glass Surface Fills

White opacity scale for glass/frosted surfaces. Use instead of `Color.white.opacity(N)`.

| Token | Opacity | Use |
|-------|---------|-----|
| `faint` | 3% | Inactive surfaces, rest backgrounds |
| `subtle` | 6% | Button backgrounds, dividers, chip fills |
| `base` | 8% | Borders, panel dividers |
| `medium` | 12% | Hover fills, accent subtle fills |
| `strong` | 16% | Hover borders, selected state borders |

```swift
// Good
.fill(SB.Glass.subtle)
.strokeBorder(SB.Glass.base, lineWidth: 0.5)

// Bad
.fill(Color.white.opacity(0.06))
.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
```

### `SB.Anim` — Animation Tokens

Named animations for consistent motion language.

| Token | Value | Use |
|-------|-------|-----|
| `springSnappy` | 0.3s, bounce 0.15 | Interactions, tab switches |
| `springGentle` | 0.4s, bounce 0.1 | Page transitions |
| `springBouncy` | 0.5s, bounce 0.25 | Playful elements |
| `fadeQuick` | 0.15s easeOut | Hover states |
| `fadeMedium` | 0.25s easeInOut | Content transitions |
| `pulse` | 0.8s repeat | Pulsing recording dot |
| `countTick` | 0.3s easeInOut | Countdown number changes |

```swift
// Good
.animation(SB.Anim.springSnappy, value: isSelected)
withAnimation(SB.Anim.fadeMedium) { ... }

// Bad
.animation(.easeInOut(duration: 0.25), value: isSelected)
```

### `SB.Layout` — Structural Constants

Fixed dimensions for app-level layout.

| Token | Value | Use |
|-------|-------|-----|
| `controlPanelWidth` | 316pt | Right panel total width |
| `tabBarWidth` | 36pt | Vertical icon tab bar |
| `contentAreaWidth` | 280pt | Panel content area |
| `timelineHeight` | 200pt | Timeline without zoom track |
| `timelineHeightWithZoom` | 240pt | Timeline with zoom track |
| `segmentTrackHeight` | 80pt | Segment strip height |
| `zoomTrackHeight` | 36pt | Zoom region track |
| `focusPickerHeight` | 140pt | Zoom focus picker |
| `exportPanelWidth` | 320pt | Export popup width |
| `countdownBackdropSize` | 140pt | Countdown blur circle |
| `countdownFrameSize` | 200pt | Countdown outer frame |
| `appIconSize` | 120pt | Welcome screen app icon |
| `cardThumbnailHeight` | 160pt | Project card thumbnail |
| `captureModeSelectorWidth` | 220pt | Recorder mode tabs |
| `exportProgressWidth` | 60pt | Export progress bar |
| `speedPickerWidth` | 80pt | Speed picker dropdown |

## Reusable Components

### Buttons

| Component | Use |
|-----------|-----|
| `SBPrimaryButton` | Primary CTA (coral background, capsule shape) |
| `SBSecondaryButton` | Secondary action (glass background, capsule shape) |
| `SBIconButton` | Hover-reveal icon actions (circle, material background) |

### Layout

| Component | Use |
|-----------|-----|
| `SBGlassCard` | Section container with glass material + gradient border |
| `SBPageBackground` | Full-screen background with warm ambient glow |
| `SBSectionLabel` | Uppercase tracking label for sections |
| `SBChip` | Metadata pill (resolution, duration) |
| `SBSliderRow` | Label + value + slider in a row |

### Navigation

| Component | Use |
|-----------|-----|
| `SBIconTabBar` | Vertical icon tab strip (left edge of panel) |
| `SBGlassTabs` | Horizontal segmented control (glass style) |

### Feedback

| Component | Use |
|-----------|-----|
| `SBPulsingDot` | Recording indicator with pulse animation |
| `SBComingSoonPlaceholder` | Disabled tab placeholder |
| `SBOptionSwatch` | Icon grid selector for type pickers |

### View Modifiers

| Modifier | Use |
|----------|-----|
| `.sbCard(hovered:)` | Glass card effect with hover animation |
| `.sbGlassPanel()` | Sidebar/toolbar glass material |
| `.sbShadow(preset)` | Apply a shadow preset |
| `.sbPageBackground()` | Full-screen warm background |

## Compliance Rules

The design system is enforced by `DesignSystemComplianceTests.swift` which scans all view `.swift` files for forbidden patterns:

**Forbidden in view files:**
- `.font(.system(` — use `SB.Typo.*` or `SB.Icons.*`
- `.font(.caption)` / `.font(.body)` / `.font(.title)` — use `SB.Typo.*`
- `Color(red:)` / `Color(white:)` — use `SB.Colors.*`
- `Color.red` / `Color.gray` / `Color.accentColor` — use `SB.Colors.*`
- `Color.white.opacity()` / `Color.black.opacity()` — use `SB.Glass.*` or `SB.Colors.*`
- `.foregroundStyle(.secondary)` — use `SB.Colors.textSecondary`
- `.foregroundStyle(.white)` — use `SB.Colors.textPrimary`
- `NSColor(red:)` — use `SB.Colors.accentNS`
- Raw `.shadow(color:)` — use `.sbShadow()`

**Exempt files** (data models, rendering engines, token definitions):
- `DesignSystem/*.swift`, `BackgroundModels.swift`, `FrameRenderer.swift`
- `CursorOverlayEngine.swift`, `Project.swift`, `EditorSettingsController.swift`

**Escape hatch:** Add `// sb-exempt` to any line that legitimately needs a raw value (e.g., SwiftUI mask fills, CGContext drawing, dynamic computed values).

## Adding New Tokens

1. Add the token to the appropriate namespace in `SBTokens.swift`
2. Use it in your view code
3. Run tests to verify compliance: `xcodebuild test`
4. If a raw value is truly necessary, add `// sb-exempt` with a reason

## Design Philosophy

- **Warm, not cold** — Charcoal backgrounds (`#171718`), not pure black. Coral accents, not blue.
- **Glass surfaces** — Ultra-thin material backgrounds with gradient white borders. Never flat opaque panels.
- **Generous spacing** — More whitespace than typical macOS apps. Let content breathe.
- **Rounded everything** — `.rounded` font design, generous corner radii.
- **Depth through shadow** — Layered shadows create natural elevation hierarchy.
- **Token-first** — If you're typing a raw number for color/font/spacing/radius, stop and add a token.
