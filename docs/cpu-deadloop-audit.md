# CPU Dead Loop Audit — Recent 25 Commits

**Audit date:** 2026-04-16
**Branch:** `debug/cpu-recursion-logging`
**Scope:** Identify commits that could cause infinite recursion / 100% CPU.

---

## Summary

The original CPU dead loop root cause was identified and fixed in `bb75cae`:
StreamingBubble was inside the `ForEach(messages)` within `LazyVStack`. Each streaming
chunk triggered SwiftUI observation → ForEach re-diff → reentrant layout invalidation → 100% CPU.

After the fix series (#129–#133), residual risk is low, mainly concentrated in
`CachedMarkdownText.parse()`'s async `@State` writeback pattern.

---

## Commits by Project Path

### `app/VibeAnywhere/Views/` — UI Layer

| Commit | PR | Description | CPU Risk |
|--------|----|-------------|----------|
| `d26565f` | #133 | Simplify ChatView scroll handling | Low |
| `a783282` | #132 | Background Markdown/syntax highlighting | Medium-Low |
| `bb75cae` | #131 | Move StreamingBubble outside ScrollView | **Fixed original bug** |
| `aeb2008` | #100 | Cancel scroll debounce on view disappear | Low |
| `7ee6471` | #119 | Port formatting, shadow consistency | None |
| `b53f34a` | #114 | Add shadows to Settings/NewSession cards | None |
| `735986a` | #113 | Liquid Glass visual polish | None |
| `c0a73a3` | #107 | Replace opaque surfaces with translucent materials | None |
| `644d4ab` | #106 | Soften error card borders | None |
| `78460cc` | #105 | Remove unsupported Gemini/Codex options | None |
| `077bbf8` | #99 | UI refinements, error styling | None |
| `2a0c106` | #91 | NewSession/SessionSettings theming | None |
| `8365f2b` | #89 | Connection timeout feedback | None |
| `1b28b58` | #86 | Toolbar icons + session cards | None |
| `027e8fb` | #83 | Empty state, force light mode, Settings theming | None |

### `app/VibeAnywhere/ViewModels/` — ViewModel Layer

| Commit | PR | Description | CPU Risk |
|--------|----|-------------|----------|
| `ab8a378` | #130 | Extract StreamingState from ChatViewModel | Safe — isolated observation chain |
| `02a3496` | #129 | Extract MessageStore from ChatViewModel | Safe — pure refactor |

### `app/VibeAnywhere/Services/` — Service Layer

| Commit | PR | Description | CPU Risk |
|--------|----|-------------|----------|
| `a79c853` | #108 | Fix reconnect counter stuck at (1/10) | None |

### `app/VibeAnywhere/` — Models, Tests, Assets

| Commit | PR | Description | CPU Risk |
|--------|----|-------------|----------|
| `3417842` | #98 | Update test patterns for replay params | None |
| `7f7bd46` | #121 | Add app icon | None |

### Cross-layer (Views + ViewModels)

| Commit | Description | CPU Risk |
|--------|-------------|----------|
| `0998ae9` | Add CPU recursion diagnostic logging | None (diagnostic only) |
| `8255d59` (#94) | Session resume | None |
| `1cd9692` | UX refinements and bug fixes | Low |
| `bd71172` | "bad tried" (failed attempt) | Unknown (pre-refactor) |

### `daemon/` — Node.js Backend

| Commit | Description | CPU Risk |
|--------|-------------|----------|
| `f807a4b` | Temp changes (acp-manager, config, sessions) | None (server-side) |
| `78460cc` (#105) | Remove Gemini/Codex (acp-manager) | None |
| `8255d59` (#94) | Session resume (acp-manager, sessions, types) | None |
| `1cd9692` | UX refinements (sessions, types) | None |
| `bd71172` | Failed attempt (sessions) | None |

### `docs/` — Documentation

| Commit | File |
|--------|------|
| `0998ae9` | chat-view-refactor.md |
| `077bbf8` | ui-refinement-rca.md |

---

## Detailed Risk Analysis

### 1. `bb75cae` — StreamingBubble Fix (fixed original bug)

**Original root cause:** StreamingBubble was inside `ForEach(messages)`. Each streaming chunk
mutated the messages array → ForEach re-diff → reentrant layout invalidation → 100% CPU dead loop.

**Fix:** Move StreamingBubble outside ScrollView into a ZStack overlay.
ForEach now only iterates completed messages (stable during streaming). Streaming chunks
cause only one view (StreamingBubble) to redraw.

### 2. `a783282` — Background Markdown Parsing (medium-low risk)

`CachedMarkdownText.parse()` uses `Task.detached` to parse markdown on a background thread,
then writes the result back to `@State attributed`:

```swift
Task.detached(priority: .userInitiated) {
    let result = ...
    await MainActor.run {
        guard content == src else { return }  // Staleness check
        attributed = result  // Writes @State → triggers body re-evaluation
    }
}
```

**Potential loop path:**
1. `attributed = result` writes `@State` → SwiftUI marks view as dirty
2. SwiftUI re-evaluates `CachedMarkdownText.body`
3. If the parent view recreates the view with the same content, `onChange(of: content)` fires
   again → `parse()` → back to step 1

**Existing mitigations:**
- Staleness check (`guard content == src`) prevents stale writes
- `onChange(of: content)` only fires when content actually changes (String value equality)
- In practice, finalized message content is stable

**Scenario where it could fail:** If the parent view recreates `CachedMarkdownText` with the
same content but a new view identity (e.g., ForEach ID changes), `onAppear` fires again
→ `parse()` → `@State` write → body re-evaluation. This is bounded (one extra evaluation)
but worth monitoring.

### 3. `d26565f` — Scroll Simplification (low risk)

Removed debounce wrapper. `scrollToBottom()` now fires directly from
`onChange(of: messages.count)` and `onChange(of: streaming.isActive)`.

No loop risk: scroll operations don't trigger observation changes that would cause reentrant
scroll handling.

### 4. `ab8a378` — StreamingState Extraction (safe)

`@ObservationIgnored let streaming = StreamingState()` on ChatViewModel means chunk updates
to `streaming.text` don't propagate through ChatViewModel's observation chain.
Only `StreamingBubble` (which directly holds `StreamingState`) redraws on each chunk.

**Note:** `ChatView.body` directly reads `viewModel.streaming.isActive` (lines 100, 110).
This creates a direct observation on `StreamingState.isActive`, but `isActive` only changes
on `begin()` and `finalize()` (once per turn each), not on every chunk.
No high-frequency loop.

### 5. `02a3496` — MessageStore Extraction (safe)

Pure refactor. Moved message array and replay buffer from ChatViewModel to a separate
`@Observable` class. Logic unchanged.

---

## Items to Monitor

1. **`CachedMarkdownText` async parse writeback** — Monitor body evaluation count via
   diagnostic logging added in `0998ae9`. If `bodyEvalCount > 50` triggers, the parse
   loop is reentering.

2. **`MarkdownContentView.updateSegments()`** — Writes `@State cachedSegments` and
   `@State cachedDisplayText`. Protected by `guard dt != cachedDisplayText`, but depends
   on `displayText` computed property being deterministic.

3. **Diagnostic logging performance overhead** — Current diagnostic logs on hot paths
   (`cpuLog` calls in StreamingState.appendText, CachedMarkdownText.body) carry non-trivial
   overhead. Should be removed before release.
