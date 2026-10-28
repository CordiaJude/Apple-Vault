import Foundation
import UIKit

/// Turns captured pages into a proposed document: recognized text, the
/// detected kind and pre-filled fields. The person always reviews the result
/// before anything is saved.
nonisolated struct ScanAnalysis: Sendable {
    var recognizedText: String
    var extracted: ExtractedDocument
    var usedIntelligence: Bool
}

nonisolated enum ScanPipeline {
    static func analyze(_ sources: [PageSource]) async -> ScanAnalysis {
        var texts: [String] = []
        // The first two pages (front and back) carry nearly all the fields.
        for source in sources.prefix(3) {
            switch source {
            case .image(let image):
                texts.append(await TextRecognizer.recognize(image))
            case .pdf(let data):
                if let embedded = TextRecognizer.embeddedText(ofPDF: data) {
                    texts.append(embedded)
                } else {
                    for image in PDFRendering.pageImages(of: data, maxDimension: 2400, limit: 2) {
                        texts.append(await TextRecognizer.recognize(image))
                    }
                }
            }
        }
        let text = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let mrz = MRZParser.parse(text: text)
        let heuristic = FieldExtractor.extract(from: text, mrz: mrz)

        var result = heuristic
        var usedIntelligence = false
        if let generated = await IntelligenceExtractor.extract(from: text) {
            usedIntelligence = true
            if mrz != nil {
                // The MRZ is authoritative; the model only fills gaps.
                result = heuristic.merged(with: generated)
            } else {
                var primary = generated
                if heuristic.confidence > 0.75 && heuristic.kind != generated.kind && generated.kind == .custom {
                    primary.kind = heuristic.kind
                }
                // Numbers matched by pattern are more reliable than generated ones.
                for key in [FieldKey.documentNumber, .memberID, .groupNumber, .policyNumber, .vin] {
                    if let value = heuristic.values[key] { primary.values[key] = value }
                }
                result = primary.merged(with: heuristic)
            }
        }
        return ScanAnalysis(recognizedText: text, extracted: result, usedIntelligence: usedIntelligence)
    }
}
