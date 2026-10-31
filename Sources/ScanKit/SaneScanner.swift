import CSane
import Foundation

public enum ScannerError: LocalizedError {
    case notFound
    case noPaper
    case cancelled
    case missingOption(String)
    case sane(String, SANE_Status)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "The scanner was not found. Open its cover and check the USB cable."
        case .noPaper: return "There is no paper in the feeder."
        case .cancelled: return "The scan was cancelled."
        case .missingOption(let name): return "The scanner does not offer the \"\(name)\" option."
        case .sane(let context, let status):
            return "\(context): \(String(cString: sane_strstatus(status)))."
        }
    }
}

/// Thin wrapper over a libsane device. SANE is not thread-safe, so every call must come
/// from the same serial queue.
public final class SaneScanner {
    /// Page feeding, resolution and blank-page handling aren't exposed in the UI. Both sides
    /// are always scanned and blank sides dropped, as ScanSnap Manager does by default.
    public static let resolution = 300
    private static let source = "ADF Duplex"
    private static let blankPagePercent = 1.0

    private static let readBufferSize = 256 * 1024

    private var handle: SANE_Handle?
    private var optionIndexes: [String: Int32] = [:]

    public init() {
        Self.initializeSANE()
    }

    deinit {
        close()
    }

    public var isOpen: Bool { handle != nil }

    /// Loads only the fujitsu backend. The default dll.conf lists every backend, which takes
    /// seconds to start and has the network ones probing the LAN.
    private static let initializeSANE: () -> Void = {
        var initialized = false
        return {
            guard !initialized else { return }
            initialized = true
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ScanButton-sane.d")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? "fujitsu\n".write(to: directory.appendingPathComponent("dll.conf"), atomically: true, encoding: .utf8)
            // The trailing colon keeps SANE's default directories on the search path, for fujitsu.conf.
            setenv("SANE_CONFIG_DIR", directory.path + ":", 1)
            var version: SANE_Int = 0
            _ = sane_init(&version, nil)
        }
    }()

    public func open() throws {
        guard handle == nil else { return }

        var list: UnsafeMutablePointer<UnsafePointer<SANE_Device>?>?
        try check(sane_get_devices(&list, SANE_Bool(SANE_TRUE)), "Listing scanners")
        guard let device = list?.pointee?.pointee, let name = device.name else {
            throw ScannerError.notFound
        }

        var opened: SANE_Handle?
        try check(sane_open(name, &opened), "Opening the scanner")
        handle = opened
        loadOptionIndexes()
    }

    public func close() {
        if let handle {
            sane_close(handle)
        }
        handle = nil
        optionIndexes = [:]
    }

    /// True if the Scan button was pressed since the last call. The S1500 latches a press
    /// until it's read, reporting it once however long the button is held.
    public func isScanButtonPressed() throws -> Bool {
        try readBool("scan")
    }

    public func isPaperLoaded() throws -> Bool {
        try readBool("page-loaded")
    }

    /// Feeds every sheet in the hopper and calls `onPage` as each side finishes.
    /// `isCancelled` is checked between reads. If the feed fails partway through (a jam, say)
    /// the error propagates, and pages already delivered through `onPage` remain valid.
    public func scan(
        mode: ColorMode,
        isCancelled: () -> Bool,
        onPageStart: (Int) -> Void,
        onPage: (ScannedPage) -> Void
    ) throws {
        guard let handle else { throw ScannerError.notFound }

        try setString("source", Self.source)
        try setString("mode", mode.saneMode)
        try setNumber("resolution", Double(Self.resolution))
        try setNumber("swskip", Self.blankPagePercent)

        defer { sane_cancel(handle) }
        var pageNumber = 0
        while true {
            if isCancelled() { throw ScannerError.cancelled }

            onPageStart(pageNumber + 1)
            let status = sane_start(handle)
            if status == SANE_STATUS_NO_DOCS {
                if pageNumber == 0 { throw ScannerError.noPaper }
                return
            }
            try check(status, "Starting the scan")

            if let page = try readPage(handle: handle, isCancelled: isCancelled) {
                pageNumber += 1
                onPage(page)
            }
        }
    }

    private func readPage(handle: SANE_Handle, isCancelled: () -> Bool) throws -> ScannedPage? {
        var parameters = SANE_Parameters()
        try check(sane_get_parameters(handle, &parameters), "Reading the scan parameters")

        var pixels = Data()
        if parameters.lines > 0 {
            pixels.reserveCapacity(Int(parameters.lines) * Int(parameters.bytes_per_line))
        }
        var buffer = [SANE_Byte](repeating: 0, count: Self.readBufferSize)
        while true {
            if isCancelled() { throw ScannerError.cancelled }
            var length: SANE_Int = 0
            let status = sane_read(handle, &buffer, SANE_Int(buffer.count), &length)
            if status == SANE_STATUS_EOF { break }
            try check(status, "Reading from the scanner")
            pixels.append(buffer, count: Int(length))
        }

        let bytesPerRow = Int(parameters.bytes_per_line)
        let width = Int(parameters.pixels_per_line)
        guard bytesPerRow > 0, width > 0 else { return nil }
        let height = pixels.count / bytesPerRow
        guard height > 0 else { return nil }
        pixels.removeLast(pixels.count - height * bytesPerRow)

        if parameters.depth == 1 {
            // SANE uses 1 for black in bilevel data; Quartz's gray space uses 1 for white.
            pixels.withUnsafeMutableBytes { bytes in
                for index in bytes.indices { bytes[index] = ~bytes[index] }
            }
            return ScannedPage(
                bilevel: pixels, width: width, height: height, bytesPerRow: bytesPerRow, dpi: Self.resolution
            )
        }
        return try ScannedPage(
            pixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow, dpi: Self.resolution,
            isColor: parameters.format == SANE_FRAME_RGB
        )
    }

    // MARK: - Options

    private func loadOptionIndexes() {
        guard let handle else { return }
        var count: SANE_Int = 0
        sane_control_option(handle, 0, SANE_ACTION_GET_VALUE, &count, nil)
        for index in 1..<max(count, 1) {
            if let name = sane_get_option_descriptor(handle, index)?.pointee.name {
                optionIndexes[String(cString: name)] = index
            }
        }
    }

    private func optionIndex(_ name: String) throws -> Int32 {
        guard let index = optionIndexes[name] else { throw ScannerError.missingOption(name) }
        return index
    }

    private func readBool(_ name: String) throws -> Bool {
        guard let handle else { throw ScannerError.notFound }
        var value: SANE_Bool = 0
        let status = sane_control_option(handle, try optionIndex(name), SANE_ACTION_GET_VALUE, &value, nil)
        try check(status, "Reading the scanner's \(name) sensor")
        return value != 0
    }

    private func setString(_ name: String, _ value: String) throws {
        guard let handle else { throw ScannerError.notFound }
        var bytes = Array(value.utf8CString)
        let status = sane_control_option(handle, try optionIndex(name), SANE_ACTION_SET_VALUE, &bytes, nil)
        try check(status, "Setting \(name) to \(value)")
    }

    private func setNumber(_ name: String, _ value: Double) throws {
        guard let handle else { throw ScannerError.notFound }
        let index = try optionIndex(name)
        let isFixed = sane_get_option_descriptor(handle, index)?.pointee.type == SANE_TYPE_FIXED
        var word = SANE_Word(isFixed ? value * Double(1 << SANE_FIXED_SCALE_SHIFT) : value)
        let status = sane_control_option(handle, index, SANE_ACTION_SET_VALUE, &word, nil)
        try check(status, "Setting \(name)")
    }

    private func check(_ status: SANE_Status, _ context: String) throws {
        if status == SANE_STATUS_NO_DOCS { throw ScannerError.noPaper }
        if status == SANE_STATUS_CANCELLED { throw ScannerError.cancelled }
        guard status == SANE_STATUS_GOOD else { throw ScannerError.sane(context, status) }
    }
}
