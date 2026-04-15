# CPU 死循环审计 — 最近 25 个 Commit

审计日期：2026-04-16
分支：`debug/cpu-recursion-logging`
审计范围：排查可能导致无限递归 / 100% CPU 占用的 commit。

---

## 总结

原始 CPU 死循环的根因已在 `bb75cae` 中定位并修复：
StreamingBubble 位于 `ForEach(messages)` 内部的 `LazyVStack` 中，每个 streaming
chunk 都会触发 SwiftUI 观察 -> ForEach 重新 diff -> 重入布局失效 -> 100% CPU。

经过修复系列（#129–#133）后，残余风险较低，主要集中在
`CachedMarkdownText.parse()` 的异步 `@State` 回写模式上。

---

## 按项目路径分类的 Commit

### `app/VibeAnywhere/Views/` — UI 层

| Commit | PR | 说明 | CPU 风险 |
|--------|----|------|----------|
| `d26565f` | #133 | 简化 ChatView 滚动处理 | 低 |
| `a783282` | #132 | 后台 Markdown/语法高亮解析 | 中低 |
| `bb75cae` | #131 | 将 StreamingBubble 移到 ScrollView 外部 | **修复了原始 bug** |
| `aeb2008` | #100 | 在 view disappear 时取消滚动 debounce | 低 |
| `7ee6471` | #119 | 端口格式化、阴影一致性 | 无 |
| `b53f34a` | #114 | Settings/NewSession 卡片添加阴影 | 无 |
| `735986a` | #113 | Liquid Glass 视觉打磨 | 无 |
| `c0a73a3` | #107 | 替换不透明表面为半透明材质 | 无 |
| `644d4ab` | #106 | 柔化错误卡片边框 | 无 |
| `78460cc` | #105 | 移除不支持的 Gemini/Codex 选项 | 无 |
| `077bbf8` | #99 | UI 精细化、错误样式 | 无 |
| `2a0c106` | #91 | NewSession/SessionSettings 主题 | 无 |
| `8365f2b` | #89 | 连接超时反馈 | 无 |
| `1b28b58` | #86 | 工具栏图标 + 会话卡片 | 无 |
| `027e8fb` | #83 | 空状态、强制浅色模式、Settings 主题 | 无 |

### `app/VibeAnywhere/ViewModels/` — ViewModel 层

| Commit | PR | 说明 | CPU 风险 |
|--------|----|------|----------|
| `ab8a378` | #130 | 从 ChatViewModel 提取 StreamingState | 安全 — 隔离了观察链 |
| `02a3496` | #129 | 从 ChatViewModel 提取 MessageStore | 安全 — 纯重构 |

### `app/VibeAnywhere/Services/` — 服务层

| Commit | PR | 说明 | CPU 风险 |
|--------|----|------|----------|
| `a79c853` | #108 | 修复重连计数器卡在 (1/10) | 无 |

### `app/VibeAnywhere/` — Models、Tests、Assets

| Commit | PR | 说明 | CPU 风险 |
|--------|----|------|----------|
| `3417842` | #98 | 更新 replay 参数的测试模式 | 无 |
| `7f7bd46` | #121 | 添加 App 图标 | 无 |

### 跨层（Views + ViewModels）

| Commit | 说明 | CPU 风险 |
|--------|------|----------|
| `0998ae9` | 添加 CPU 递归诊断日志 | 无（诊断用） |
| `8255d59` (#94) | 会话恢复 | 无 |
| `1cd9692` | UX 优化和 bug 修复 | 低 |
| `bd71172` | "bad tried"（失败尝试） | 未知（重构前） |

### `daemon/` — Node.js 后端

| Commit | 说明 | CPU 风险 |
|--------|------|----------|
| `f807a4b` | 临时改动（acp-manager, config, sessions） | 无（服务端） |
| `78460cc` (#105) | 移除 Gemini/Codex（acp-manager） | 无 |
| `8255d59` (#94) | 会话恢复（acp-manager, sessions, types） | 无 |
| `1cd9692` | UX 优化（sessions, types） | 无 |
| `bd71172` | 失败尝试（sessions） | 无 |

### `docs/` — 文档

| Commit | 文件 |
|--------|------|
| `0998ae9` | chat-view-refactor.md |
| `077bbf8` | ui-refinement-rca.md |

---

## 详细风险分析

### 1. `bb75cae` — StreamingBubble 修复（已修复原始 bug）

**原始根因：** StreamingBubble 位于 `ForEach(messages)` 内部。每个 streaming chunk
都会变更 messages 数组 -> ForEach 重新 diff -> 重入布局失效 -> 100% CPU 死循环。

**修复方案：** 将 StreamingBubble 移到 ScrollView 外部，放入 ZStack overlay。
ForEach 现在只遍历已完成的消息（streaming 期间保持稳定）。Streaming chunk
只会导致一个视图（StreamingBubble）重绘。

### 2. `a783282` — 后台 Markdown 解析（中低风险）

`CachedMarkdownText.parse()` 使用 `Task.detached` 在后台线程解析 markdown，
然后将结果回写到 `@State attributed`：

```swift
Task.detached(priority: .userInitiated) {
    let result = ...
    await MainActor.run {
        guard content == src else { return }  // 过期检查
        attributed = result  // 写入 @State -> 触发 body 重新求值
    }
}
```

**潜在循环路径：**
1. `attributed = result` 写入 `@State` -> SwiftUI 标记 view 为 dirty
2. SwiftUI 重新求值 `CachedMarkdownText.body`
3. 如果父视图以相同 content 重建了该视图，`onChange(of: content)` 再次触发
   -> `parse()` -> 回到步骤 1

**已有的缓解措施：**
- 过期检查（`guard content == src`）防止过期写入
- `onChange(of: content)` 仅在 content 实际变化时触发（String 值相等比较）
- 实际上，已完成的消息内容是稳定的

**可能出问题的场景：** 如果父视图以相同 content 但新的 view identity 重建
`CachedMarkdownText`（例如 ForEach ID 发生变化），`onAppear` 会再次触发
-> `parse()` -> `@State` 写入 -> body 重新求值。这是有界的（多一次求值），
但值得监控。

### 3. `d26565f` — 滚动简化（低风险）

移除了 debounce 包装。`scrollToBottom()` 现在直接从
`onChange(of: messages.count)` 和 `onChange(of: streaming.isActive)` 触发。

无循环风险：滚动操作不会触发导致重入滚动处理的观察变更。

### 4. `ab8a378` — StreamingState 提取（安全）

ChatViewModel 上的 `@ObservationIgnored let streaming = StreamingState()` 意味着
对 `streaming.text` 的 chunk 更新不会通过 ChatViewModel 的观察链传播。
只有 `StreamingBubble`（直接持有 `StreamingState`）会在 chunk 时重绘。

**注意：** `ChatView.body` 直接读取了 `viewModel.streaming.isActive`（第 100、110
行）。这会创建对 `StreamingState.isActive` 的直接观察，但 `isActive` 仅在
`begin()` 和 `finalize()` 时变化（每个 turn 各一次），不会在每个 chunk 时变化。
不会造成高频循环。

### 5. `02a3496` — MessageStore 提取（安全）

纯重构。将消息数组和 replay 缓冲区从 ChatViewModel 移到独立的 `@Observable`
类中。逻辑不变。

---

## 待持续关注的项目

1. **`CachedMarkdownText` 异步解析回写** — 通过 `0998ae9` 中添加的诊断日志监控
   body 求值次数。如果 `bodyEvalCount > 50` 被触发，说明解析循环正在重入。

2. **`MarkdownContentView.updateSegments()`** — 写入 `@State cachedSegments` 和
   `@State cachedDisplayText`。受 `guard dt != cachedDisplayText` 保护，但依赖
   `displayText` 计算属性的确定性。

3. **诊断日志的性能开销** — 当前在热路径上的诊断日志（`cpuLog` 调用，如
   StreamingState.appendText、CachedMarkdownText.body）会带来非平凡的性能开销。
   发布前应移除。
