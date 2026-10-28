import Foundation
import SwiftData
import UIKit

/// A page ready to be stored: already downscaled, compressed and encrypted,
/// off the main thread.
nonisolated struct PreparedPage: Sendable {
    var encryptedData: Data
    var encryptedThumbnail: Data?
    var isPDF: Bool
    var pixelSize: CGSize
}

/// Raw material for a page, before preparation.
nonisolated enum PageSource: Sendable {
    case image(UIImage)
    case pdf(Data)

    var previewImage: UIImage? {
        switch self {
        case .image(let image): image
        case .pdf(let data): PDFRendering.firstPageImage(of: data, maxDimension: 1200)
        }
    }
}

nonisolated enum PagePreparer {
    static let maxImageDimension: CGFloat = 3000
    static let thumbnailDimension: CGFloat = 700

    @concurrent
    static func prepare(_ source: PageSource) async throws -> PreparedPage {
        switch source {
        case .image(let image):
            let scaled = image.vaultScaled(maxDimension: maxImageDimension)
            guard let jpeg = scaled.jpegData(compressionQuality: 0.88) else { throw CocoaError(.fileWriteUnknown) }
            let thumb = scaled.vaultScaled(maxDimension: thumbnailDimension).jpegData(compressionQuality: 0.8)
            return PreparedPage(
                encryptedData: try VaultCrypto.seal(jpeg),
                encryptedThumbnail: try thumb.map(VaultCrypto.seal),
                isPDF: false,
                pixelSize: CGSize(width: scaled.size.width * scaled.scale, height: scaled.size.height * scaled.scale)
            )
        case .pdf(let data):
            let preview = PDFRendering.firstPageImage(of: data, maxDimension: thumbnailDimension)
            return PreparedPage(
                encryptedData: try VaultCrypto.seal(data),
                encryptedThumbnail: try preview?.jpegData(compressionQuality: 0.8).map(VaultCrypto.seal),
                isPDF: true,
                pixelSize: preview.map { CGSize(width: $0.size.width, height: $0.size.height) } ?? CGSize(width: 612, height: 792)
            )
        }
    }
}

extension DocumentPage {
    convenience init(prepared: PreparedPage, role: PageRole, index: Int) {
        self.init(role: role, index: index)
        encryptedData = prepared.encryptedData
        encryptedThumbnail = prepared.encryptedThumbnail
        isPDF = prepared.isPDF
        pixelWidth = prepared.pixelSize.width
        pixelHeight = prepared.pixelSize.height
    }
}

extension UIImage {
    nonisolated func vaultScaled(maxDimension: CGFloat) -> UIImage {
        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension else { return normalizedOrientation() }
        let factor = maxDimension / longest
        let target = CGSize(width: (pixelWidth * factor).rounded(), height: (pixelHeight * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    nonisolated func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
