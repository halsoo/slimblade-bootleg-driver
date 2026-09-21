import ApplicationServices
import Foundation
import IOKit.hid
import SlimBladeCore

final class HIDBridgeService {
    struct Snapshot: Equatable {
        let connected: Int
        let nativeMode: Int
        let lastError: String?
    }

    var onSnapshotChange: ((Snapshot) -> Void)?

    private let manager: IOHIDManager
    private var state: ButtonBridgeState<UInt>
    private var lastError: String?

    init(enabled: Bool) {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        state = ButtonBridgeState(isEnabled: enabled)

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x047D,
            kIOHIDProductIDKey as String: 0x2041,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context else { return }
            Unmanaged<HIDBridgeService>.fromOpaque(context).takeUnretainedValue()
                .deviceAttached(device, result: result)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, _, device in
            guard let context else { return }
            Unmanaged<HIDBridgeService>.fromOpaque(context).takeUnretainedValue()
                .deviceDetached(device, result: result)
        }, context)
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, type, _, report, length in
            guard let context, let sender, type == kIOHIDReportTypeInput else { return }
            let service = Unmanaged<HIDBridgeService>.fromOpaque(context).takeUnretainedValue()
            let device = unsafeBitCast(sender, to: IOHIDDevice.self)
            service.received(report: report, length: length, from: device, result: result)
        }, context)

        // Scheduling on the main run loop serializes callbacks with menu actions.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            lastError = "Could not open HID manager (0x\(String(UInt32(bitPattern: result), radix: 16)))."
        }
    }

    deinit {
        emit(state.resetPressedState())
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func setEnabled(_ enabled: Bool) {
        emit(state.setEnabled(enabled))
        publishSnapshot()
    }

    func resetForSystemTransition() {
        emit(state.resetPressedState())
    }

    func currentSnapshot() -> Snapshot {
        Snapshot(connected: state.deviceCount, nativeMode: state.nativeDeviceCount, lastError: lastError)
    }

    private func deviceAttached(_ device: IOHIDDevice, result: IOReturn) {
        record(result, operation: "Device attachment")
        emit(state.attach(identity(of: device), hasNativeButtons: exposesStandardUpperButtons(device)))
        publishSnapshot()
    }

    private func deviceDetached(_ device: IOHIDDevice, result: IOReturn) {
        record(result, operation: "Device removal")
        emit(state.detach(identity(of: device)))
        publishSnapshot()
    }

    private func received(
        report: UnsafeMutablePointer<UInt8>,
        length: CFIndex,
        from device: IOHIDDevice,
        result: IOReturn
    ) {
        guard result == kIOReturnSuccess else {
            record(result, operation: "Input report")
            publishSnapshot()
            return
        }
        guard length >= 0 else { return }
        let bytes = UnsafeRawBufferPointer(start: report, count: length)
        emit(state.process(bytes, from: identity(of: device)))
    }

    private func exposesStandardUpperButtons(_ device: IOHIDDevice) -> Bool {
        let matching = [kIOHIDElementUsagePageKey as String: 0x09] as CFDictionary
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            matching,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return false }

        let usages = Set(elements.map(IOHIDElementGetUsage))
        return usages.contains(3) || usages.contains(4)
    }

    private func identity(of device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    private func emit(_ transitions: [ButtonTransition]) {
        for transition in transitions {
            let button: SlimBladeButton
            let eventType: CGEventType
            switch transition {
            case let .down(value):
                button = value
                eventType = .otherMouseDown
            case let .up(value):
                button = value
                eventType = .otherMouseUp
            }

            guard let location = CGEvent(source: nil)?.location,
                  let mouseButton = CGMouseButton(rawValue: UInt32(button.rawValue)),
                  let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: eventType,
                    mouseCursorPosition: location,
                    mouseButton: mouseButton
                  )
            else {
                lastError = "Could not create a synthetic mouse event."
                publishSnapshot()
                continue
            }
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
            event.post(tap: .cghidEventTap)
        }
    }

    private func record(_ result: IOReturn, operation: String) {
        guard result != kIOReturnSuccess else { return }
        lastError = "\(operation) failed (0x\(String(UInt32(bitPattern: result), radix: 16)))."
    }

    private func publishSnapshot() {
        onSnapshotChange?(currentSnapshot())
    }
}
