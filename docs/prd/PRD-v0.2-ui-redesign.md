# PRD: v0.2 — UI Redesign: Dark Terminal Aesthetic

**Status:** Draft
**Author:** Major
**Date:** 2026-04-12
**Depends on:** v0.1.0 (MVP)
**Issue:** #52

## Problem

The current iOS UI is a plain white iMessage clone — blue user bubbles, gray assistant bubbles, white background, no personality. For an app that controls a coding agent, it looks generic and uninspired.

## Goal

Redesign the iOS app with a dark, terminal-inspired aesthetic that says "this is a tool for developers." The vibe should feel like using a premium terminal emulator (iTerm2, Ghostty, Warp) on your phone — not a chat app.

## Design Principles

1. **Dark-first** — dark backgrounds, high contrast text, no light mode (for now)
2. **Terminal heritage** — monospaced fonts where appropriate, command-line visual language
3. **Minimal chrome** — let content breathe, reduce decorative elements
4. **Functional aesthetics** — every visual element communicates state (streaming, done, error, tool running)

## Color Palette

### Base Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `background` | `#0D1117` | App background, scroll areas |
| `surface` | `#161B22` | Cards, bubbles, input bar |
| `surfaceElevated` | `#1C2128` | Elevated cards (tool use, settings sections) |
| `border` | `#30363D` | Subtle borders, dividers |

### Text Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `textPrimary` | `#E6EDF3` | Body text, message content |
| `textSecondary` | `#8B949E` | Captions, timestamps, paths |
| `textMuted` | `#484F58` | Disabled, placeholder |

### Accent Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `accent` | `#00FF41` | Primary accent — send button, active states, user bubble border |
| `accentDim` | `#00CC33` | Pressed states, secondary accent |
| `accentGlow` | `#00FF41` @ 15% opacity | Subtle glow behind active elements |

### Semantic Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `success` | `#3FB950` | Connected status, completed tools |
| `warning` | `#D29922` | Reconnecting, slow responses |
| `error` | `#F85149` | Disconnected, errors |
| `info` | `#58A6FF` | Links, informational |

## Typography

| Context | Font | Example |
|---------|------|---------|
| Message text | SF Pro (system default) | "Let me look at the code..." |
| Code / paths / tool I/O | `.system(.body, design: .monospaced)` | `~/projects/my-app` |
| Session name | `.system(.headline, design: .monospaced)` | `my-app` |
| Input prompt prefix | `.system(.body, design: .monospaced)` | `>` |
| Tool name header | `.system(.caption, design: .monospaced).bold()` | `$ Read file` |

## Component Designs

### Chat View (`ChatView.swift`)

**Background:** `background` color, edge-to-edge

**Input bar:**
```
┌─────────────────────────────────────────────┐
│  > Message…                            [▲]  │
│  surface bg, border top                      │
└─────────────────────────────────────────────┘
```
- Background: `surface`
- Top border: `border` (1px)
- `>` prefix: `accent` color, monospaced
- Send button: `accent` tint, `arrow.up.circle.fill`
- Disabled state: `textMuted` for prefix and button

### Message Bubbles (`MessageBubble.swift`)

**User message:**
```
                    ┌──────────────────────┐
                    │ Fix the login bug    │
                    │                      │
                    └──────────────────────┘
                    accent border (1pt), surface bg
                    right-aligned, rounded 12pt
```

**Assistant message:**
```
┃ Let me look at the authentication
┃ module...
│
accent left bar (3pt), surface bg
left-aligned, rounded 12pt
```

**Streaming state:**
- Blinking block cursor `█` at end of text
- Animation: `opacity 0↔1` with `.easeInOut(duration: 0.6).repeatForever()`
- If no text yet: `Thinking…` with pulsing dots

### Tool Use Card (`ToolUseCard`)

```
┌─────────────────────────────────────┐
│  $ Read file                    ▼   │
│  surfaceElevated bg                 │
│                                     │
│  (expanded:)                        │
│  path: "src/auth.ts"                │
│  monospaced, textSecondary          │
└─────────────────────────────────────┘
```
- Background: `surfaceElevated`
- Header: `$ ` prefix in `accent`, tool name in monospaced bold
- Chevron: `textSecondary`
- Border: `border` (0.5pt)
- Expanded content: monospaced, `textSecondary`

### Session List (`SessionListView.swift`)

**Row:**
```
┌─────────────────────────────────────┐
│  📁  my-app                        │
│      ~/projects/my-app              │
│  surface bg                         │
└─────────────────────────────────────┘
```
- Background: `background`
- Row cards: `surface` with `border` (0.5pt)
- Project name: monospaced headline, `textPrimary`
- Path: monospaced caption, `textSecondary`
- `+` button: `accent` tint

**Empty state:**
- Terminal icon
- "No sessions. Create one to start coding."
- `textSecondary`

### Settings View (`SettingsView.swift`)

- Dark form sections with `surfaceElevated` background
- Token field: monospaced, `accent` text color (like a terminal password prompt)
- Connection status dot: `success`/`warning`/`error` with subtle glow (`shadow(color:radius:)`)
- Connect button: `accent` tint
- Section headers: `textSecondary`, uppercase, small

### New Session View (`NewSessionView.swift`)

- Dark form matching Settings style
- Path input: monospaced, `accent` text
- Recent dirs: folder icon + monospaced path
- Create button: `accent` tint

## Implementation Plan

### 1. Theme file (`Theme.swift`)

New file with all color and font definitions as static extensions:

```swift
enum VibeTheme {
    // Colors
    static let background = Color(hex: 0x0D1117)
    static let surface = Color(hex: 0x161B22)
    static let surfaceElevated = Color(hex: 0x1C2128)
    static let border = Color(hex: 0x30363D)
    
    static let textPrimary = Color(hex: 0xE6EDF3)
    static let textSecondary = Color(hex: 0x8B949E)
    static let textMuted = Color(hex: 0x484F58)
    
    static let accent = Color(hex: 0x00FF41)
    static let accentDim = Color(hex: 0x00CC33)
    
    static let success = Color(hex: 0x3FB950)
    static let warning = Color(hex: 0xD29922)
    static let error = Color(hex: 0xF85149)
    static let info = Color(hex: 0x58A6FF)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
```

### 2. Force dark mode

In `VibeAnywhereApp.swift`:
```swift
.preferredColorScheme(.dark)
```

### 3. View modifications

Each view file gets updated to use `VibeTheme` colors and fonts. No logic changes — purely visual.

## Files Changed

| File | Change |
|------|--------|
| NEW `Theme.swift` | Color palette + font definitions |
| `VibeAnywhereApp.swift` | Add `.preferredColorScheme(.dark)` |
| `ChatView.swift` | Dark bg, styled input bar with `>` prompt |
| `MessageBubble.swift` | Accent-bordered user, left-bar assistant, blinking cursor |
| `ToolUseCard` (in MessageBubble.swift) | Terminal-style `$` header |
| `SessionListView.swift` | Dark list, monospace styling |
| `SettingsView.swift` | Dark form, green token, glow status |
| `NewSessionView.swift` | Dark form, monospace path |

## Estimate

~300-400 LOC changes across 7 files + 1 new file.

## Not in Scope

- App icon redesign
- Custom fonts (SF Mono is system-provided)
- Light mode support
- Launch screen redesign
- Complex animations beyond cursor blink

## Open Questions

1. **Accent color: green vs cyan?** Green (`#00FF41`) feels more terminal/Matrix. Cyan (`#00D4FF`) feels more modern/Tron. Going with green for now — easier to change later since it's centralized in `Theme.swift`.
2. **Markdown rendering?** Claude often returns markdown. For v0.2 we keep plain text. Markdown rendering is a separate issue.
