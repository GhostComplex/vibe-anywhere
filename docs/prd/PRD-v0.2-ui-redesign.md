# PRD: v0.2 — UI Redesign: Pixel Art + Claude Orange + Liquid Glass

**Status:** Draft (Rev 2)
**Author:** Major
**Date:** 2026-04-12
**Depends on:** v0.1.0 (MVP)
**Issue:** #52

## Problem

The current iOS UI is a plain white iMessage clone — no personality, no brand identity. The dark terminal mockup (rev 1) was too geeky/hacker. Need something warmer with brand identity.

## Direction Change (Steins feedback)

- ❌ ~~Neon green terminal aesthetic~~ → too cold, too hacker
- ✅ **Claude orange** as primary accent — brand alignment
- ✅ **8-bit pixel art** vibe — retro, fun, approachable
- ✅ **Liquid Glass** effects (iOS 26) — modern + playful
- ✅ **Fix Tab Bar** — current system blue tabs clash with dark theme

## Design Principles

1. **Pixel-retro meets modern** — 8-bit pixel art elements (icons, decorations) on top of clean iOS Liquid Glass surfaces
2. **Claude orange identity** — warm orange accent throughout, not cold neon
3. **Liquid Glass everywhere** — tab bar, nav bar, input bar, cards all use iOS 26 glass materials
4. **Dark-first** — dark background stays, but warmer tones
5. **Fun, not intimidating** — a developer tool that doesn't take itself too seriously

## Color Palette

### Base Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `background` | `#1A1410` | App background — warm dark brown-black |
| `surface` | Liquid Glass | Cards, bubbles — use `.glassEffect()` |
| `surfaceElevated` | Liquid Glass (prominent) | Tool cards, settings sections |

### Accent — Claude Orange

| Token | Hex | Usage |
|-------|-----|-------|
| `accent` | `#E07538` | Primary — Claude's brand orange |
| `accentLight` | `#F0A060` | Highlights, glows, pressed states |
| `accentDim` | `#C05A20` | Dark pressed states |

### Text Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `textPrimary` | `#F0E6D8` | Body text — warm off-white |
| `textSecondary` | `#9E8E7E` | Captions, timestamps — warm gray |
| `textMuted` | `#5E5248` | Disabled, placeholder |

### Semantic Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `success` | `#4CAF50` | Connected, completed |
| `warning` | `#FFB74D` | Reconnecting |
| `error` | `#EF5350` | Disconnected, errors |

## Typography

| Context | Font | Notes |
|---------|------|-------|
| Message text | SF Pro (system) | Standard readability |
| Code / paths | `.system(.body, design: .monospaced)` | Monospace for technical content |
| Pixel decorations | Custom 8-bit pixel font (optional) | Headers, empty states, fun elements |
| Session name | `.system(.headline, design: .monospaced)` | Project identity |

### Pixel Font Option

Consider bundling a free pixel font (e.g., "Press Start 2P" or "Silkscreen") for:
- Empty state messages ("No sessions yet! Create one ▶")
- Section headers in settings
- Fun decorative elements

If too heavy, use SF Mono with pixelated decorative Unicode characters instead.

## Component Designs

### Tab Bar

**Problem:** System blue tab icons clash with dark theme.
**Fix:** Use Liquid Glass tab bar with Claude orange selected state.

```swift
.tabViewStyle(.tabBarOnly)
// Custom tab item tint
.tint(VibeTheme.accent)  // Claude orange
```

- Selected: Claude orange icon + label
- Unselected: warm gray (`textSecondary`)
- Background: Liquid Glass material
- Consider pixel-art style tab icons (tiny 16×16 pixel sprites)

### Chat View (`ChatView.swift`)

**Background:** Warm dark `background` color

**Input bar:**
- Liquid Glass background
- `>` prompt prefix in Claude orange (keep the terminal nod)
- Orange send button (`arrow.up.circle.fill`)
- Pixel-art cursor blink in input field

### Message Bubbles (`MessageBubble.swift`)

**User message:**
- Liquid Glass bubble with Claude orange tint/border
- Right-aligned
- Subtle orange glow

**Assistant message:**
- Liquid Glass bubble, left-aligned
- Left accent bar in Claude orange (3pt)
- Or: pixel-art speech bubble border (8-bit style corners)

**Streaming state:**
- Blinking pixel block cursor `█` in Claude orange
- Or: animated pixel dots `...` in 8-bit style

### Tool Use Card

- Liquid Glass elevated card
- `$ tool_name` header still works (keep some terminal flavor)
- Orange chevron for expand/collapse
- Pixel-art border decoration (optional)

### Session List (`SessionListView.swift`)

- Warm dark background
- Liquid Glass row cards
- Folder icon in Claude orange
- Project name: monospace, warm white
- Path: monospace, warm gray
- Active indicator: orange dot with glow
- `+` button: Claude orange

### Settings View (`SettingsView.swift`)

- Liquid Glass form sections
- Token field: monospace, Claude orange text
- Connection status: orange (connected) / red (error) dot with glow
- Connect button: Claude orange filled

### New Session View (`NewSessionView.swift`)

- Liquid Glass form
- Orange-tinted path input
- Recent dirs with pixel-art folder icons

## 8-Bit Pixel Art Elements

Add pixel-art flair without going overboard:

1. **Empty state illustrations** — Small pixel art scenes
   - No sessions: pixel computer with `>_` prompt
   - Disconnected: pixel broken cable
   - Loading: pixel hourglass animation

2. **Custom icons** (optional, stretch goal)
   - Tab bar: pixel chat bubble, pixel folder, pixel gear
   - Send button: pixel arrow
   - Tool cards: pixel wrench, pixel file, pixel terminal

3. **Decorative borders** (optional)
   - Pixel-art corner decorations on cards
   - 8-bit style dividers between sections

4. **Pixel cursor** — `█` blinking cursor during streaming, styled as an 8-bit block

## Liquid Glass (iOS 26)

Use SwiftUI Liquid Glass modifiers where available:

```swift
// Glass background for cards
.glassEffect(.regular)

// Glass tab bar
TabView { ... }
    .glassEffect(.regular)

// Glass navigation bar
.toolbarBackground(.hidden, for: .navigationBar)
.glassEffect(.regular)
```

**Fallback:** For iOS < 26, use `.ultraThinMaterial` as a fallback glass effect.

## Implementation Plan

### 1. Theme file (`Theme.swift`)

All colors as static extensions with Claude orange palette.

### 2. Force dark mode + Liquid Glass

```swift
// App entry
.preferredColorScheme(.dark)
```

### 3. Tab Bar fix

```swift
TabView { ... }
    .tint(VibeTheme.accent)
```

### 4. View modifications

Each view updated for warm dark + Claude orange + Liquid Glass.

### 5. Pixel art assets (stretch)

Add pixel art as SF Symbol alternatives or small PNG/SVG assets.

## Files Changed

| File | Change |
|------|--------|
| NEW `Theme.swift` | Claude orange palette + Liquid Glass helpers |
| `VibeAnywhereApp.swift` | Dark mode + tab tint |
| `ChatView.swift` | Glass input bar, warm bg, orange accents |
| `MessageBubble.swift` | Glass bubbles, orange accent bar, pixel cursor |
| `SessionListView.swift` | Glass rows, orange icons, warm styling |
| `SettingsView.swift` | Glass forms, orange token, glow status |
| `NewSessionView.swift` | Glass form, orange path |
| NEW `Assets/` | Pixel art assets (if using custom icons) |

## Estimate

~400-500 LOC across 7-8 files + 1 new Theme file + optional pixel assets.

## Not in Scope

- App icon redesign (separate task)
- Custom pixel font bundling (use system fonts for v1)
- Complex pixel art animations
- Light mode

## Open Questions

1. **Pixel font?** Use "Press Start 2P" for headers/empty states, or stick with system SF Mono? → Start with SF Mono, add pixel font as follow-up if it fits.
2. **Liquid Glass availability?** iOS 26 only. Do we need iOS 18 fallback? → Yes, use `.ultraThinMaterial` fallback.
3. **Pixel art assets?** Commission/find free 8-bit icons or use Unicode pixel characters? → Start with Unicode/SF Symbols, add custom art later.
4. **How much pixel?** Full pixel-art UI or just decorative touches? → Decorative touches only — pixel cursor, pixel empty states, maybe pixel tab icons. Keep the core UI clean.
