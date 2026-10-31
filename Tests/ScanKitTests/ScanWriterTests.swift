import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing
@testable import ScanKit

private let dpi = 300
private let pageWidth = 2550
private let pageHeight = 3300
private let bodyText = "The quick brown fox jumps over the lazy dog"

/// A Letter page of black text on white, returned as 8-bit gray rows.
private func renderGrayPage(text: String = bodyText) throws -> Data {
    var pixels = Data(repeating: 0xFF, count: pageWidth * pageHeight)
    try pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
        guard let context = CGContext(
            data: buffer.baseAddress, width: pageWidth, height: pageHeight, bitsPerComponent: 8,
            bytesPerRow: pageWidth, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw ScanOutputError.encodingFailed }
        let font = CTFontCreateWithName("Times New Roman" as CFString, 50, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font]))
        context.textPosition = CGPoint(x: 300, y: 2400)
        CTLineDraw(line, context)
    }
    return pixels
}

private func bilevelPage(text: String = bodyText) throws -> ScannedPage {
    let gray = try renderGrayPage(text: text)
    let bytesPerRow = (pageWidth + 7) / 8
    var bits = Data(repeating: 0, count: bytesPerRow * pageHeight)
    for y in 0..<pageHeight {
        for x in 0..<pageWidth where gray[y * pageWidth + x] > 127 {
            bits[y * bytesPerRow + x / 8] |= UInt8(0x80 >> (x % 8))
        }
    }
    return ScannedPage(bilevel: bits, width: pageWidth, height: pageHeight, bytesPerRow: bytesPerRow, dpi: dpi)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

private func darkPixelCount(_ page: PDFPage, width: Int, height: Int) throws -> Int {
    var pixels = [UInt8](repeating: 0xFF, count: width * height)
    return try pixels.withUnsafeMutableBytes { buffer -> Int in
        guard let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { throw ScanOutputError.encodingFailed }
        let bounds = page.bounds(for: .mediaBox)
        context.scaleBy(x: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height)
        page.draw(with: .mediaBox, to: context)
        return buffer.filter { $0 < 128 }.count
    }
}

@Test func bilevelPDFWithOCRIsSearchableAtTheTextsPosition() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let urls = try ScanWriter.write(pages: [try bilevelPage()], options: ScanOptions(), directory: directory)

    let document = try #require(PDFDocument(url: urls[0]))
    #expect(document.pageCount == 1)
    let page = try #require(document.page(at: 0))
    #expect(abs(page.bounds(for: .mediaBox).width - 612) < 0.5)
    #expect(abs(page.bounds(for: .mediaBox).height - 792) < 0.5)
    #expect(page.string?.contains("quick brown fox") == true)

    // The text was drawn with its baseline at y=2400 of 3300 pixels, starting at x=300.
    let match = try #require(document.findString("quick", withOptions: .caseInsensitive).first)
    let bounds = match.bounds(for: page)
    #expect(abs(bounds.midY - (2400.0 / 300 * 72 + 5)) < 12)
    #expect(bounds.minX > 300.0 / 300 * 72)
    #expect(bounds.minX < 300.0 / 300 * 72 + 60)
}

@Test func textLayerIsInvisible() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = try bilevelPage()
    let withText = try ScanWriter.write(pages: [page], options: ScanOptions(), directory: directory.appendingPathComponent("a"))
    let without = try ScanWriter.write(
        pages: [page], options: ScanOptions(ocr: false), directory: directory.appendingPathComponent("b"))

    let ocrDocument = try #require(PDFDocument(url: withText[0]))
    let plainDocument = try #require(PDFDocument(url: without[0]))
    let ocrPage = try #require(ocrDocument.page(at: 0))
    let plainPage = try #require(plainDocument.page(at: 0))
    #expect(plainPage.string?.isEmpty != false)

    let ocrDark = try darkPixelCount(ocrPage, width: pageWidth, height: pageHeight)
    let plainDark = try darkPixelCount(plainPage, width: pageWidth, height: pageHeight)
    #expect(plainDark > 1000, "the page should render with visible black text")
    #expect(ocrDark == plainDark)
}

@Test func grayPDFEmbedsTheJPEGWithoutRecompressing() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = try ScannedPage(
        pixels: try renderGrayPage(), width: pageWidth, height: pageHeight, bytesPerRow: pageWidth, dpi: dpi,
        isColor: false)
    let urls = try ScanWriter.write(
        pages: [page], options: ScanOptions(colorMode: .grayscale, ocr: true), directory: directory)

    let data = try Data(contentsOf: urls[0])
    #expect(data.range(of: Data("/DCTDecode".utf8)) != nil)
    let document = try #require(PDFDocument(url: urls[0]))
    #expect(document.page(at: 0)?.string?.contains("quick brown fox") == true)
}

@Test func colorPageRoundTrips() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (width, height) = (600, 400)
    var pixels = Data(count: width * height * 3)
    for offset in stride(from: 0, to: pixels.count, by: 3) {
        pixels[offset] = 220
        pixels[offset + 1] = 30
        pixels[offset + 2] = 40
    }
    let page = try ScannedPage(pixels: pixels, width: width, height: height, bytesPerRow: width * 3, dpi: dpi, isColor: true)
    let urls = try ScanWriter.write(
        pages: [page], options: ScanOptions(colorMode: .color, format: .jpg), directory: directory)

    let image = try #require(NSImage(contentsOf: urls[0])?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(image.width == width)
    let color = try #require(NSBitmapImageRep(cgImage: image).colorAt(x: 300, y: 200)?.usingColorSpace(.deviceRGB))
    #expect(color.redComponent > 0.7 && color.greenComponent < 0.3)
}

@Test func jpgOutputWritesOneFilePerPageAndOmitsOCR() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = try bilevelPage()
    var recognized = 0
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let urls = try ScanWriter.write(
        pages: [page, page], options: ScanOptions(format: .jpg), directory: directory, date: date,
        onRecognizing: { _, _ in recognized += 1 })

    #expect(urls.count == 2)
    #expect(urls[0].lastPathComponent.hasSuffix("-Scan1-001.jpg"))
    #expect(urls[1].lastPathComponent.hasSuffix("-Scan1-002.jpg"))
    #expect(recognized == 0)

    let source = try #require(CGImageSourceCreateWithURL(urls[0] as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == pageWidth)
    #expect(properties[kCGImagePropertyDPIWidth] as? Int == dpi)
}

@Test func fileNumbersCountUpWithinADayAcrossFormatsAndRestartTheNextDay() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let page = try bilevelPage()
    let pdf = ScanOptions(ocr: false)
    let jpg = ScanOptions(format: .jpg)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12)))
    let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))

    func names(_ options: ScanOptions, pages: Int = 1, date: Date) throws -> [String] {
        try ScanWriter.write(
            pages: Array(repeating: page, count: pages), options: options, directory: directory, date: date
        ).map(\.lastPathComponent)
    }

    #expect(try names(pdf, date: day) == ["20261031-Scan1.pdf"])
    #expect(try names(pdf, date: day) == ["20261031-Scan2.pdf"])
    #expect(try names(jpg, date: day) == ["20261031-Scan3.jpg"])
    #expect(try names(jpg, pages: 2, date: day) == ["20261031-Scan4-001.jpg", "20261031-Scan4-002.jpg"])
    #expect(try names(pdf, date: day) == ["20261031-Scan5.pdf"])
    #expect(try names(pdf, date: nextDay) == ["20261101-Scan1.pdf"])

    // Double digits must compare as numbers, and gaps below the highest aren't reused.
    try Data().write(to: directory.appendingPathComponent("20261031-Scan10.pdf"))
    try FileManager.default.removeItem(at: directory.appendingPathComponent("20261031-Scan2.pdf"))
    #expect(try names(pdf, date: day) == ["20261031-Scan11.pdf"])
}

@Test func ocrIsSkippedForJPGOutput() {
    #expect(ScanOptions().performsOCR)
    #expect(!ScanOptions(ocr: false).performsOCR)
    #expect(!ScanOptions(ocr: true, format: .jpg).performsOCR)
}
