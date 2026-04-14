import SwiftUI

/// Renders Markdown text with headings, styled code blocks, and inline formatting.
struct MarkdownContentView: View {
    let text: String

    /// Messages longer than this threshold get a "Show more" collapse.
    private static let collapseThreshold = 800
    @State private var isExpanded = false

    private var shouldCollapse: Bool {
        text.count > Self.collapseThreshold
    }

    private var displayText: String {
        if shouldCollapse && !isExpanded {
            return String(text.prefix(Self.collapseThreshold))
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                segmentView(segment)
            }

            if shouldCollapse {
                collapseToggle
            }
        }
    }

    // MARK: - Collapse Toggle

    private var collapseToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(.caption.bold())
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
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

    private var segments: [Segment] {
        parseSegments(displayText)
    }

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
        let attributed = (try? AttributedString(markdown: content, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ))) ?? AttributedString(content)

        return Text(attributed)
            .textSelection(.enabled)
            .foregroundStyle(Theme.textPrimary)
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
        .background(Color(hex: 0xF7F6F3))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
                .stroke(Theme.border.opacity(0.6), lineWidth: 0.5)
        )
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
        .background(Color(hex: 0xE8E7E3).opacity(0.5))
    }
}

// MARK: - Syntax Highlighting

private struct SyntaxHighlightedText: View {
    let code: String
    let language: String

    private static let kwColor = Color(hex: 0xCF222E)
    private static let strColor = Color(hex: 0x0A3069)
    private static let commentColor = Color(hex: 0x6E7781)
    private static let typeColor = Color(hex: 0x8250DF)
    private static let numColor = Color(hex: 0x0550AE)

    var body: some View {
        Text(highlighted)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
    }

    private var highlighted: AttributedString {
        var result = AttributedString()
        let lines = code.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            if idx > 0 { result.append(AttributedString("\n")) }
            result.append(highlightLine(line))
        }
        return result
    }

    private var kw: Set<String> {
        switch language.lowercased() {
        case "swift":
            return ["import", "func", "var", "let", "class", "struct", "enum", "protocol",
                    "if", "else", "guard", "return", "switch", "case", "default", "for",
                    "in", "while", "repeat", "break", "continue", "throw", "throws",
                    "try", "catch", "async", "await", "some", "any", "private", "public",
                    "internal", "fileprivate", "open", "static", "self", "Self", "nil",
                    "true", "false", "init", "deinit", "extension", "where", "typealias",
                    "mutating", "override", "final", "weak", "lazy", "super", "defer",
                    "do", "inout", "is", "as"]
        case "javascript", "js", "typescript", "ts", "jsx", "tsx":
            return ["const", "let", "var", "function", "return", "if", "else", "for",
                    "while", "do", "switch", "case", "default", "break", "continue",
                    "throw", "try", "catch", "finally", "new", "typeof", "instanceof",
                    "this", "class", "extends", "super", "import", "export", "from",
                    "async", "await", "of", "in", "true", "false", "null", "undefined",
                    "type", "interface", "enum", "readonly", "private", "public",
                    "protected", "static", "abstract", "declare"]
        case "python", "py":
            return ["def", "class", "return", "if", "elif", "else", "for", "while",
                    "break", "continue", "pass", "raise", "try", "except", "finally",
                    "with", "as", "import", "from", "yield", "lambda", "and", "or",
                    "not", "is", "in", "True", "False", "None", "self", "async", "await",
                    "global", "nonlocal", "del", "assert"]
        default:
            return ["if", "else", "for", "while", "return", "function", "class",
                    "var", "let", "const", "import", "export", "true", "false", "null",
                    "nil", "void", "new", "this", "self", "switch", "case", "default",
                    "break", "continue", "try", "catch", "throw"]
        }
    }

    private var types: Set<String> {
        switch language.lowercased() {
        case "swift":
            return ["String", "Int", "Double", "Float", "Bool", "Array", "Dictionary",
                    "Set", "Optional", "Result", "Error", "URL", "Data", "Date", "UUID",
                    "View", "Color", "Text", "Image", "Button", "VStack", "HStack",
                    "ZStack", "List", "ForEach", "NavigationStack", "ScrollView",
                    "Any", "AnyObject", "Void", "Never", "Codable", "Hashable",
                    "Equatable", "Identifiable", "CGFloat"]
        case "typescript", "ts", "tsx":
            return ["string", "number", "boolean", "object", "any", "unknown", "never",
                    "void", "undefined", "Array", "Map", "Set", "Promise", "Record",
                    "Partial", "Required", "Readonly"]
        default:
            return []
        }
    }

    private func highlightLine(_ line: String) -> AttributedString {
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

    private func scanString(_ line: String, from start: String.Index, quote: Character) -> String.Index {
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
