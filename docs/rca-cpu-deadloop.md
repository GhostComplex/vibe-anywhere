# RCA: SwiftUI "Modifying state during view update" 导致 CPU 100%

**日期**：2026-04-16
**严重度**：P1 — 用户可感知的 UI 冻结 / 设备发热
**影响范围**：所有恢复历史会话（session resume）的场景
**修复分支**：`debug/cpu-recursion-logging`

---

## 1. 问题现象

恢复一个有多条历史消息的会话时，app CPU 飙升至 100%，UI 卡顿，设备发热。
Xcode 控制台持续输出大量 `Modifying state during view update, this will cause
undefined behavior.` 警告。

---

## 2. 根因（Root Cause）

**不是单一 bug，而是三个问题叠加：**

### 2.1 诊断代码自身成为问题源（主因）

`0998ae9` 添加的 CPU 递归诊断日志在**每个 view 的 `body` 中同步修改 `@State bodyEvalCount`**：

```swift
var body: some View {
    let _ = {
        bodyEvalCount += 1  // ← 在 body 求值中写 @State！
        cpuLog.warning("...")
    }()
    ...
}
```

SwiftUI 规定 `body` 求值期间不允许修改状态。这里的 `bodyEvalCount += 1` 直接违反了这个约束，导致 SwiftUI 将 view 标记为 dirty，触发额外的 body 求值，形成**雪崩效应**。

这个模式存在于 4 个 view 中（ChatView、MarkdownContentView、CachedMarkdownText、
SyntaxHighlightedText、MessageBubble、StreamingBubble），每个 view 的每次 body 求值都会触发一次。当 replay 一次性加载 8-9 条消息时，数十个 view 同时做这件事，级联放大。

**讽刺之处**：加诊断代码是为了找死循环，但诊断代码本身创造了最大的 CPU 热点。

### 2.2 MarkdownContentView.updateSegments() 在 view update 中同步写 @State

```swift
.onAppear { updateSegments() }  // onAppear 可能在布局 pass 中被调用

func updateSegments() {
    cachedDisplayText = dt      // ← 写 @State
    cachedSegments = parseSegments(dt)  // ← 写 @State
}
```

`onAppear` 在 SwiftUI 首次布局时可能同步执行（而非延迟到布局完成后），此时写 `@State` 就会产生 "Modifying state during view update" 警告，并导致 view 被标记为 dirty 进而重新求值。

### 2.3 CachedMarkdownText.parse() 在 LazyVStack 滚动时重复触发

```swift
.onAppear { parse() }  // LazyVStack 回收 view 后再滚回来，又触发 onAppear
```

`parse()` 通过 `Task.detached` 异步解析 markdown，完成后回写 `@State attributed`。
LazyVStack 回收 view identity 后重新显示时，`onAppear` 再次触发 → 又解析一次 →
又写一次 `@State` → 又触发 body 重算。对于同一条不变的消息，不断重复解析。

### 触发链时序

```
endReplay() 写入 8 条消息到 items 数组
  → SwiftUI 开始布局
    → ChatView.body 求值
      → bodyEvalCount += 1          ← "Modifying state during view update"
      → ForEach 遍历 8 条消息
        → 每条 MessageBubble.body
          → bodyEvalCount += 1      ← "Modifying state during view update"
          → MarkdownContentView.body
            → bodyEvalCount += 1    ← "Modifying state during view update"
            → onAppear → updateSegments()
              → cachedSegments = ...  ← "Modifying state during view update"
              → CachedMarkdownText.body
                → bodyEvalCount += 1  ← "Modifying state during view update"
                → onAppear → parse()
                  → Task.detached → attributed = result  ← 触发 body 重算
    → SwiftUI 发现大量 dirty views → 重新求值 → 循环
```

8 条消息 × 每条消息 4-6 个嵌套 view × 每个 view 至少 1 次 @State 写入 = **40-50 次 "Modifying state during view update"**，产生级联重算。

---

## 3. 为什么搞了一下午没搞好

| 时间投入 | 做了什么 | 为什么没效果 |
|----------|----------|-------------|
| 第一阶段 | 识别出 streaming chunk 导致 ForEach re-diff 的死循环（`bb75cae` 修复） | 这个修复是正确的，但不是唯一的问题 |
| 第二阶段 | 提取 StreamingState、MessageStore 隔离观察链 (#129 #130) | 正确的架构改进，但 replay 路径的问题被掩盖了 |
| 第三阶段 | 后台 markdown 解析、简化滚动 (#132 #133) | 改善了 streaming 路径，但 replay 路径仍有问题 |
| 第四阶段 | 加诊断日志 (`0998ae9`) 试图定位残余问题 | **诊断代码自身成为新的问题源** |

**核心误区：**

1. **只关注了 streaming 路径，忽略了 replay 路径**。原始死循环（ForEach + streaming chunk）确实修好了，但 replay 一次性灌入大量消息也会触发类似的级联重算，只是机制不同。

2. **诊断代码引入了新问题**。`bodyEvalCount += 1` 这个看似无害的计数器，在 body 中作为 `@State` 修改，恰好触发了 SwiftUI 最讨厌的反模式。在诊断日志存在的情况下，即使原始问题已修复，CPU 仍然飙高——于是误认为修复没有生效。

3. **没有先移除诊断代码再观察**。加了日志后看到问题仍在，就继续在其他方向上投入时间，而没有考虑"诊断代码本身是否有问题"。

---

## 4. 修复方案

### 4.1 移除所有诊断代码
删除 4 个文件中的 `cpuLog`、`bodyEvalCount`、body 中的 closure 日志。

### 4.2 `MarkdownContentView`：`.onAppear` → `.task(id:)`
```swift
// Before
.onAppear { updateSegments() }
.onChange(of: text) { _, _ in updateSegments() }

// After
.task(id: text) { updateSegments() }
```
`.task` 保证在布局完成后异步执行，不会在 view update 中同步写 @State。

### 4.3 `CachedMarkdownText`：防止重复解析
```swift
func parse() {
    guard attributed == nil else { return }  // 已有缓存，跳过
    ...
}
```
`onChange(of: content)` 先 `attributed = nil` 再 `parse()`。

### 4.4 `SyntaxHighlightedText`：同上处理。

---

## 5. 经验教训

1. **诊断代码不应有副作用**。在 SwiftUI body 中，任何 `@State` 修改都是副作用。
   如果需要计数 body 求值次数，用 `print()` 而不是 `@State` 计数器。

2. **SwiftUI 的 `onAppear` 不保证在布局完成后执行**。如果需要在 appear 时写 @State，
   用 `.task {}` 替代 `.onAppear {}`。

3. **修复性能问题时，先移除诊断代码再观察效果**。否则无法区分"原始问题"和"诊断引入的问题"。

4. **Replay 和 streaming 是两条不同的热路径**，需要分别测试。一条修好不代表另一条没问题。

---

## 6. 验证

- [ ] 恢复有多条历史的 session，控制台无 "Modifying state during view update" 警告
- [ ] CPU 不飙高
- [ ] Streaming 正常显示和 finalize
- [ ] 展开/折叠长消息正常
- [ ] LazyVStack 滚动时不重复解析已缓存的 markdown
