// Things the Mac itself is doing: output volume, microphone and camera in use, battery and charging,
// headphones connecting. None of these need a permission except Bluetooth, which is opt-in.
import AppKit
import CoreAudio
import AudioToolbox
import CoreMediaIO
import IOKit.ps
import IOBluetooth
import Combine
import SwiftUI

// MARK: Volume

enum SystemVolume {
    static func defaultOutput() -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let s = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return s == noErr && id != kAudioObjectUnknown ? id : nil
    }

    static var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                          mScope: kAudioDevicePropertyScopeOutput,
                                                          mElement: kAudioObjectPropertyElementMain)
    static var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                        mScope: kAudioDevicePropertyScopeOutput,
                                                        mElement: kAudioObjectPropertyElementMain)

    static var volume: Float {
        get {
            guard let dev = defaultOutput() else { return 0 }
            var v = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            var a = volumeAddress
            return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : 0
        }
        set {
            guard let dev = defaultOutput() else { return }
            var v = Float32(min(max(newValue, 0), 1))
            var a = volumeAddress
            AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
            if v > 0 && isMuted { isMuted = false }
        }
    }

    static var isMuted: Bool {
        get {
            guard let dev = defaultOutput() else { return false }
            var m = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            var a = muteAddress
            return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &m) == noErr && m != 0
        }
        set {
            guard let dev = defaultOutput() else { return }
            var m = UInt32(newValue ? 1 : 0)
            var a = muteAddress
            AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        }
    }

    static func deviceIsRunning(_ dev: AudioObjectID) -> Bool {
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &running) == noErr && running != 0
    }

    static func defaultInput() -> AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let s = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return s == noErr && id != kAudioObjectUnknown ? id : nil
    }
}

enum CameraState {
    /// True when any app is using any camera. Reads CoreMediaIO, no permission needed.
    static func inUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var a = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                              mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                              mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var got: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }
}

// MARK: Battery

struct BatteryState: Equatable {
    var percent: Int
    var charging: Bool
    var pluggedIn: Bool
    var hasBattery: Bool
    var minutesLeft: Int?

    static func read() -> BatteryState {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryState(percent: 100, charging: false, pluggedIn: true, hasBattery: false, minutesLeft: nil)
        }
        for ps in list {
            guard let info = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = info[kIOPSPowerSourceStateKey] as? String
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let mins = (info[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            return BatteryState(percent: max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur,
                                charging: charging, pluggedIn: state == kIOPSACPowerValue, hasBattery: true,
                                minutesLeft: mins)
        }
        return BatteryState(percent: 100, charging: false, pluggedIn: true, hasBattery: false, minutesLeft: nil)
    }
}

// MARK: The signal hub

/// One short moment the island can show by widening for a few seconds.
struct Moment: Equatable, Identifiable {
    enum Kind: Equatable { case agent, timer, volume, brightness, charging, device, camera, mic, mail, event, shelf }
    let id = UUID()
    var kind: Kind
    var symbol: String
    var title: String
    var detail: String?
    var tint: Color
    /// 0...1 for HUD bars and the battery fill; nil for text-only moments.
    var level: Double?
    var duration: TimeInterval = 3.2

    static func == (a: Moment, b: Moment) -> Bool {
        a.id == b.id && a.level == b.level && a.title == b.title
    }
}

@MainActor
final class SignalCenter: NSObject, ObservableObject {
    @Published private(set) var battery = BatteryState.read()
    @Published private(set) var cameraOn = false
    @Published private(set) var micOn = false
    @Published private(set) var volume: Float = SystemVolume.volume
    @Published private(set) var muted = SystemVolume.isMuted

    var onMoment: (Moment) -> Void = { _ in }
    /// Set while Perch itself changes the volume, so its own slider does not pop a HUD.
    var quietVolumeUntil = Date.distantPast

    private let prefs = Prefs.shared
    private var psSource: CFRunLoopSource?
    private var privacyTimer: Timer?
    private var volumeDevice: AudioObjectID?
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    private var deviceBlock: AudioObjectPropertyListenerBlock?
    private var btNote: IOBluetoothUserNotification?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        startBattery()
        startVolume()
        startPrivacy()
        if prefs.deviceMoments { startBluetooth() }
    }

    // Battery: IOKit calls us when anything about power changes.
    private func startBattery() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<SignalCenter>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { me.batteryChanged() } }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            psSource = src
        }
    }

    private func batteryChanged() {
        let now = BatteryState.read()
        let before = battery
        battery = now
        guard prefs.chargingMoment, now.hasBattery else { return }
        if now.pluggedIn && !before.pluggedIn {
            onMoment(Moment(kind: .charging, symbol: "bolt.fill", title: "\(now.percent)%",
                            detail: now.charging ? "Charging" : "Plugged in", tint: Ink.mint,
                            level: Double(now.percent) / 100, duration: 3.6))
        } else if !now.pluggedIn && now.percent <= 20 && before.percent > 20 {
            onMoment(Moment(kind: .charging, symbol: "battery.25", title: "\(now.percent)%",
                            detail: "Battery low", tint: Ink.coral, level: Double(now.percent) / 100, duration: 4))
        }
    }

    // Volume: listen on the default output device, and follow it when it changes (AirPods etc).
    private func startVolume() {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.attachVolumeListener() } }
        }
        deviceBlock = block
        AudioObjectAddPropertyListenerBlock(sys, &addr, DispatchQueue.main, block)
        attachVolumeListener()
    }

    private func attachVolumeListener() {
        if let dev = volumeDevice, let b = volumeBlock {
            var a = SystemVolume.volumeAddress
            AudioObjectRemovePropertyListenerBlock(dev, &a, DispatchQueue.main, b)
            var m = SystemVolume.muteAddress
            AudioObjectRemovePropertyListenerBlock(dev, &m, DispatchQueue.main, b)
        }
        guard let dev = SystemVolume.defaultOutput() else { return }
        let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.volumeChanged() } }
        }
        var a = SystemVolume.volumeAddress
        AudioObjectAddPropertyListenerBlock(dev, &a, DispatchQueue.main, b)
        var m = SystemVolume.muteAddress
        AudioObjectAddPropertyListenerBlock(dev, &m, DispatchQueue.main, b)
        volumeDevice = dev
        volumeBlock = b
        volume = SystemVolume.volume
        muted = SystemVolume.isMuted
    }

    private func volumeChanged() {
        let v = SystemVolume.volume, m = SystemVolume.isMuted
        guard v != volume || m != muted else { return }
        volume = v; muted = m
        guard prefs.volumeHUD, Date() > quietVolumeUntil else { return }
        showVolumeMoment()
    }

    func showVolumeMoment() {
        let symbol = muted || volume == 0 ? "speaker.slash.fill" : (volume < 0.34 ? "speaker.wave.1.fill" : (volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
        onMoment(Moment(kind: .volume, symbol: symbol, title: muted ? "Muted" : "\(Int((volume * 100).rounded()))",
                        detail: nil, tint: Ink.accent, level: muted ? 0 : Double(volume), duration: 1.6))
    }

    func setVolume(_ v: Float) {
        quietVolumeUntil = Date().addingTimeInterval(0.6)
        SystemVolume.volume = v
        volume = SystemVolume.volume
        muted = SystemVolume.isMuted
    }

    // Camera and microphone: a cheap check every 2 seconds (CoreMediaIO has no simple global callback).
    private func startPrivacy() {
        privacyTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPrivacy() }
        }
        privacyTimer?.tolerance = 0.5
        checkPrivacy()
    }

    private func checkPrivacy() {
        guard prefs.privacyDots else { if cameraOn || micOn { cameraOn = false; micOn = false }; return }
        let cam = CameraState.inUse()
        let mic = SystemVolume.defaultInput().map(SystemVolume.deviceIsRunning) ?? false
        if cam && !cameraOn {
            onMoment(Moment(kind: .camera, symbol: "video.fill", title: "Camera on",
                            detail: "Your cover has it covered", tint: Ink.mint, level: nil, duration: 3))
        }
        if mic && !micOn && !cam {
            onMoment(Moment(kind: .mic, symbol: "mic.fill", title: "Microphone on", detail: nil, tint: Ink.amber, level: nil, duration: 2.6))
        }
        if cam != cameraOn { cameraOn = cam }
        if mic != micOn { micOn = mic }
    }

    // Headphones: IOBluetooth tells us when a device connects. macOS asks once for Bluetooth access.
    func startBluetooth() {
        guard btNote == nil else { return }
        btNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    func stopBluetooth() {
        btNote?.unregister()
        btNote = nil
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Bluetooth device"
        let lower = name.lowercased()
        let symbol = lower.contains("airpods max") ? "airpodsmax"
            : lower.contains("airpods pro") ? "airpodspro"
            : lower.contains("airpods") ? "airpods"
            : (lower.contains("beats") || lower.contains("head") || lower.contains("buds")) ? "headphones"
            : lower.contains("keyboard") ? "keyboard" : lower.contains("mouse") || lower.contains("trackpad") ? "computermouse" : "dot.radiowaves.left.and.right"
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard self.prefs.deviceMoments else { return }
                self.onMoment(Moment(kind: .device, symbol: symbol, title: name, detail: "Connected", tint: Ink.sky, level: nil, duration: 3))
            }
        }
    }
}
