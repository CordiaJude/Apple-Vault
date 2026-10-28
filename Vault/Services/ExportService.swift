import PDFKit
import SwiftUI
import UIKit

/// Builds shareable images and PDFs from documents. Files are written to a
/// protected temporary folder that is emptied whenever Vault locks.
@MainActor
enum ExportService {
    enum Failure: LocalizedError {
        case nothingToExport
        case encryptionFailed

        var errorDescription: String? {
            switch self {
            case .nothingToExport: String(localized: "There’s nothing to export.")
            case .encryptionFailed: String(localized: "The PDF couldn’t be password-protected.")
            }
        }
    }

    // MARK: Single document

    /// The front image (or a rendered card if there is no scan).
    static func image(for document: VaultDocument) throws -> URL {
        let image = document.frontPage?.image() ?? renderCard(document)
        guard let data = image?.jpegData(compressionQuality: 0.92) else { throw Failure.nothingToExport }
        return try SecureFiles.writeTemporary(data, named: fileName(for: document, extension: "jpg"))
    }

    static func pdf(for document: VaultDocument, password: String? = nil) throws -> URL {
        try pdf(for: [document], named: fileName(for: document, extension: "pdf"), password: password)
    }

    // MARK: Many documents

    /// One PDF containing every page and the typed fields of each document.
    static func pdf(for documents: [VaultDocument], named name: String? = nil, password: String? = nil, includeFields: Bool = true) throws -> URL {
        guard !documents.isEmpty else { throw Failure.nothingToExport }
        let data = renderPDF(documents, includeFields: includeFields)
        let output: Data
        if let password, !password.isEmpty {
            guard let document = PDFDocument(data: data),
                  let encrypted = document.dataRepresentation(options: [
                      PDFDocumentWriteOption.userPasswordOption: password,
                      PDFDocumentWriteOption.ownerPasswordOption: password,
                  ])
            else { throw Failure.encryptionFailed }
            output = encrypted
        } else {
            output = data
        }
        let fileName = name ?? String(localized: "Vault Documents.pdf")
        return try SecureFiles.writeTemporary(output, named: fileName)
    }

    private static let pageSize = CGSize(width: 612, height: 792) // US Letter
    private static let margin: CGFloat = 48

    private static func renderPDF(_ documents: [VaultDocument], includeFields: Bool) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            for document in documents {
                context.beginPage()
                var y = drawHeader(for: document, in: context)
                // Front and back side by side on the summary page, like a photocopy.
                let images = [document.frontPage, document.backPage].compactMap { $0 }.filter { !$0.isPDF }.compactMap { $0.image() }
                if !images.isEmpty {
                    y = drawImages(images, top: y)
                }
                if includeFields {
                    y = drawFields(document.payload, top: y + 16, context: context)
                }
                // Then every extra page and PDF page at full size.
                for page in document.sortedPages {
                    if page.isPDF, let data = page.data() {
                        for image in PDFRendering.pageImages(of: data, maxDimension: 1800) {
                            context.beginPage()
                            drawFullPage(image)
                        }
                    } else if page.role == .extra, let image = page.image() {
                        context.beginPage()
                        drawFullPage(image)
                    }
                }
            }
        }
    }

    private static func drawHeader(for document: VaultDocument, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let title = NSAttributedString(string: document.title, attributes: [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.black,
        ])
        title.draw(at: CGPoint(x: margin, y: margin))
        var subtitleParts = [document.kind.name]
        if let person = document.person { subtitleParts.append(person.displayName) }
        if let expires = document.expiresOn { subtitleParts.append(String(localized: "Expires \(expires.formatted(date: .long, time: .omitted))")) }
        let subtitle = NSAttributedString(string: subtitleParts.joined(separator: " · "), attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.darkGray,
        ])
        subtitle.draw(at: CGPoint(x: margin, y: margin + 32))
        return margin + 60
    }

    private static func drawImages(_ images: [UIImage], top: CGFloat) -> CGFloat {
        let available = pageSize.width - margin * 2
        let spacing: CGFloat = 16
        let width = images.count > 1 ? (available - spacing) / 2 : min(available, 360)
        var maxHeight: CGFloat = 0
        for (index, image) in images.prefix(2).enumerated() {
            let height = width * image.size.height / max(image.size.width, 1)
            let rect = CGRect(x: margin + CGFloat(index) * (width + spacing), y: top, width: width, height: min(height, 320))
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
            UIGraphicsGetCurrentContext()?.saveGState()
            path.addClip()
            image.draw(in: rect)
            UIGraphicsGetCurrentContext()?.restoreGState()
            maxHeight = max(maxHeight, rect.height)
        }
        return top + maxHeight + 8
    }

    private static func drawFields(_ payload: DocumentPayload, top: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var y = top
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.gray]
        let valueAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.black]
        for field in payload.fields where !field.isEmpty {
            if y > pageSize.height - margin - 40 {
                context.beginPage()
                y = margin
            }
            NSAttributedString(string: field.label.uppercased(), attributes: labelAttributes).draw(at: CGPoint(x: margin, y: y))
            NSAttributedString(string: field.displayValue, attributes: valueAttributes)
                .draw(in: CGRect(x: margin, y: y + 13, width: pageSize.width - margin * 2, height: 40))
            y += 38
        }
        if !payload.notes.isEmpty {
            if y > pageSize.height - margin - 80 {
                context.beginPage()
                y = margin
            }
            NSAttributedString(string: String(localized: "NOTES"), attributes: labelAttributes).draw(at: CGPoint(x: margin, y: y))
            let rect = CGRect(x: margin, y: y + 13, width: pageSize.width - margin * 2, height: pageSize.height - y - margin - 13)
            NSAttributedString(string: payload.notes, attributes: valueAttributes).draw(in: rect)
        }
        return y
    }

    private static func drawFullPage(_ image: UIImage) {
        let available = CGRect(x: margin / 2, y: margin / 2, width: pageSize.width - margin, height: pageSize.height - margin)
        let scale = min(available.width / image.size.width, available.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height))
    }

    // MARK: Helpers

    static func renderCard(_ document: VaultDocument) -> UIImage? {
        let renderer = ImageRenderer(content:
            CardFace(title: document.title, kind: document.kind, color: document.color, holder: document.person?.displayName, expiresOn: document.expiresOn)
                .frame(width: 540)
                .padding(20)
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    static func fileName(for document: VaultDocument, extension ext: String) -> String {
        let safe = document.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        return (safe.isEmpty ? "Document" : safe) + "." + ext
    }
}
