import AppKit
import ScanKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = ScannerMonitor()
    private let model = ScanPanelModel()
    private var panelController: ScanPanelController!
    private var statusItem: NSStatusItem!
    private var availability = ScannerAvailability.disconnected
    private var keepAwake: NSObjectProtocol?

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let scanItem = NSMenuItem(title: "Scan…", action: #selector(showOptions), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu bar app with no windows open gets App Napped, which would stall the button polling.
        keepAwake = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Watching for the scanner's Scan button")

        panelController = ScanPanelController(model: model, monitor: monitor)
        setUpStatusItem()
        registerForLoginOnFirstRun()

        monitor.onAvailabilityChange = { [weak self] availability in
            self?.availability = availability
            self?.refreshStatus()
        }
        monitor.onButtonPress = { [weak self] in
            self?.panelController.scanButtonPressed()
        }
        monitor.start()
        refreshStatus()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scanner", accessibilityDescription: "Fauxjitsu Scan Buddy")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        scanItem.target = self
        loginItem.target = self
        let folderItem = NSMenuItem(title: "Open Scans Folder", action: #selector(openFolder), keyEquivalent: "")
        folderItem.target = self
        menu.items = [
            statusLine, .separator(), scanItem, folderItem, .separator(), loginItem, .separator(),
            NSMenuItem(title: "Quit Fauxjitsu Scan Buddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]
        statusItem.menu = menu
    }

    private func refreshStatus() {
        switch availability {
        case .ready:
            statusLine.title = "Scanner ready"
            scanItem.isEnabled = true
        case .disconnected:
            statusLine.title = "Scanner off — open the cover"
            scanItem.isEnabled = false
        case .busy:
            statusLine.title = "Scanner in use by another app"
            scanItem.isEnabled = false
        }
        statusItem.button?.appearsDisabled = availability != .ready
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showOptions() {
        panelController.showOptions()
    }

    @objc private func openFolder() {
        try? FileManager.default.createDirectory(at: model.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(model.directory)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// A button-driven app is only useful if it's running, so it opts in once. It stays off for
    /// development builds, which would otherwise register a path inside .build.
    private func registerForLoginOnFirstRun() {
        // Named for the app bundle, since renaming the bundle needs a fresh registration.
        let key = "didRegisterFauxjitsuScanBuddyForLogin"
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications"
        else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }
}
