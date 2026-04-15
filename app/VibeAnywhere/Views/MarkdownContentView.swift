import SwiftUI

/// Renders Markdown text with headings, styled code blocks, and inline formatting.
struct MarkdownContentView: View {
    let text: String

    /// Messages with more than this many lines get a "Show more" collapse.
    private static let collapseLineLimit = 5
    private static let collapseCharLimit = 300
    @State private var isExpanded = false
    @State private var cachedSegments: [Segment] = []
    @State private var cachedDisplayText: String = ""

    private var shouldCollapse: Bool {
        text.count > Self.collapseCharLimit
            || text.components(separatedBy: "\n").count > Self.collapseLineLimit
    }

    private var displayText: String {
        if shouldCollapse && !isExpanded {
            let byLines = text.components(separatedBy: "\n")
                .prefix(Self.collapseLineLimit)
                .joined(separator: "\n")
            return String(byLines.prefix(Self.collapseCharLimit))
        }
        return text
    }

    var body: some View {
        let collapsed = shouldCollapse

        VStack(alignment: .leading, spacing: 10) {
            if collapsed {
                collapseToggle
            }

            ForEach(Array(cachedSegments.enumerated()), id: \.offset) { _, segment in
                segmentView(segment)
            }
        }
        .mask {
            if collapsed && !isExpanded {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 32)
                }
            } else {
                Color.black
            }
        }
        .clipped()
        .task(id: text) { updateSegments() }
        .onChange(of: isExpanded) { _, _ in updateSegments() }
    }

    private func updateSegments() {
        let dt = displayText
        guard dt != cachedDisplayText else { return }
        cachedDisplayText = dt
        cachedSegments = parseSegments(dt)
    }

    // MARK: - Collapse Toggle

    private var collapseToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                Text(isExpanded ? "Collapse" : "Expand")
                    .font(.caption.bold())
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: - Segment Types

    private enum Segment {
        case text(String)
        case heading(level: Int, text: String)
        case codeBlock(language: String, code: String)
    }

    // MARK: - Parsing

    private func parseSegments(_ input: String) -> [Segment] {
        var result: [Segment] = []
        let lines = input.components(separatedBy: "\n")
        var currentText: [String] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var codeLang = ""

        for line in lines {
            if !inCodeBlock, line.hasPrefix("```") {
                flushText(&currentText, into: &result)
                inCodeBlock = true
                codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLines = []
            } else if inCodeBlock, line.hasPrefix("```") {
                result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
                inCodeBlock = false
                codeLang = ""
                codeLines = []
            } else if inCodeBlock {
                codeLines.append(line)
            } else if let heading = parseHeading(line) {
                flushText(&currentText, into: &result)
                result.append(heading)
            } else {
                currentText.append(line)
            }
        }

        if inCodeBlock {
            result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
        } else {
            flushText(&currentText, into: &result)
        }

        return result
    }

    private func parseHeading(_ line: String) -> Segment? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, trimmed.count > level else { return nil }
        let next = trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)]
        guard next == " " else { return nil }
        let headingText = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !headingText.isEmpty else { return nil }
        return .heading(level: level, text: headingText)
    }

    private func flushText(_ lines: inout [String], into result: inout [Segment]) {
        let joined = lines.joined(separator: "\n")
        let paragraphs = joined.components(separatedBy: "\n\n")
        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.append(.text(trimmed))
            }
        }
        lines = []
    }

    // MARK: - Rendering

    @ViewBuilder
    private func segmentView(_ segment: Segment) -> some View {
        switch segment {
        case .text(let content):
            inlineMarkdownView(content)
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)
        }
    }

    private func headingView(level: Int, text: String) -> some View {
        let font: Font = switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.bold()
        }

        return Text(text)
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, level <= 2 ? 6 : 2)
    }

    private func inlineMarkdownView(_ content: String) -> some View {
        CachedMarkdownText(content: content)
    }

    // MARK: - Code Block

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            codeBlockHeader(language: language, code: code)

            ScrollView(.horizontal, showsIndicators: false) {
                if !language.isEmpty {
                    SyntaxHighlightedText(code: code, language: language)
                        .padding(12)
                } else {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: Theme.cardShadow, radius: 4, y: 2)
    }

    private func codeBlockHeader(language: String, code: String) -> some View {
        HStack {
            if !language.isEmpty {
                Text(language)
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            CopyButton(text: code)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Cached Markdown Text

private struct CachedMarkdownText: View {
    let content: String
    @State private var attributed: AttributedString?

    var body: some View {
        Text(attributed ?? AttributedString(content))
            .textSelection(.enabled)
            .foregroundStyle(Theme.textPrimary)
            .task {
                parse()
            }
            .onChange(of: content) { _, _ in
                attributed = nil
                parse()
            }
    }

    private func parse() {
        let src = content
        guard attributed == nil else { return }
        Task.detached(priority: .userInitiated) {
            let result = (try? AttributedString(markdown: src, options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            ))) ?? AttributedString(src)
            await MainActor.run {
                guard content == src else { return }
                attributed = result
            }
        }
    }
}

// MARK: - Syntax Highlighting

private struct SyntaxHighlightedText: View {
    let code: String
    let language: String
    @State private var cached: AttributedString?

    private nonisolated(unsafe) static let kwColor = Color(hex: 0xCF222E)
    private nonisolated(unsafe) static let strColor = Color(hex: 0x0A3069)
    private nonisolated(unsafe) static let commentColor = Color(hex: 0x6E7781)
    private nonisolated(unsafe) static let typeColor = Color(hex: 0x8250DF)
    private nonisolated(unsafe) static let numColor = Color(hex: 0x0550AE)

    // Pre-built keyword/type sets (static, allocated once)
    private nonisolated(unsafe) static let kwSets: [String: Set<String>] = [
        "swift": ["import", "func", "var", "let", "class", "struct", "enum", "protocol",
                  "if", "else", "guard", "return", "switch", "case", "default", "for",
                  "in", "while", "repeat", "break", "continue", "throw", "throws",
                  "try", "catch", "async", "await", "some", "any", "private", "public",
                  "internal", "fileprivate", "open", "static", "self", "Self", "nil",
                  "true", "false", "init", "deinit", "extension", "where", "typealias",
                  "mutating", "override", "final", "weak", "lazy", "super", "defer",
                  "do", "inout", "is", "as"],
        "javascript": ["const", "let", "var", "function", "return", "if", "else", "for",
                       "while", "do", "switch", "case", "default", "break", "continue",
                       "throw", "try", "catch", "finally", "new", "typeof", "instanceof",
                       "this", "class", "extends", "super", "import", "export", "from",
                       "async", "await", "of", "in", "true", "false", "null", "undefined",
                       "type", "interface", "enum", "readonly", "private", "public",
                       "protected", "static", "abstract", "declare"],
        "python": ["def", "class", "return", "if", "elif", "else", "for", "while",
                   "break", "continue", "pass", "raise", "try", "except", "finally",
                   "with", "as", "import", "from", "yield", "lambda", "and", "or",
                   "not", "is", "in", "True", "False", "None", "self", "async", "await",
                   "global", "nonlocal", "del", "assert"],
    ]
    private nonisolated(unsafe) static let defaultKw: Set<String> = [
        "if", "else", "for", "while", "return", "function", "class",
        "var", "let", "const", "import", "export", "true", "false", "null",
        "nil", "void", "new", "this", "self", "switch", "case", "default",
        "break", "continue", "try", "catch", "throw"
    ]
    private nonisolated(unsafe) static let typeSets: [String: Set<String>] = [
        "swift": ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary",
                  "Set", "Optional", "Result", "Error", "URL", "Data", "Date", "UUID",
                  "View", "Color", "Text", "Image", "Button", "VStack", "HStack",
                  "ZStack", "List", "ForEach", "NavigationStack", "ScrollView",
                  "Any", "AnyObject", "Void", "Never", "Codable", "Hashable",
                  "Equatable", "Identifiable", "CGFloat"],
        "typescript": ["string", "number", "boolean", "object", "any", "unknown", "never",
                       "void", "undefined", "Array", "Map", "Set", "Promise", "Record",
                       "Partial", "Required", "Readonly"],
    ]

    var body: some View {
        Text(cached ?? AttributedString(code))
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .task {
                highlight()
            }
            .onChange(of: code) { _, _ in
                cached = nil
                highlight()
            }
    }

    private func highlight() {
        let src = code
        let lang = language
        guard cached == nil else { return }
        Task.detached(priority: .userInitiated) {
            let result = Self.performHighlight(code: src, language: lang)
            await MainActor.run {
                guard code == src else { return }
                cached = result
            }
        }
    }

    private nonisolated static func performHighlight(code: String, language: String) -> AttributedString {
        let lang = language.lowercased()
        let langKey: String
        switch lang {
        case "swift": langKey = "swift"
        case "javascript", "js", "jsx": langKey = "javascript"
        case "typescript", "ts", "tsx": langKey = "javascript"
        case "python", "py": langKey = "python"
        default: langKey = ""
        }
        let keywords = kwSets[langKey] ?? defaultKw
        let typeSet = typeSets[langKey] ?? []

        var result = AttributedString()
        let lines = code.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            if idx > 0 { result.append(AttributedString("\n")) }
            result.append(highlightLine(line, kw: keywords, types: typeSet))
        }
        return result
    }

    private nonisolated static func highlightLine(_ line: String, kw: Set<String>, types: Set<String>) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
            var a = AttributedString(line)
            a.foregroundColor = Self.commentColor
            return a
        }

        var result = AttributedString()
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]

            // String literal
            if ch == "\"" || ch == "'" || ch == "`" {
                let end = scanString(line, from: i, quote: ch)
                var part = AttributedString(String(line[i..<end]))
                part.foregroundColor = Self.strColor
                result.append(part)
                i = end
                continue
            }

            // Inline comment
            if ch == "/" && line.index(after: i) < line.endIndex && line[line.index(after: i)] == "/" {
                var part = AttributedString(String(line[i...]))
                part.foregroundColor = Self.commentColor
                result.append(part)
                return result
            }

            // Number
            if ch.isNumber {
                var end = line.index(after: i)
                while end < line.endIndex && (line[end].isNumber || line[end] == "." || line[end] == "x") {
                    end = line.index(after: end)
                }
                var part = AttributedString(String(line[i..<end]))
                part.foregroundColor = Self.numColor
                result.append(part)
                i = end
                continue
            }

            // Word
            if ch.isLetter || ch == "_" || ch == "@" {
                var end = line.index(after: i)
                while end < line.endIndex && (line[end].isLetter || line[end].isNumber || line[end] == "_") {
                    end = line.index(after: end)
                }
                let word = String(line[i..<end])
                var part = AttributedString(word)
                if kw.contains(word) {
                    part.foregroundColor = Self.kwColor
                } else if types.contains(word) {
                    part.foregroundColor = Self.typeColor
                } else {
                    part.foregroundColor = Theme.textPrimary
                }
                result.append(part)
                i = end
                continue
            }

            var part = AttributedString(String(ch))
            part.foregroundColor = Theme.textPrimary
            result.append(part)
            i = line.index(after: i)
        }

        return result
    }

    private nonisolated static func scanString(_ line: String, from start: String.Index, quote: Character) -> String.Index {
        var i = line.index(after: start)
        while i < line.endIndex {
            if line[i] == "\\" && line.index(after: i) < line.endIndex {
                i = line.index(i, offsetBy: 2)
                continue
            }
            if line[i] == quote {
                return line.index(after: i)
            }
            i = line.index(after: i)
        }
        return i
    }
}

// MARK: - Copy Button

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(copied ? Theme.accent : Theme.textTertiary)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: copied)
    }
}
