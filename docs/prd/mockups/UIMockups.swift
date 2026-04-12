import SwiftUI

// MARK: - Theme

enum VibeTheme {
    static let background = Color(hex: 0x0D1117)
    static let surface = Color(hex: 0x161B22)
    static let surfaceElevated = Color(hex: 0x1C2128)
    static let border = Color(hex: 0x30363D)
    
    static let textPrimary = Color(hex: 0xE6EDF3)
    static let textSecondary = Color(hex: 0x8B949E)
    static let textMuted = Color(hex: 0x484F58)
    
    static let accent = Color(hex: 0x00FF41)
    static let accentDim = Color(hex: 0x00CC33)
    
    static let success = Color(hex: 0x3FB950)
    static let warning = Color(hex: 0xD29922)
    static let error = Color(hex: 0xF85149)
    static let info = Color(hex: 0x58A6FF)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Chat Mockup

struct MockChatView: View {
    @State private var inputText = ""
    @State private var cursorVisible = true
    
    let messages: [(role: String, content: String, toolName: String?, toolExpanded: Bool)] = [
        (role: "user", content: "Fix the login bug in auth.ts", toolName: nil, toolExpanded: false),
        (role: "assistant", content: "I'll look at the authentication module. Let me read the file first.", toolName: nil, toolExpanded: false),
        (role: "tool", content: "src/auth.ts", toolName: "Read file", toolExpanded: true),
        (role: "assistant", content: "Found the issue. The token validation is missing the expiry check. Let me fix that...", toolName: nil, toolExpanded: false),
        (role: "tool", content: "src/auth.ts — lines 42-58", toolName: "Edit file", toolExpanded: false),
        (role: "streaming", content: "Done! The fix adds proper JWT expiry validation. The token was being accepted even after", toolName: nil, toolExpanded: false),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Image(systemName: "chevron.left")
                    .foregroundStyle(VibeTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("my-app")
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(VibeTheme.textPrimary)
                    Text("claude · sonnet-4")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(VibeTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "stop.circle")
                    .foregroundStyle(VibeTheme.error)
                    .font(.title3)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(VibeTheme.surface.opacity(0.95))
            
            Divider().overlay(VibeTheme.border)
            
            // Messages
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, msg in
                        if msg.role == "tool" {
                            // Tool card
                            toolCard(name: msg.toolName ?? "Tool", content: msg.content, expanded: msg.toolExpanded)
                        } else if msg.role == "user" {
                            // User bubble
                            userBubble(msg.content)
                        } else if msg.role == "streaming" {
                            // Streaming bubble
                            streamingBubble(msg.content)
                        } else {
                            // Assistant bubble
                            assistantBubble(msg.content)
                        }
                    }
                }
                .padding()
            }
            .background(VibeTheme.background)
            
            Divider().overlay(VibeTheme.border)
            
            // Input bar
            HStack(spacing: 10) {
                Text(">")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(VibeTheme.accent)
                
                TextField("Message…", text: $inputText)
                    .font(.system(.body))
                    .foregroundStyle(VibeTheme.textPrimary)
                
                Button {
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.isEmpty ? VibeTheme.textMuted : VibeTheme.accent)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(VibeTheme.surface)
        }
        .background(VibeTheme.background)
        .preferredColorScheme(.dark)
    }
    
    func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(.body))
                .foregroundStyle(VibeTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(VibeTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(VibeTheme.accent, lineWidth: 1)
                )
        }
    }
    
    func assistantBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(VibeTheme.accent)
                .frame(width: 3)
                .padding(.vertical, 4)
            
            Text(text)
                .font(.system(.body))
                .foregroundStyle(VibeTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            
            Spacer(minLength: 40)
        }
        .background(VibeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    func streamingBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(VibeTheme.accent)
                .frame(width: 3)
                .padding(.vertical, 4)
            
            HStack(spacing: 0) {
                Text(text)
                    .font(.system(.body))
                    .foregroundStyle(VibeTheme.textPrimary)
                Text("█")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(VibeTheme.accent)
                    .opacity(cursorVisible ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            cursorVisible.toggle()
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Spacer(minLength: 40)
        }
        .background(VibeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    func toolCard(name: String, content: String, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("$")
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(VibeTheme.accent)
                Text(name)
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(VibeTheme.textPrimary)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(VibeTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            if expanded {
                Divider().overlay(VibeTheme.border)
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(VibeTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .background(VibeTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(VibeTheme.border, lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
    }
}

// MARK: - Session List Mockup

struct MockSessionListView: View {
    let sessions = [
        ("my-app", "~/projects/my-app", "claude", true),
        ("isotopes", "~/projects/isotopes", "claude", false),
        ("vibe-anywhere", "~/projects/vibe-anywhere", "codex", false),
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Text("Sessions")
                    .font(.system(.title2, design: .monospaced).bold())
                    .foregroundStyle(VibeTheme.textPrimary)
                Spacer()
                Button {
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(VibeTheme.accent)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider().overlay(VibeTheme.border)
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { _, session in
                        sessionRow(name: session.0, path: session.1, agent: session.2, active: session.3)
                    }
                }
                .padding()
            }
            .background(VibeTheme.background)
        }
        .background(VibeTheme.background)
        .preferredColorScheme(.dark)
    }
    
    func sessionRow(name: String, path: String, agent: String, active: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(active ? VibeTheme.accent : VibeTheme.textSecondary)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(name)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundStyle(VibeTheme.textPrimary)
                    if active {
                        Circle()
                            .fill(VibeTheme.success)
                            .frame(width: 6, height: 6)
                            .shadow(color: VibeTheme.success.opacity(0.5), radius: 3)
                    }
                }
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(VibeTheme.textSecondary)
            }
            
            Spacer()
            
            Text(agent)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(VibeTheme.accent.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(VibeTheme.accent.opacity(0.1))
                .clipShape(Capsule())
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(VibeTheme.textMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(VibeTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(VibeTheme.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Settings Mockup

struct MockSettingsView: View {
    @State private var host = "192.168.1.100"
    @State private var port = "7842"
    @State private var token = "a1b2c3d4e5f6..."
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(.title2, design: .monospaced).bold())
                    .foregroundStyle(VibeTheme.textPrimary)
                Spacer()
                Button("Done") {}
                    .foregroundStyle(VibeTheme.accent)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider().overlay(VibeTheme.border)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Connection section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONNECTION")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(VibeTheme.textSecondary)
                            .padding(.horizontal, 4)
                        
                        VStack(spacing: 0) {
                            settingsField("Host", value: host, color: VibeTheme.textPrimary)
                            Divider().overlay(VibeTheme.border)
                            settingsField("Port", value: port, color: VibeTheme.textPrimary)
                            Divider().overlay(VibeTheme.border)
                            settingsField("Token", value: token, color: VibeTheme.accent)
                        }
                        .background(VibeTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(VibeTheme.border, lineWidth: 0.5)
                        )
                    }
                    
                    // Status section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STATUS")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(VibeTheme.textSecondary)
                            .padding(.horizontal, 4)
                        
                        HStack {
                            Circle()
                                .fill(VibeTheme.success)
                                .frame(width: 8, height: 8)
                                .shadow(color: VibeTheme.success.opacity(0.6), radius: 4)
                            Text("Connected")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(VibeTheme.success)
                            Spacer()
                            Text("v0.2.0")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(VibeTheme.textMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(VibeTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(VibeTheme.border, lineWidth: 0.5)
                        )
                    }
                    
                    // Connect button
                    Button {
                    } label: {
                        Text("Connect")
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundStyle(VibeTheme.background)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(VibeTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding()
            }
            .background(VibeTheme.background)
        }
        .background(VibeTheme.background)
        .preferredColorScheme(.dark)
    }
    
    func settingsField(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(.body))
                .foregroundStyle(VibeTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Previews

#Preview("Chat View") {
    MockChatView()
}

#Preview("Session List") {
    MockSessionListView()
}

#Preview("Settings") {
    MockSettingsView()
}
