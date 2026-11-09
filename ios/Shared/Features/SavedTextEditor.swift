import SwiftUI

/// Edits a local draft; only Save changes the library item.
struct SavedTextEditor: View {
    let library: Library
    let item: LibraryItem
    private let original: String
    @State private var draft: String
    @State private var showsSaveError = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(library: Library, item: LibraryItem) {
        self.library = library
        self.item = item
        original = item.text ?? ""
        _draft = State(initialValue: item.text ?? "")
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .font(.body)
                .focused($focused)
                .padding()
                .accessibilityLabel("Text")
                .accessibilityIdentifier("SavedTextEditor")
                .navigationTitle("Edit Text")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(draft == original || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .keyboardShortcut(.defaultAction)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 560, minHeight: 320, idealHeight: 440)
        #endif
        .interactiveDismissDisabled(draft != original)
        .onAppear { focused = true }
        .onChange(of: library.contains(item)) { _, available in
            if !available { dismiss() }
        }
        .alert("Couldn't Save Text", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your changes are still in the editor. Please try saving again.")
        }
    }

    private func save() {
        guard library.contains(item) else { dismiss(); return }
        do {
            try library.updateText(draft, for: item)
            dismiss()
        } catch {
            showsSaveError = true
        }
    }
}
