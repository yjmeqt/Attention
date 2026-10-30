import SwiftUI

/// Adds or removes manual tags on one or more items.
struct TagEditor: View {
    let library: Library
    let items: [LibraryItem]
    @State private var newTag = ""
    @FocusState private var fieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New tag", text: $newTag)
                            .focused($fieldFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        Button("Add", action: add)
                            .disabled(Library.normalizedTag(newTag).isEmpty)
                    }
                }
                let tags = library.allTags
                if !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags, id: \.self) { tag in
                            let state = state(of: tag)
                            Button {
                                if state == .all { library.removeTag(tag, from: items) } else { library.addTag(tag, to: items) }
                            } label: {
                                HStack {
                                    Label("#\(tag)", systemImage: "tag")
                                    Spacer()
                                    switch state {
                                    case .all: Image(systemName: "checkmark").foregroundStyle(.tint)
                                    case .some: Image(systemName: "minus").foregroundStyle(.secondary)
                                    case .none: EmptyView()
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle(items.count == 1 ? String(localized: "Tags") : String(localized: "Tag \(items.count) Items"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onAppear { if library.allTags.isEmpty { fieldFocused = true } }
        }
    }

    private enum State { case all, some, none }

    private func state(of tag: String) -> State {
        let count = items.count { $0.tags.contains(tag) }
        return count == items.count ? .all : count == 0 ? .none : .some
    }

    private func add() {
        library.addTag(newTag, to: items)
        newTag = ""
    }
}
