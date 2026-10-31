import Foundation
import IOKit
import IOKit.usb

public enum ScannerAvailability: Sendable, Equatable {
    case disconnected
    case ready
    case busy(String)
}

public enum ScanProgress: Sendable {
    case scanning(page: Int)
    case recognizing(page: Int, total: Int)
}

public struct ScanResult: Sendable {
    public let files: [URL]
    public let pageCount: Int
    /// Set when the feed failed partway; `files` then holds the pages scanned before the failure.
    public let interruption: String?
}

/// Owns the scanner. All SANE work happens on one private queue: while the device is on USB
/// it polls the Scan button, and a running job simply blocks the polling until it finishes.
/// Callbacks arrive on the main queue.
public final class ScannerMonitor: @unchecked Sendable {
    public var onAvailabilityChange: ((ScannerAvailability) -> Void)?
    public var onButtonPress: (() -> Void)?

    private static let vendorID = 0x04C5
    private static let productID = 0x11A2
    private static let pollInterval: DispatchTimeInterval = .milliseconds(150)
    private static let reopenInterval: TimeInterval = 2

    private let queue = DispatchQueue(label: "ScanButton.scanner")
    private let scanner: SaneScanner
    private var timer: DispatchSourceTimer?
    private var usbWatcher: USBWatcher?
    private var isOnUSB = false
    private var wasPressed = false
    private var lastOpenAttempt = Date.distantPast
    private var availability = ScannerAvailability.disconnected

    private let cancelLock = NSLock()
    private var cancelRequested = false

    public init() {
        scanner = SaneScanner()
    }

    public func start() {
        queue.async { [self] in
            usbWatcher = USBWatcher(
                vendorID: Self.vendorID, productID: Self.productID, queue: queue
            ) { [weak self] present in
                self?.usbPresenceChanged(present)
            }
        }
    }

    /// Runs a scan job. Button presses during the job are ignored.
    public func scan(
        options: ScanOptions,
        directory: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void,
        completion: @escaping @Sendable (Result<ScanResult, Error>) -> Void
    ) {
        setCancelRequested(false)
        queue.async { [self] in
            let result = Result { try runJob(options: options, directory: directory, onProgress: onProgress) }
            // Discard any press latched during the job, so it can't start another one.
            wasPressed = (try? scanner.isScanButtonPressed()) ?? false
            DispatchQueue.main.async { completion(result) }
        }
    }

    public func cancelScan() {
        setCancelRequested(true)
    }

    private func runJob(
        options: ScanOptions,
        directory: URL,
        onProgress: @escaping @Sendable (ScanProgress) -> Void
    ) throws -> ScanResult {
        // Fail on an unusable folder now, before a stack of paper has gone through the feeder.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try scanner.open()

        var pages: [ScannedPage] = []
        var interruption: Error?
        do {
            try scanner.scan(
                mode: options.colorMode,
                isCancelled: { [self] in isCancelRequested },
                onPageStart: { page in DispatchQueue.main.async { onProgress(.scanning(page: page)) } },
                onPage: { pages.append($0) }
            )
        } catch ScannerError.cancelled {
            throw ScannerError.cancelled
        } catch {
            // A jam on page 12 shouldn't cost the first 11 sheets.
            guard !pages.isEmpty else { throw error }
            interruption = error
        }

        let files = try ScanWriter.write(pages: pages, options: options, directory: directory) { page, total in
            DispatchQueue.main.async { onProgress(.recognizing(page: page, total: total)) }
        }
        return ScanResult(files: files, pageCount: pages.count, interruption: interruption?.localizedDescription)
    }

    private var isCancelRequested: Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelRequested
    }

    private func setCancelRequested(_ value: Bool) {
        cancelLock.lock()
        cancelRequested = value
        cancelLock.unlock()
    }

    // MARK: - Polling

    private func usbPresenceChanged(_ present: Bool) {
        isOnUSB = present
        if present {
            lastOpenAttempt = .distantPast
            startPolling()
        } else {
            stopPolling()
            scanner.close()
            setAvailability(.disconnected)
        }
    }

    private func startPolling() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(25))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    private func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        if !scanner.isOpen {
            // The device takes a moment to come up after its cover opens, and another program
            // may be holding it, so keep trying at a gentle pace.
            guard Date().timeIntervalSince(lastOpenAttempt) >= Self.reopenInterval else { return }
            lastOpenAttempt = Date()
            do {
                try scanner.open()
                // Discard any press latched before the app was watching.
                wasPressed = try scanner.isScanButtonPressed()
                setAvailability(.ready)
            } catch {
                scanner.close()
                setAvailability(.busy(error.localizedDescription))
            }
            return
        }

        do {
            let pressed = try scanner.isScanButtonPressed()
            defer { wasPressed = pressed }
            if pressed && !wasPressed {
                DispatchQueue.main.async { [weak self] in self?.onButtonPress?() }
            }
        } catch {
            scanner.close()
            lastOpenAttempt = Date()
            setAvailability(.busy(error.localizedDescription))
        }
    }

    private func setAvailability(_ new: ScannerAvailability) {
        guard new != availability else { return }
        availability = new
        DispatchQueue.main.async { [weak self] in self?.onAvailabilityChange?(new) }
    }
}

/// Reports a USB device arriving and leaving. The scanner powers off when its cover closes,
/// so these notifications let the app go completely idle until the cover opens again.
private final class USBWatcher {
    private let port: IONotificationPortRef
    private let onChange: (Bool) -> Void
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0

    init(vendorID: Int, productID: Int, queue: DispatchQueue, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, queue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for (type, isArrival) in [(kIOMatchedNotification, true), (kIOTerminatedNotification, false)] {
            let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
            matching[kUSBVendorID] = vendorID
            matching[kUSBProductID] = productID

            var iterator: io_iterator_t = 0
            let callback: IOServiceMatchingCallback = isArrival
                ? { context, iterator in USBWatcher.drain(iterator, context: context, present: true) }
                : { context, iterator in USBWatcher.drain(iterator, context: context, present: false) }
            IOServiceAddMatchingNotification(port, type, matching, callback, context, &iterator)
            // Draining arms the notification, and reports a scanner that was already attached.
            USBWatcher.drain(iterator, context: context, present: isArrival)
            if isArrival { matchedIterator = iterator } else { terminatedIterator = iterator }
        }
    }

    deinit {
        IOObjectRelease(matchedIterator)
        IOObjectRelease(terminatedIterator)
        IONotificationPortDestroy(port)
    }

    private static func drain(_ iterator: io_iterator_t, context: UnsafeMutableRawPointer?, present: Bool) {
        guard let context else { return }
        let watcher = Unmanaged<USBWatcher>.fromOpaque(context).takeUnretainedValue()
        var changed = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
            changed = true
        }
        if changed { watcher.onChange(present) }
    }
}
