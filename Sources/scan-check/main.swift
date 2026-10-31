// Hardware check, separate from the app:
//   scan-check watch [seconds]
//   scan-check scan <output-dir> <bw|gray|color> <ocr|no-ocr> <pdf|jpg>
import Foundation
import ScanKit

setvbuf(stdout, nil, _IOLBF, 0)

let arguments = CommandLine.arguments

func watchButton(seconds: Double) throws {
    let scanner = SaneScanner()
    let opened = Date()
    try scanner.open()
    print(String(format: "opened in %.2fs; watching for %.0fs", Date().timeIntervalSince(opened), seconds))

    var wasPressed = try scanner.isScanButtonPressed()
    print("initial state: \(wasPressed)")
    var reads = 0
    var slowest = 0.0
    let start = Date()
    while Date().timeIntervalSince(start) < seconds {
        let before = Date()
        let pressed = try scanner.isScanButtonPressed()
        slowest = max(slowest, Date().timeIntervalSince(before))
        reads += 1
        if pressed != wasPressed {
            print(String(format: "%7.2fs  button %@", Date().timeIntervalSince(start), pressed ? "DOWN" : "UP"))
            wasPressed = pressed
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    print(String(format: "%d reads, slowest %.1fms", reads, slowest * 1000))
}

func scan(directory: URL, options: ScanOptions) throws {
    let scanner = SaneScanner()
    try scanner.open()
    var pages: [ScannedPage] = []
    var failure: Error?
    let started = Date()
    do {
        try scanner.scan(
            mode: options.colorMode,
            isCancelled: { false },
            onPageStart: { _ in },
            onPage: { page in
                pages.append(page)
                print("page \(pages.count): \(page.width)x\(page.height)")
            }
        )
    } catch {
        failure = error
    }
    print(String(format: "scanned %d pages in %.1fs", pages.count, Date().timeIntervalSince(started)))
    if !pages.isEmpty {
        let urls = try ScanWriter.write(pages: pages, options: options, directory: directory)
        urls.forEach { print($0.path) }
    }
    if let failure { throw failure }
}

do {
    switch arguments.dropFirst().first {
    case "watch":
        try watchButton(seconds: arguments.count > 2 ? Double(arguments[2]) ?? 30 : 30)
    case "scan" where arguments.count == 6:
        let modes: [String: ColorMode] = ["bw": .blackAndWhite, "gray": .grayscale, "color": .color]
        guard let mode = modes[arguments[3]], let format = OutputFormat(rawValue: arguments[5]) else {
            fallthrough
        }
        try scan(
            directory: URL(fileURLWithPath: arguments[2]),
            options: ScanOptions(colorMode: mode, ocr: arguments[4] == "ocr", format: format)
        )
    default:
        print("usage: scan-check watch [seconds] | scan <output-dir> <bw|gray|color> <ocr|no-ocr> <pdf|jpg>")
        exit(2)
    }
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}
