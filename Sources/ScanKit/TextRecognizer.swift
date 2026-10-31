import CoreGraphics
import Foundation
import Vision

public struct RecognizedLine: Sendable, Equatable {
    public let text: String
    /// Normalized to the page, with the origin at the lower left.
    public let box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

public enum TextRecognizer {
    public static func recognize(_ image: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return RecognizedLine(text: text, box: observation.boundingBox)
        }
    }
}
