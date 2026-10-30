// One global shortcut to open the island. Carbon hot keys need no permission.
import Carbon
import AppKit

final class Hotkey {
    static let shared = Hotkey()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: () -> Void = {}

    func apply(_ preset: ShortcutPreset) {
        unregister()
        let combo: (UInt32, UInt32)?
        switch preset {
        case .off: combo = nil
        case .ctrlOptSpace: combo = (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .cmdShiftSpace: combo = (UInt32(kVK_Space), UInt32(cmdKey | shiftKey))
        case .ctrlOptP: combo = (UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey))
        }
        guard let c = combo else { return }
        let key = c.0, mods = c.1
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { Hotkey.shared.action() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5052_4348), id: 1) // "PRCH"
        RegisterEventHotKey(key, mods, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r) }
        ref = nil
    }
}
