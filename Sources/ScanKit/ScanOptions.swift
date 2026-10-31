import Foundation

public enum ColorMode: String, Codable, CaseIterable, Sendable {
    case blackAndWhite, grayscale, color

    var saneMode: String {
        switch self {
        case .blackAndWhite: return "Lineart"
        case .grayscale: return "Gray"
        case .color: return "Color"
        }
    }
}

public enum OutputFormat: String, Codable, CaseIterable, Sendable {
    case pdf, jpg
}

public struct ScanOptions: Codable, Equatable, Sendable {
    public var colorMode: ColorMode = .blackAndWhite
    public var ocr: Bool = true
    public var format: OutputFormat = .pdf

    public init(colorMode: ColorMode = .blackAndWhite, ocr: Bool = true, format: OutputFormat = .pdf) {
        self.colorMode = colorMode
        self.ocr = ocr
        self.format = format
    }

    /// OCR only produces a text layer in a PDF; JPGs have nowhere to put it.
    public var performsOCR: Bool { ocr && format == .pdf }
}
