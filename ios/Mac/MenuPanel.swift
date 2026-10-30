import SwiftUI
import ServiceManagement

struct MenuPanel: View {
    @Bindable var maker: CardMaker
    let openLibrary: () -> Void
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                TextField("Paste a link", text: $maker.input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(maker.makeFromInput)
                Button("Make", systemImage: "arrow.right.circle.fill", action: maker.makeFromInput)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title2)
                    .disabled(maker.input.isEmpty)
            }

            Picker("Style", selection: $maker.style.template) {
                ForEach(CardTemplate.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            preview

            HStack {
                Button("Copy Image", systemImage: "photo.on.rectangle") { maker.copyImage() }
                    .keyboardShortcut("c")
                Button("Copy Link", systemImage: "link", action: maker.copyLink)
                Spacer()
                Button("Save…", systemImage: "square.and.arrow.down", action: maker.save)
                    .labelStyle(.iconOnly)
                    .help("Save…")
            }
            .disabled(maker.card == nil)

            Divider()

            HStack {
                Button("Open Library", systemImage: "square.grid.2x2", action: openLibrary)
                    .keyboardShortcut("l")
                Spacer()
                Toggle("Open at Login", isOn: $opensAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: opensAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                Button("Quit", action: { NSApp.terminate(nil) })
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }

    @ViewBuilder private var preview: some View {
        Group {
            if let card = maker.card {
                ScrollView {
                    Image(nsImage: card)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10).strokeBorder(.separator)
                        }
                        .onDrag { maker.cardFile().flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider() }
                        .help("Drag into a chat, or copy it")
                }
                .frame(maxHeight: 440)
                .fixedSize(horizontal: false, vertical: true)
                .overlay {
                    if maker.phase == .working { ProgressView().controlSize(.small) }
                }
            } else {
                VStack(spacing: 8) {
                    switch maker.phase {
                    case .working:
                        ProgressView()
                    case .failed:
                        Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.secondary)
                        Text("No link found").foregroundStyle(.secondary)
                    case .idle, .ready:
                        Image(systemName: "link").font(.title2).foregroundStyle(.secondary)
                        Text("Copy a link, then press \(Hotkey.label) anywhere to put its card on the clipboard.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 160)
                .padding(.horizontal)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10))
            }
        }
    }
}
