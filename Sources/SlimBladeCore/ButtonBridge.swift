import Foundation

// SlimBlade report handling adapted from LinearMouse; see THIRD_PARTY_NOTICES.md.

public enum SlimBladeButton: Int, CaseIterable, Hashable, Sendable {
    case upperLeft = 3
    case upperRight = 4
}

public enum ButtonTransition: Equatable, Sendable {
    case down(SlimBladeButton)
    case up(SlimBladeButton)
}

public enum SlimBladeReportParser {
    /// Wired SlimBlade reports carry upper-button bits in byte 4.
    public static func pressedButtons(in report: UnsafeRawBufferPointer) -> Set<SlimBladeButton>? {
        guard report.count >= 5 else { return nil }
        return pressedButtons(in: report[4])
    }

    public static func pressedButtons(in bytes: [UInt8]) -> Set<SlimBladeButton>? {
        bytes.withUnsafeBytes { pressedButtons(in: $0) }
    }

    private static func pressedButtons(in flags: UInt8) -> Set<SlimBladeButton> {
        var result: Set<SlimBladeButton> = []
        if flags & 0x01 != 0 { result.insert(.upperLeft) }
        if flags & 0x02 != 0 { result.insert(.upperRight) }
        return result
    }
}

/// Owns edge detection and coalesces button state across multiple physical devices.
/// Devices exposing standard HID Button usages 3 or 4 are placed in native mode.
public struct ButtonBridgeState<DeviceID: Hashable & Sendable>: Sendable {
    private struct Device: Sendable {
        var hasNativeButtons: Bool
        var pressed: Set<SlimBladeButton> = []
    }

    public private(set) var isEnabled: Bool
    private var devices: [DeviceID: Device] = [:]

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public var deviceCount: Int { devices.count }
    public var nativeDeviceCount: Int { devices.values.filter(\.hasNativeButtons).count }

    @discardableResult
    public mutating func attach(_ id: DeviceID, hasNativeButtons: Bool) -> [ButtonTransition] {
        var transitions: [ButtonTransition] = []
        if devices[id] != nil {
            transitions += detach(id)
        }
        devices[id] = Device(hasNativeButtons: hasNativeButtons)
        return transitions
    }

    public mutating func process(_ report: [UInt8], from id: DeviceID) -> [ButtonTransition] {
        report.withUnsafeBytes { process($0, from: id) }
    }

    public mutating func process(_ report: UnsafeRawBufferPointer, from id: DeviceID) -> [ButtonTransition] {
        guard isEnabled,
              var device = devices[id],
              !device.hasNativeButtons,
              let next = SlimBladeReportParser.pressedButtons(in: report)
        else { return [] }

        let before = aggregatePressed()
        device.pressed = next
        devices[id] = device
        return transitions(from: before, to: aggregatePressed())
    }

    @discardableResult
    public mutating func detach(_ id: DeviceID) -> [ButtonTransition] {
        let before = aggregatePressed()
        devices.removeValue(forKey: id)
        return transitions(from: before, to: aggregatePressed())
    }

    @discardableResult
    public mutating func setEnabled(_ enabled: Bool) -> [ButtonTransition] {
        guard enabled != isEnabled else { return [] }
        let before = aggregatePressed()
        isEnabled = enabled
        for key in devices.keys {
            devices[key]?.pressed.removeAll()
        }
        return enabled ? [] : transitions(from: before, to: [])
    }

    /// Clears physical state after sleep/wake or an input-stream reset.
    @discardableResult
    public mutating func resetPressedState() -> [ButtonTransition] {
        let before = aggregatePressed()
        for key in devices.keys {
            devices[key]?.pressed.removeAll()
        }
        return transitions(from: before, to: [])
    }

    private func aggregatePressed() -> Set<SlimBladeButton> {
        devices.values.reduce(into: []) { $0.formUnion($1.pressed) }
    }

    private func transitions(
        from old: Set<SlimBladeButton>,
        to new: Set<SlimBladeButton>
    ) -> [ButtonTransition] {
        SlimBladeButton.allCases.compactMap { button in
            if !old.contains(button), new.contains(button) { return .down(button) }
            if old.contains(button), !new.contains(button) { return .up(button) }
            return nil
        }
    }
}
