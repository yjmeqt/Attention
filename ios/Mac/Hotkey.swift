import Carbon.HIToolbox

/// A system-wide shortcut. Carbon's hot keys need no Accessibility permission, unlike event taps.
final class Hotkey {
    static let label = "⌃⌥⌘A"

    private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    init(action: @escaping () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers hot keys on the main thread.
            MainActor.assumeIsolated { Hotkey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4154_544E), id: 1) // "ATTN"
        RegisterEventHotKey(UInt32(kVK_ANSI_A), UInt32(controlKey | optionKey | cmdKey), id,
                            GetApplicationEventTarget(), 0, &ref)
    }
}
