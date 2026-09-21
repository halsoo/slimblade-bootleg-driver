import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let enabled = "driverEnabled"
    }

    private var statusItem: NSStatusItem!
    private var service: HIDBridgeService!
    private var snapshot = HIDBridgeService.Snapshot(connected: 0, nativeMode: 0, lastError: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [DefaultsKey.enabled: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "computermouse",
            accessibilityDescription: "SlimBlade Bootleg Driver"
        )
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self

        service = HIDBridgeService(enabled: isEnabled)
        service.onSnapshotChange = { [weak self] snapshot in
            self?.snapshot = snapshot
        }
        snapshot = service.currentSnapshot()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        service.setEnabled(false)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.enabled)
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        let next = !isEnabled
        UserDefaults.standard.set(next, forKey: DefaultsKey.enabled)
        service.setEnabled(next)
    }

    @objc private func requestAccessibility(_ sender: NSMenuItem) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("Could not update Launch at Login: \(error.localizedDescription)")
        }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    @objc private func systemWillSleep() {
        service.resetForSystemTransition()
    }

    @objc private func systemDidWake() {
        service.resetForSystemTransition()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "SlimBlade Bootleg Driver"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func statusText() -> String {
        if let error = snapshot.lastError { return "Error: \(error)" }
        guard snapshot.connected > 0 else { return "No SlimBlade connected" }
        if snapshot.nativeMode == snapshot.connected {
            return snapshot.connected == 1 ? "Connected · native buttons" : "\(snapshot.connected) connected · native buttons"
        }
        if snapshot.nativeMode > 0 {
            return "\(snapshot.connected) connected · \(snapshot.nativeMode) native"
        }
        return snapshot.connected == 1 ? "Connected · raw bridge" : "\(snapshot.connected) connected · raw bridge"
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "SlimBlade Bootleg Driver", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = isEnabled ? .on : .off
        menu.addItem(enabled)

        let trusted = AXIsProcessTrusted()
        let accessibility = NSMenuItem(
            title: trusted ? "Accessibility Permission Granted" : "Open Accessibility Settings…",
            action: trusted ? nil : #selector(requestAccessibility),
            keyEquivalent: ""
        )
        accessibility.target = self
        accessibility.isEnabled = !trusted
        menu.addItem(accessibility)

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }
}
