import PDFKit
import UIKit

nonisolated enum PDFRendering {
    /// Renders the first page of a PDF as an image (for card faces and OCR).
    static func firstPageImage(of data: Data, maxDimension: CGFloat = 2000) -> UIImage? {
        pageImages(of: data, maxDimension: maxDimension, limit: 1).first
    }

    static func pageImages(of data: Data, maxDimension: CGFloat = 2000, limit: Int = .max) -> [UIImage] {
        guard let document = PDFDocument(data: data) else { return [] }
        return (0..<min(document.pageCount, limit)).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = maxDimension / max(bounds.width, bounds.height, 1)
            return page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        }
    }

    static func pageCount(of data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }
}
