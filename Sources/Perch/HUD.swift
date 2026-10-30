// Optional: take over the volume and brightness keys so the island shows the level instead of the
// big grey square. This needs Accessibility, so it is off until you turn it on in Settings.
import AppKit
import ApplicationServices
import CoreGraphics

enum Brightness {
    private typealias Getter = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (UInt32, Float) -> Int32
    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getter: Getter? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Getter.self) }
    private static let setter: Setter? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Setter.self) }

    static var available: Bool { getter != nil && setter != nil }

    static var builtInDisplay: UInt32 {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &n)
        return ids.prefix(Int(n)).first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? CGMainDisplayID()
    }

    static var level: Float {
        get {
            var v: Float = 0
            _ = getter?(builtInDisplay, &v)
            return v
        }
        set { _ = setter?(builtInDisplay, min(max(newValue, 0), 1)) }
    }
}

@MainActor
final class MediaKeyTap {
    static let shared = MediaKeyTap()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    weak var signals: SignalCenter?
    var onBrightness: (Float) -> Void = { _ in }

    var isRunning: Bool { tap != nil }

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once. macOS then lists Perch under Accessibility.
    static func askForTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start() {
        guard tap == nil, Self.trusted else { return }
        let mask = CGEventMask(1) << 14  // NSEvent.EventType.systemDefined
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, ctx in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let ctx { let t = Unmanaged<MediaKeyTap>.fromOpaque(ctx).takeUnretainedValue()
                    DispatchQueue.main.async { MainActor.assumeIsolated { if let p = t.tap { CGEvent.tapEnable(tap: p, enable: true) } } } }
                return Unmanaged.passUnretained(event)
            }
            guard let ctx, let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }
            let code = Int((ns.data1 & 0xFFFF0000) >> 16)
            let down = ((ns.data1 & 0xFF00) >> 8) == 0xA
            let fine = ns.modifierFlags.contains(.option) && ns.modifierFlags.contains(.shift)
            // 0 sound up, 1 sound down, 2 brightness up, 3 brightness down, 7 mute
            guard [0, 1, 2, 3, 7].contains(code) else { return Unmanaged.passUnretained(event) }
            if down {
                let t = Unmanaged<MediaKeyTap>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { t.handle(code: code, fine: fine) } }
            }
            return nil
        }, userInfo: me) else { return }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let p = tap { CGEvent.tapEnable(tap: p, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
    }

    private func handle(code: Int, fine: Bool) {
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
        switch code {
        case 0, 1:
            let now = SystemVolume.volume
            let next = code == 0 ? now + step : now - step
            SystemVolume.volume = (next * 64).rounded() / 64
            if code == 0, SystemVolume.isMuted { SystemVolume.isMuted = false }
        case 7:
            SystemVolume.isMuted.toggle()
        case 2, 3:
            guard Brightness.available else { return }
            let now = Brightness.level
            Brightness.level = code == 2 ? now + step : now - step
            onBrightness(Brightness.level)
        default: break
        }
        if Prefs.shared.haptics { Haptics.level() }
    }
}
