# Design Doc: Chat View Refactor

**Issue:** #122 (expanded scope)
**Author:** Major
**Status:** Draft
**Goal:** Eliminate 100% CPU dead-loop during streaming. Keep current visual design. Make the architecture simple, stable, and impossible to deadlock.

---

## Problem Statement

When Claude streams a response with multiple tool calls, the chat view locks up at 100% CPU. The user cannot scroll, tap, or interact. The root cause is a reentrant layout invalidation cycle in SwiftUI:

1. `ChatViewModel` is a single `@Observable` object holding both `messages` (array) and `streamingText` (string)
2. `StreamingBubble` reads `viewModel.streamingText` → SwiftUI registers observation on the same `ChatViewModel`
3. `StreamingBubble` is inside `ForEach(viewModel.messages)` → any observation invalidation triggers ForEach to re-diff the entire array
4. Chunk arrives → writes `streamingText` → invalidates all observers → ForEach re-diffs → layout pass reads `streamingText` again → new chunk arrives → reentrant invalidation → **dead loop**

PR #123 attempted to fix this with a separate `StreamingState` object + `@ObservationIgnored`, but it didn't work — the issue likely persists because `ForEach` still needs to identify which item is `.isStreaming` and the layout invalidation still cascades through the LazyVStack.

## Design Principles

1. **No observation coupling between streaming updates and message list.** Streaming chunks must not trigger any work on the messages array or its ForEach.
2. **Streaming bubble lives outside the ScrollView.** If it's inside ForEach, SwiftUI will always re-evaluate it during layout passes. Move it out entirely.
3. **Minimal moving parts.** Fewer `@Observable` objects, fewer `onChange` handlers, fewer animation triggers.
4. **Plain Text during streaming, Markdown after finalization.** Don't parse markdown on every chunk. Only render rich content for completed messages.

## Architecture

### Current (broken)

```
ScrollView
  └─ LazyVStack
       └─ ForEach(viewModel.messages)
            ├─ MessageBubble (for completed messages)
            └─ StreamingBubble (for isStreaming=true) ← reads streamingText ← triggers ForEach diff
```

### Proposed (stable)

```
ZStack(alignment: .bottom) {
  ScrollView                              ← only completed messages, never changes during streaming
    └─ LazyVStack
         └─ ForEach(completedMessages)    ← stable array, only mutated on finalize
              └─ MessageBubble

  if isStreaming {
    StreamingOverlay                      ← pinned to bottom, outside ScrollView entirely
      └─ StreamingBubble                  ← reads streamingText, no ForEach involvement
  }

  InputBar                                ← always at bottom
}
```

### Key Changes

#### 1. Split `ChatViewModel` into focused pieces

**`MessageStore`** — holds the completed messages array. Only mutated when:
- User sends a message (append user message)
- Turn ends (append finalized assistant message)
- History replay completes (bulk replace)
- Error occurs (append error message)

```swift
@Observable @MainActor
final class MessageStore {
    private(set) var messages: [ChatMessage] = []
    var isLoadingHistory = false

    func appendUser(_ text: String) { ... }
    func finalizeAssistant(text: String, toolUses: [ToolUseInfo]) { ... }
    func appendError(_ message: String) { ... }
    func replaceAll(_ messages: [ChatMessage]) { ... }  // for replay
}
```

**`StreamingState`** — holds current streaming data. Completely isolated from MessageStore.

```swift
@Observable @MainActor
final class StreamingState {
    private(set) var text: String = ""
    private(set) var toolUses: [ToolUseInfo] = []
    private(set) var isActive: Bool = false

    func begin() { ... }
    func appendText(_ chunk: String) { ... }
    func appendToolCall(...) { ... }
    func updateToolCall(...) { ... }
    func finalize() -> (text: String, toolUses: [ToolUseInfo]) { ... }
}
```

**`ChatViewModel`** — thin coordinator. Receives daemon messages, routes to MessageStore or StreamingState. Holds session metadata (agent, model, permissions, usage).

```swift
@Observable @MainActor
final class ChatViewModel {
    let messages: MessageStore       // not @ObservationIgnored — views can observe it
    let streaming: StreamingState    // separate observation scope

    // Session metadata
    private(set) var isWaiting = false
    private(set) var hasError = false
    private(set) var turnUsage: TurnUsage?
    private(set) var sessionAgent: String = "claude"
    // ... permissions, models, modes
}
```

#### 2. StreamingBubble outside the ScrollView

The critical architectural change. `StreamingBubble` is a **fixed overlay at the bottom of the chat**, not inside the `ForEach`. This means:

- StreamingBubble observation is completely disconnected from LazyVStack layout
- Chunk updates only redraw the overlay, never touch the scroll content
- ScrollView content only contains finalized messages — stable, no hot updates

```swift
struct ChatView: View {
    let viewModel: ChatViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Layer 1: Completed messages (stable)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Invisible spacer when streaming, so scroll content
                        // has room for the overlay
                        if viewModel.streaming.isActive {
                            Color.clear
                                .frame(height: streamingOverlayHeight)
                                .id("streaming-spacer")
                        }
                    }
                    .padding()
                }
            }

            // Layer 2: Streaming overlay (pinned to bottom, outside scroll)
            if viewModel.streaming.isActive {
                StreamingOverlay(streaming: viewModel.streaming)
                    .padding(.bottom, inputBarHeight)
            }

            // Layer 3: Input bar
            if !viewModel.hasError {
                inputBar
            }
        }
    }
}
```

#### 3. Plain text during streaming, Markdown after finalize

`StreamingBubble` renders plain `Text(streaming.text)` — no markdown parsing, no syntax highlighting. Fast and cheap.

`MessageBubble` renders `MarkdownContentView(text: message.text)` — only for finalized messages. Since finalized messages don't change, markdown parsing runs once and caches.

#### 4. Throttled streaming text updates (optional, if still needed)

If plain text rendering is still too frequent (unlikely), add a simple throttle:

```swift
// In StreamingState
private var pendingText: String = ""
private var flushTask: Task<Void, Never>?

func appendText(_ chunk: String) {
    pendingText += chunk
    flushTask?.cancel()
    flushTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(32))  // ~30fps
        guard !Task.isCancelled else { return }
        text += pendingText
        pendingText = ""
    }
}
```

This batches rapid chunks into ~30fps updates. But try without throttling first — plain text rendering should be fine.

#### 5. Scroll behavior

- **Auto-scroll on new messages:** `onChange(of: viewModel.messages.messages.count)` — only fires on finalize/user send, not on every chunk
- **Auto-scroll during streaming:** Use `onChange(of: viewModel.streaming.isActive)` to scroll to `"streaming-spacer"` when streaming starts
- **No scroll-on-every-chunk:** The streaming overlay is pinned to the bottom, so it's always visible without scrolling

#### 6. MarkdownContentView simplification

Keep the current markdown parser but ensure:
- `parse()` only runs on `onAppear` and when `content` changes (already has guard)
- Remove `Task.detached` for markdown — it causes race conditions. Markdown parsing is fast enough on-main for finalized messages (they don't change)
- Syntax highlighting can stay synchronous — it only runs once per code block on finalized messages

---

## Issue Breakdown

### Issue 1: Extract `MessageStore` from `ChatViewModel`
- Create `MessageStore.swift` with `messages`, `isLoadingHistory`, replay buffer logic
- `ChatViewModel` holds a `let messages: MessageStore`
- Update all views to read `viewModel.messages.messages`
- No visual changes. Pure refactor.

### Issue 2: Extract `StreamingState` from `ChatViewModel`
- Create `StreamingState.swift` (text, toolUses, isActive, begin/append/finalize)
- `ChatViewModel` holds a `let streaming: StreamingState`
- Route daemon events to correct store
- No visual changes yet.

### Issue 3: Move `StreamingBubble` outside ScrollView
- Restructure `ChatView` to use ZStack layout
- `StreamingBubble` reads only `StreamingState`, pinned to bottom
- Add streaming spacer in ScrollView for layout room
- Remove `isStreaming` flag from `ChatMessage` struct (no longer needed)
- This is the **key fix** for the CPU issue.

### Issue 4: Plain text streaming, Markdown on finalize
- `StreamingBubble` uses `Text(streaming.text)` — no MarkdownContentView
- `MessageBubble` continues using `MarkdownContentView` for finalized messages
- This eliminates all markdown parsing during streaming.

### Issue 5: Clean up scroll handling
- Remove `scrollTask` debouncing complexity
- `onChange(of: messages.count)` for user/finalize scroll
- `onChange(of: streaming.isActive)` for streaming-start scroll
- No scroll on every chunk (overlay is always visible)

---

## Testing

### Acceptance Criteria
1. Open a session with 50+ messages of history → loads without lag
2. Send a message that triggers 5+ tool calls → streaming shows text + tool cards
3. During streaming, scroll up through history → **no hang, no stutter, CPU < 30%**
4. Streaming completes → assistant message appears in scroll list with full Markdown
5. Error state → orange card, input disabled, no duplicate on re-enter
6. Permission modal → appears and functions during streaming
7. Session list → shows correct session titles and timestamps

### Non-goals
- No visual design changes (keep current Liquid Glass style)
- No new features
- No daemon changes

---

## Risk Assessment

**Low risk:** Issues 1-2 are pure refactors, extracting existing code into separate files. Tests can verify no behavior change.

**Medium risk:** Issue 3 changes the view hierarchy. The streaming overlay positioning needs care — it must not overlap with the input bar and must scroll away when streaming ends. However, the approach is simpler than the current one (fewer moving parts = fewer bugs).

**Low risk:** Issues 4-5 are simplifications that remove code rather than add it.
