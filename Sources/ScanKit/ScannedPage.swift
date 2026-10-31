import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ScanOutputError: LocalizedError {
    case encodingFailed
    case writeFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed: return "The scanned image could not be encoded."
        case .writeFailed(let url): return "Could not write \(url.lastPathComponent)."
        }
    }
}

/// One scanned side of a sheet. Grayscale and color pages are JPEG-compressed as soon as
/// they arrive, so a long color job doesn't hold gigabytes of raw pixels in memory.
public struct ScannedPage: Sendable {
    private enum Storage: Sendable {
        case bilevel(Data, bytesPerRow: Int)
        case jpeg(Data)
    }

    public let width: Int
    public let height: Int
    public let dpi: Int
    private let storage: Storage

    static let jpegQuality = 0.8

    /// `pixels` holds 1-bit rows, MSB first, with set bits white.
    public init(bilevel pixels: Data, width: Int, height: Int, bytesPerRow: Int, dpi: Int) {
        self.width = width
        self.height = height
        self.dpi = dpi
        storage = .bilevel(pixels, bytesPerRow: bytesPerRow)
    }

    /// `pixels` holds 8-bit gray rows, or interleaved 8-bit RGB rows when `isColor` is set.
    public init(pixels: Data, width: Int, height: Int, bytesPerRow: Int, dpi: Int, isColor: Bool) throws {
        let image = try Self.makeImage(
            pixels, width: width, height: height, bitsPerPixel: isColor ? 24 : 8,
            bytesPerRow: bytesPerRow, isColor: isColor
        )
        self.width = width
        self.height = height
        self.dpi = dpi
        storage = .jpeg(try Self.encodeJPEG(image, dpi: dpi, quality: Self.jpegQuality))
    }

    /// Page size in PDF points.
    public var pointSize: CGSize {
        CGSize(width: CGFloat(width) * 72 / CGFloat(dpi), height: CGFloat(height) * 72 / CGFloat(dpi))
    }

    public func cgImage() throws -> CGImage {
        switch storage {
        case .bilevel(let data, let bytesPerRow):
            return try Self.makeImage(
                data, width: width, height: height, bitsPerPixel: 1, bytesPerRow: bytesPerRow, isColor: false
            )
        case .jpeg(let data):
            // Built from the JPEG provider so Quartz can embed the original bytes in a PDF
            // rather than recompressing them.
            guard let provider = CGDataProvider(data: data as CFData),
                  let image = CGImage(
                    jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                    intent: .defaultIntent)
            else { throw ScanOutputError.encodingFailed }
            return image
        }
    }

    public func jpegData() throws -> Data {
        switch storage {
        case .jpeg(let data):
            return data
        case .bilevel:
            // JPEG has no 1-bit form, so expand to 8-bit gray first.
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { throw ScanOutputError.encodingFailed }
            context.interpolationQuality = .none
            context.draw(try cgImage(), in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let image = context.makeImage() else { throw ScanOutputError.encodingFailed }
            return try Self.encodeJPEG(image, dpi: dpi, quality: 0.9)
        }
    }

    private static func makeImage(
        _ pixels: Data, width: Int, height: Int, bitsPerPixel: Int, bytesPerRow: Int, isColor: Bool
    ) throws -> CGImage {
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width, height: height,
                bitsPerComponent: isColor ? 8 : bitsPerPixel, bitsPerPixel: bitsPerPixel,
                bytesPerRow: bytesPerRow,
                space: isColor ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw ScanOutputError.encodingFailed }
        return image
    }

    private static func encodeJPEG(_ image: CGImage, dpi: Int, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ScanOutputError.encodingFailed }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ScanOutputError.encodingFailed }
        return output as Data
    }
}
