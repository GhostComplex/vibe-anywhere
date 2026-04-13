import SwiftUI

/// Renders Markdown text with styled code blocks and inline formatting.
/// Uses SwiftUI's built-in AttributedString for inline markdown (bold, italic, code, links)
/// and custom parsing for fenced code blocks.
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
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                segmentView(segment)
            }

            if shouldCollapse {
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
        }
    }

    // MARK: - Segment Types

    private enum Segment {
        case text(String)
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
                // Flush accumulated text
                let joined = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    result.append(.text(joined))
                }
                currentText = []

                // Start code block
                inCodeBlock = true
                codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLines = []
            } else if inCodeBlock, line.hasPrefix("```") {
                // End code block
                result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
                inCodeBlock = false
                codeLang = ""
                codeLines = []
            } else if inCodeBlock {
                codeLines.append(line)
            } else {
                currentText.append(line)
            }
        }

        // Flush remaining
        if inCodeBlock {
            // Unclosed code block — treat as code anyway
            result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
        } else {
            let joined = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                result.append(.text(joined))
            }
        }

        return result
    }

    // MARK: - Rendering

    @ViewBuilder
    private func segmentView(_ segment: Segment) -> some View {
        switch segment {
        case .text(let content):
            inlineMarkdownView(content)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)
        }
    }

    private func inlineMarkdownView(_ content: String) -> some View {
        let attributed = (try? AttributedString(markdown: content, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ))) ?? AttributedString(content)

        return Text(attributed)
            .textSelection(.enabled)
            .foregroundStyle(Theme.textPrimary)
    }

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language label + copy button
            if !language.isEmpty {
                HStack {
                    Text(language)
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    CopyButton(text: code)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: 0xE8E7E3).opacity(0.5))
            } else {
                HStack {
                    Spacer()
                    CopyButton(text: code)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: 0xE8E7E3).opacity(0.5))
            }

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(hex: 0xF7F6F3))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .stroke(Theme.border, lineWidth: 1)
        )
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
