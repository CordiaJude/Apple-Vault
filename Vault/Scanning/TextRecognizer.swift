import PDFKit
import UIKit
import Vision

/// On-device text recognition with Vision. Uses iOS 26's document
/// recognition (which understands layout, paragraphs and tables), plus a
/// second pass without language correction so MRZ lines stay exact.
nonisolated enum TextRecognizer {
    @concurrent
    static func recognize(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        async let documentText = documentTranscript(cgImage)
        async let rawLines = literalLines(cgImage)
        let (document, raw) = await (documentText, rawLines)
        // Keep MRZ-looking lines from the literal pass; they matter character by character.
        let mrzLines = raw.filter { MRZParser.normalize($0).count >= 28 && $0.contains("<") }
        return ([document.isEmpty ? raw.joined(separator: "\n") : document] + mrzLines).joined(separator: "\n")
    }

    /// Text already embedded in a PDF, if it has a text layer.
    static func embeddedText(ofPDF data: Data) -> String? {
        let text = PDFDocument(data: data)?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.count ?? 0) > 20 ? text : nil
    }

    private static func documentTranscript(_ image: CGImage) async -> String {
        do {
            let request = RecognizeDocumentsRequest()
            let observations = try await request.perform(on: image)
            return observations.map { observation in
                let lines = observation.document.text.lines.compactMap { $0.topCandidates(1).first?.string }
                return lines.isEmpty ? observation.document.text.transcript : lines.joined(separator: "\n")
            }.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    private static func literalLines(_ image: CGImage) async -> [String] {
        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let observations = try await request.perform(on: image)
            return observations.compactMap { $0.topCandidates(1).first?.string }
        } catch {
            return []
        }
    }
}
