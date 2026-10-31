import AppKit
import ScanKit
import SwiftUI

enum PanelStage: Equatable {
    case options
    case working(String)
    case finished(files: [URL], summary: String, warning: String?)
    case failed(String)
}

final class ScanPanelModel: ObservableObject {
    private static let optionsKey = "lastScanOptions"
    private static let directoryKey = "scanDirectory"

    @Published var stage = PanelStage.options
    @Published var options: ScanOptions
    @Published var directory: URL

    init() {
        let defaults = UserDefaults.standard
        options = defaults.data(forKey: Self.optionsKey)
            .flatMap { try? JSONDecoder().decode(ScanOptions.self, from: $0) } ?? ScanOptions()
        directory = defaults.string(forKey: Self.directoryKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Scans", isDirectory: true)
    }

    func saveDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(options), forKey: Self.optionsKey)
        defaults.set(directory.path, forKey: Self.directoryKey)
    }
}

final class ScanPanelController: NSObject, NSWindowDelegate {
    private static let autoCloseDelay: TimeInterval = 20

    private let model: ScanPanelModel
    private let monitor: ScannerMonitor
    private let panel: NSPanel
    private var autoClose: DispatchWorkItem?

    init(model: ScanPanelModel, monitor: ScannerMonitor) {
        self.model = model
        self.monitor = monitor
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        super.init()

        panel.title = "Fauxjitsu Scan Buddy"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ScanPanelView(
            model: model,
            onScan: { [weak self] in self?.startScan() },
            onCancelOptions: { [weak self] in self?.closePanel() },
            onCancelScan: { [weak self] in self?.monitor.cancelScan() },
            onBack: { [weak self] in self?.showOptions() },
            onClose: { [weak self] in self?.closePanel() },
            onChooseFolder: { [weak self] in self?.chooseFolder() },
            onOpen: { [weak self] files in self?.finish { NSWorkspace.shared.open(files[0]) } },
            onReveal: { [weak self] files in self?.finish { NSWorkspace.shared.activateFileViewerSelecting(files) } }
        ))
    }

    /// The scanner's button opens the options; pressing it again confirms them, so a scan
    /// can be run from the scanner without touching the keyboard.
    func scanButtonPressed() {
        switch model.stage {
        case .options where panel.isVisible:
            startScan()
        case .working:
            break
        default:
            showOptions()
        }
    }

    func showOptions() {
        if case .working = model.stage { return present() }
        autoClose?.cancel()
        model.stage = .options
        present()
    }

    private func present() {
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
        if !panel.isVisible { panel.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func closePanel() {
        autoClose?.cancel()
        panel.orderOut(nil)
        if case .working = model.stage { return }
        model.stage = .options
    }

    private func finish(then action: () -> Void) {
        closePanel()
        action()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if case .working = model.stage {
            monitor.cancelScan()
            return false
        }
        closePanel()
        return false
    }

    private func startScan() {
        model.saveDefaults()
        model.stage = .working("Starting…")
        monitor.scan(
            options: model.options,
            directory: model.directory,
            onProgress: { [weak self] progress in self?.show(progress) },
            completion: { [weak self] result in self?.show(result) }
        )
    }

    private func show(_ progress: ScanProgress) {
        guard case .working = model.stage else { return }
        switch progress {
        case .scanning(let page):
            model.stage = .working("Scanning page \(page)…")
        case .recognizing(let page, let total):
            model.stage = .working("Recognizing text, page \(page) of \(total)…")
        }
    }

    private func show(_ result: Result<ScanResult, Error>) {
        switch result {
        case .success(let result):
            let pages = result.pageCount == 1 ? "1 page" : "\(result.pageCount) pages"
            model.stage = .finished(files: result.files, summary: "Saved \(pages)", warning: result.interruption)
            // Stay up if something went wrong, so a partial scan can't go unnoticed.
            if result.interruption == nil { scheduleAutoClose() }
        case .failure(ScannerError.cancelled):
            model.stage = .options
            closePanel()
            return
        case .failure(let error):
            model.stage = .failed(error.localizedDescription)
        }
        present()
    }

    private func scheduleAutoClose() {
        let work = DispatchWorkItem { [weak self] in self?.closePanel() }
        autoClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoCloseDelay, execute: work)
    }

    private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = true
        picker.prompt = "Choose"
        picker.directoryURL = model.directory
        picker.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            self?.model.directory = url
            self?.model.saveDefaults()
        }
    }
}

struct ScanPanelView: View {
    @ObservedObject var model: ScanPanelModel
    let onScan: () -> Void
    let onCancelOptions: () -> Void
    let onCancelScan: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let onChooseFolder: () -> Void
    let onOpen: ([URL]) -> Void
    let onReveal: ([URL]) -> Void

    var body: some View {
        Group {
            switch model.stage {
            case .options:
                optionsView
            case .working(let message):
                workingView(message)
            case .finished(let files, let summary, let warning):
                finishedView(files: files, summary: summary, warning: warning)
            case .failed(let message):
                failedView(message)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                BuddyMascot().frame(width: 52, height: 52)
                (Text("Fauxjitsu ").fontWeight(.black) + Text("Scan Buddy").fontWeight(.medium))
                    .font(.system(size: 30, design: .rounded))
                    .foregroundStyle(Color(nsColor: NSColor(name: nil) { appearance in
                        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                            ? NSColor(red: 0.4, green: 0.8, blue: 0.95, alpha: 1)
                            : NSColor(red: 0.07, green: 0.5, blue: 0.72, alpha: 1)
                    }))
                    .accessibilityAddTraits(.isHeader)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    rowLabel("Color:")
                    HStack(spacing: 4) {
                        colorTile("B&W", .blackAndWhite)
                        colorTile("Grayscale", .grayscale)
                        colorTile("Color", .color)
                    }
                }
                GridRow {
                    rowLabel("Text:")
                        .opacity(model.options.format == .jpg ? 0.35 : 1)
                    HStack(spacing: 4) {
                        ocrTile("OCR", true)
                        ocrTile("No OCR", false)
                    }
                    .disabled(model.options.format == .jpg)
                    .opacity(model.options.format == .jpg ? 0.35 : 1)
                }
                GridRow {
                    rowLabel("Save as:")
                    HStack(spacing: 4) {
                        formatTile("PDF", .pdf)
                        formatTile("JPG", .jpg)
                    }
                }
            }
            HStack {
                Text("Folder:")
                Text(model.directory.path(percentEncoded: false)
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Change…", action: onChooseFolder)
            }
            HStack {
                Text("Press Scan on the scanner, or Return")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancelOptions)
                    .keyboardShortcut(.cancelAction)
                Button("Scan", action: onScan)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func workingView(_ message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel", action: onCancelScan)
                .keyboardShortcut(.cancelAction)
        }
    }

    private func finishedView(files: [URL], summary: String, warning: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summary, systemImage: warning == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(warning == nil ? Color.primary : Color.orange)
            if let warning {
                Text("The scan stopped early: \(warning) Only the pages above were saved.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(files.count == 1 ? files[0].lastPathComponent : "\(files.count) files in \(files[0].deletingLastPathComponent().lastPathComponent)")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Spacer()
                Button("Show in Finder") { onReveal(files) }
                if files.count == 1 {
                    Button("Open") { onOpen(files) }
                }
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Try Again", action: onBack)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .gridColumnAlignment(.trailing)
    }

    private func colorTile(_ title: String, _ mode: ColorMode) -> some View {
        OptionTile(title: title, isSelected: model.options.colorMode == mode) {
            model.options.colorMode = mode
        } icon: {
            ColorModeIcon(mode: mode)
        }
    }

    private func ocrTile(_ title: String, _ isOn: Bool) -> some View {
        OptionTile(title: title, isSelected: model.options.ocr == isOn) {
            model.options.ocr = isOn
        } icon: {
            OCRIcon(isOn: isOn)
        }
    }

    private func formatTile(_ title: String, _ format: OutputFormat) -> some View {
        OptionTile(title: title, isSelected: model.options.format == format) {
            model.options.format = format
        } icon: {
            FormatIcon(format: format)
        }
    }
}
