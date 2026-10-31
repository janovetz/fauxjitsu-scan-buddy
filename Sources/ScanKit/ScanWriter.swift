import CoreGraphics
import CoreText
import Foundation

public enum ScanWriter {
    /// Writes the pages to `directory` and returns the created files: one PDF, or one JPG per page.
    public static func write(
        pages: [ScannedPage],
        options: ScanOptions,
        directory: URL,
        date: Date = Date(),
        onRecognizing: (_ page: Int, _ total: Int) -> Void = { _, _ in }
    ) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = try nextBaseName(directory: directory, date: date)

        switch options.format {
        case .pdf:
            let url = directory.appendingPathComponent(baseName).appendingPathExtension("pdf")
            try writePDF(pages: pages, recognizesText: options.performsOCR, to: url, onRecognizing: onRecognizing)
            return [url]
        case .jpg:
            return try pages.enumerated().map { index, page in
                let name = pages.count > 1 ? String(format: "%@-%03d", baseName, index + 1) : baseName
                let url = directory.appendingPathComponent(name).appendingPathExtension("jpg")
                try page.jpegData().write(to: url)
                return url
            }
        }
    }

    private static func writePDF(
        pages: [ScannedPage],
        recognizesText: Bool,
        to url: URL,
        onRecognizing: (Int, Int) -> Void
    ) throws {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else {
            throw ScanOutputError.writeFailed(url)
        }
        for (index, page) in pages.enumerated() {
            try autoreleasepool {
                let image = try page.cgImage()
                var lines: [RecognizedLine] = []
                if recognizesText {
                    onRecognizing(index + 1, pages.count)
                    lines = try TextRecognizer.recognize(image)
                }

                var mediaBox = CGRect(origin: .zero, size: page.pointSize)
                let boxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
                context.interpolationQuality = .none
                context.draw(image, in: mediaBox)
                drawInvisibleText(lines, pageSize: page.pointSize, in: context)
                context.endPDFPage()
            }
        }
        context.closePDF()
    }

    /// Lays each recognized line over its image so it can be searched and selected but isn't seen.
    private static func drawInvisibleText(_ lines: [RecognizedLine], pageSize: CGSize, in context: CGContext) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for recognized in lines where !recognized.text.isEmpty {
            let box = CGRect(
                x: recognized.box.minX * pageSize.width,
                y: recognized.box.minY * pageSize.height,
                width: recognized.box.width * pageSize.width,
                height: recognized.box.height * pageSize.height
            )
            guard box.width > 0, box.height > 0 else { continue }

            let font = CTFontCreateWithName("Helvetica" as CFString, box.height * 0.8, nil)
            let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: recognized.text, attributes: attributes))
            let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
            guard lineWidth > 0 else { continue }

            context.saveGState()
            context.translateBy(x: box.minX, y: box.minY + CTFontGetDescent(font))
            context.scaleBy(x: box.width / lineWidth, y: 1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// "YYYYMMDD-ScanN", where N follows the highest number already used that day. PDFs and
    /// JPGs share the sequence, and a deleted scan's number isn't reused unless it was the highest.
    private static func nextBaseName(directory: URL, date: Date) throws -> String {
        let prefix = fileDateFormatter.string(from: date) + "-Scan"
        let used = try FileManager.default.contentsOfDirectory(atPath: directory.path).compactMap { name -> Int? in
            guard name.hasPrefix(prefix) else { return nil }
            return Int(name.dropFirst(prefix.count).prefix(while: \.isNumber))
        }
        return "\(prefix)\((used.max() ?? 0) + 1)"
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}
