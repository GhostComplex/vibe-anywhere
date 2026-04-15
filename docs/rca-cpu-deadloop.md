# RCA: SwiftUI "Modifying state during view update" Causing 100% CPU

**Date:** 2026-04-16
**Severity:** P1 — User-perceptible UI freeze / device overheating
**Scope:** All session resume scenarios (sessions with history messages)
**Fix branch:** `debug/cpu-recursion-logging`

---

## 1. Symptoms

When resuming a session with multiple history messages, the app CPU spikes to 100%, the UI freezes, and the device overheats. Xcode console continuously outputs `Modifying state during view update, this will cause undefined behavior.` warnings.

---

## 2. Root Cause

**Not a single bug, but three overlapping issues:**

### 2.1 Diagnostic code itself became the problem source (primary)

Commit `0998ae9` added CPU recursion diagnostic logging that **synchronously mutated `@State bodyEvalCount` inside every view's `body`**:

```swift
var body: some View {
    let _ = {
        bodyEvalCount += 1  // ← Writing @State during body evaluation!
        cpuLog.warning("...")
    }()
    ...
}
```

SwiftUI prohibits state mutation during `body` evaluation. The `bodyEvalCount += 1` directly violates this constraint, causing SwiftUI to mark the view as dirty, triggering additional body evaluations and creating an **avalanche effect**.

This pattern existed in 6 views (ChatView, MarkdownContentView, CachedMarkdownText, SyntaxHighlightedText, MessageBubble, StreamingBubble), each triggering on every body evaluation. When replay loads 8-9 messages at once, dozens of views do this simultaneously, cascading and amplifying.

**The irony:** The diagnostic code was added to find the dead loop, but the diagnostic code itself created the largest CPU hotspot.

### 2.2 MarkdownContentView.updateSegments() synchronously writes @State during view update

```swift
.onAppear { updateSegments() }  // onAppear may be called during layout pass

func updateSegments() {
    cachedDisplayText = dt      // ← Writing @State
    cachedSegments = parseSegments(dt)  // ← Writing @State
}
```

`onAppear` may execute synchronously during SwiftUI's initial layout (rather than being deferred until after layout completes). Writing `@State` at this point produces the "Modifying state during view update" warning and causes the view to be marked dirty for re-evaluation.

### 2.3 CachedMarkdownText.parse() repeatedly triggered during LazyVStack scrolling

```swift
.onAppear { parse() }  // LazyVStack recycles view, scrolling back triggers onAppear again
```

`parse()` asynchronously parses markdown via `Task.detached`, then writes back to `@State attributed`. When LazyVStack recycles a view identity and re-displays it, `onAppear` fires again → parses again → writes `@State` again → triggers body re-evaluation. For the same unchanged message, parsing repeats endlessly.

### Trigger chain timeline

```
endReplay() writes 8 messages to items array
  → SwiftUI begins layout
    → ChatView.body evaluation
      → bodyEvalCount += 1          ← "Modifying state during view update"
      → ForEach iterates 8 messages
        → Each MessageBubble.body
          → bodyEvalCount += 1      ← "Modifying state during view update"
          → MarkdownContentView.body
            → bodyEvalCount += 1    ← "Modifying state during view update"
            → onAppear → updateSegments()
              → cachedSegments = ...  ← "Modifying state during view update"
              → CachedMarkdownText.body
                → bodyEvalCount += 1  ← "Modifying state during view update"
                → onAppear → parse()
                  → Task.detached → attributed = result  ← triggers body re-eval
    → SwiftUI finds many dirty views → re-evaluates → loop
```

8 messages × 4-6 nested views per message × at least 1 @State write per view = **40-50+ "Modifying state during view update" events**, producing cascading re-evaluations.

---

## 3. Why it took all afternoon to fix

| Phase | What was done | Why it didn't resolve the issue |
|-------|---------------|--------------------------------|
| Phase 1 | Identified streaming chunk → ForEach re-diff dead loop (fixed in `bb75cae`) | Correct fix, but not the only problem |
| Phase 2 | Extracted StreamingState, MessageStore to isolate observation chains (#129 #130) | Correct architectural improvement, but replay path issues were masked |
| Phase 3 | Background markdown parsing, simplified scrolling (#132 #133) | Improved streaming path, but replay path still broken |
| Phase 4 | Added diagnostic logging (`0998ae9`) to locate residual issues | **Diagnostic code itself became a new problem source** |

**Core mistakes:**

1. **Focused only on the streaming path, missed the replay path.** The original dead loop (ForEach + streaming chunk) was indeed fixed, but replay bulk-inserting many messages also triggers similar cascading re-evaluations through a different mechanism.

2. **Diagnostic code introduced new problems.** The seemingly harmless `bodyEvalCount += 1` counter, mutated as `@State` inside body, triggered exactly the anti-pattern SwiftUI hates most. With diagnostic logging present, CPU remained high even after the original fix — leading to the false conclusion that the fix hadn't worked.

3. **Didn't remove diagnostic code before observing results.** After adding logs and seeing the issue persist, more time was spent exploring other directions instead of considering "could the diagnostic code itself be the problem?"

---

## 4. Fix

### 4.1 Remove all diagnostic code
Delete `cpuLog`, `bodyEvalCount`, and body closure logging from all 6 affected files.

### 4.2 `MarkdownContentView`: `.onAppear` → `.task(id:)`
```swift
// Before
.onAppear { updateSegments() }
.onChange(of: text) { _, _ in updateSegments() }

// After
.task(id: text) { updateSegments() }
```
`.task` guarantees execution after layout completes — no synchronous @State writes during view update.

### 4.3 `CachedMarkdownText`: Prevent redundant parsing
```swift
func parse() {
    guard attributed == nil else { return }  // Cache hit, skip
    ...
}
```
`onChange(of: content)` sets `attributed = nil` before calling `parse()`.

### 4.4 `SyntaxHighlightedText`: Same pattern as above.

---

## 5. Lessons Learned

1. **Diagnostic code must be side-effect-free.** In SwiftUI body, any `@State` mutation is a side effect. If you need to count body evaluations, use `print()` instead of an `@State` counter.

2. **SwiftUI's `onAppear` does not guarantee execution after layout completes.** If you need to write @State on appear, use `.task {}` instead of `.onAppear {}`.

3. **When debugging performance issues, remove diagnostic code before observing results.** Otherwise you can't distinguish "the original problem" from "problems introduced by diagnostics."

4. **Replay and streaming are two distinct hot paths** — they need separate testing. Fixing one doesn't mean the other is fine.

---

## 6. Verification

- [ ] Resume a session with multiple history messages — no "Modifying state during view update" warnings in console
- [ ] CPU stays normal (no spike)
- [ ] Streaming displays and finalizes correctly
- [ ] Expand/collapse long messages works
- [ ] LazyVStack scrolling doesn't re-parse already cached markdown
