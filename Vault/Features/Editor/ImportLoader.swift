import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Loads pages from Photos and Files.
enum ImportLoader {
    static func load(items: [PhotosPickerItem]) async -> [PageSource] {
        var sources: [PageSource] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                sources.append(.image(image))
            }
        }
        return sources
    }

    /// Files picked with `fileImporter` are security-scoped.
    static func load(urls: [URL]) -> [PageSource] {
        urls.compactMap { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return source(from: data, type: UTType(filenameExtension: url.pathExtension))
        }
    }

    static func source(from data: Data, type: UTType?) -> PageSource? {
        if type?.conforms(to: .pdf) == true || data.starts(with: Data("%PDF".utf8)) {
            return .pdf(data)
        }
        return UIImage(data: data).map(PageSource.image)
    }
}
