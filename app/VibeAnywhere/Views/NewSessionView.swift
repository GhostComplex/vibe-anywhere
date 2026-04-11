import SwiftUI

struct NewSessionView: View {
    let viewModel: SessionViewModel
    var onDismiss: () -> Void

    @State private var path = ""
    @State private var favorites: [String] = []

    private static let favoritesKey = "savedDirectories"

    var body: some View {
        NavigationStack {
            Form {
                Section("Project Directory") {
                    TextField("~/projects/my-app", text: $path)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                }

                if !favorites.isEmpty {
                    Section("Recent") {
                        ForEach(favorites, id: \.self) { dir in
                            Button {
                                path = dir
                            } label: {
                                Label {
                                    Text(dir)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "folder")
                                }
                            }
                        }
                        .onDelete { indexSet in
                            favorites.remove(atOffsets: indexSet)
                            saveFavorites()
                        }
                    }
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSession()
                    }
                    .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                loadFavorites()
            }
        }
    }

    private func createSession() {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Save to favorites
        if !favorites.contains(trimmed) {
            favorites.insert(trimmed, at: 0)
            if favorites.count > 10 { favorites = Array(favorites.prefix(10)) }
            saveFavorites()
        }

        viewModel.createSession(cwd: trimmed)
        onDismiss()
    }

    private func loadFavorites() {
        favorites = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
    }

    private func saveFavorites() {
        UserDefaults.standard.set(favorites, forKey: Self.favoritesKey)
    }
}
