# UI Refinement RCA

**Date:** 2026-04-14
**Commits:** `5ff0fed`, `01fd663`, `e733ecb`
**Branch:** `user/steins/fix`
**Files changed:** 12 (107 insertions, 71 deletions)

---

## Summary

Three categories of issues were identified and fixed: visual border/shadow inconsistencies across the app, a harsh navigation bar overlay in ChatView, and unhandled error state in chat sessions.

---

## Issue 1: Hard borders across all views

**Symptom:** All cards, toolbar buttons, and interactive elements had visible 1px solid borders, giving the app a boxy, dated look.

**Root Cause:** `Theme.border` (`#E8E7E3`) was applied at full opacity with `lineWidth: 1` uniformly across all views. The `CardStyle` modifier and individual views all used the same hard stroke. Shadow values were too subtle (`0.04` opacity, `radius: 2`) to provide depth without border assistance.

**Fix (commit `5ff0fed`):**
- Border color lightened to `#EBEBEB`
- All strokes reduced to `lineWidth: 0.5` at `opacity(0.6)`
- Shadow opacity increased from `0.04` to `0.06`, radius from `2` to `4`
- Toolbar buttons (gear, plus): replaced border stroke with shadow
- Circular icons (empty state, connecting/disconnected): replaced border with shadow
- `SessionSettingsSheet.themedCard()`: added missing shadow to match global `CardStyle`
- `EmptyStateView` chips: added shadow for consistency

**Files affected:** `Theme.swift`, `ContentView.swift`, `SessionListView.swift`, `NewSessionView.swift`, `EmptyStateView.swift`, `MarkdownContentView.swift`, `SessionSettingsSheet.swift`, `SettingsView.swift`, `PermissionViews.swift`

**Test points:**
- [ ] Session list: card borders and toolbar button shadows
- [ ] New Session sheet: input fields, agent selector, recent list
- [ ] Settings sheet: connection/auth/status sections
- [ ] Session Settings (ellipsis menu): all section cards have shadow
- [ ] Empty chat state: chips and logo icon
- [ ] Code blocks in messages: border treatment
- [ ] Permission modal: card styling and shadow

---

## Issue 2: Harsh navigation bar overlay in ChatView

**Symptom:** A visible hard-edged translucent band appeared below the navigation bar in the chat view. The `ultraThinMaterial` rectangle created an abrupt visual cutoff where it ended.

**Root Cause:** A 40pt `Rectangle().fill(.ultraThinMaterial)` was overlaid at the top of the message list with a gradient mask. The material's blur effect created a hard bottom edge that the gradient mask couldn't fully smooth out. This approach conflicted with the iOS navigation bar's own built-in translucency.

**Fix (commit `01fd663`):**
- Removed the custom material overlay entirely — iOS NavigationBar handles the transition natively
- Replaced the `Divider` between messages and input bar with an upward shadow (`y: -3`) on the input bar itself
- Changed input bar background from `Color.white` to `Theme.surface` for consistency
- Added 16ms debounce to `scrollToBottom` to suppress SwiftUI runtime warning: `onChange(of: Int) action tried to update multiple times per frame`

**Files affected:** `ChatView.swift`

**Test points:**
- [ ] Scroll messages up/down — no visual artifact below navigation bar
- [ ] Input bar has soft shadow separation from message area
- [ ] Streaming messages scroll smoothly without console warnings
- [ ] Input bar background matches app theme

---

## Issue 3: Unhandled error state in chat sessions

**Symptom:** When a session failed (e.g., "Directory not allowed"), the error was displayed as a plain text message with a `⚠️` emoji prefix. The input bar remained active, allowing users to type and send messages to a broken session. Re-entering the chat view caused duplicate error messages to stack.

**Root Cause:**
- `appendError()` in `ChatViewModel` treated errors as regular assistant messages with an emoji prefix — no distinct visual treatment
- No `hasError` state existed to disable input after a fatal error
- The `ChatViewModel` was cached in `SessionViewModel.chatVMs`, so the `messages` array persisted across navigations. Each re-entry triggered another resume, producing another error append

**Fix (commit `e733ecb`):**
- Added `isError: Bool` flag to `ChatMessage` struct
- Added `hasError: Bool` state to `ChatViewModel`
- `appendError()` now: sets `hasError = true`, skips if already in error state (prevents duplicates), creates a separate error message instead of appending to streaming text
- `sendMessage()` guards on `!hasError`
- `ChatView` hides the input bar entirely when `viewModel.hasError` is true
- `MessageBubble` renders error messages as full-width orange warning cards with an icon, visually distinct from normal messages

**Files affected:** `ChatViewModel.swift`, `MessageBubble.swift`, `ChatView.swift`

**Test points:**
- [ ] Create session with disallowed directory — error card displays, no input bar
- [ ] Navigate back and re-enter — only one error message, not duplicated
- [ ] Normal sessions still accept input normally
- [ ] Error during streaming — streaming finalizes, error card appears separately
- [ ] Error card is full-width with orange background and warning icon
