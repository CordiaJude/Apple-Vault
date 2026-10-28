import EventKit
import EventKitUI
import PDFKit
import SwiftUI
import UIKit

/// Pinch to zoom and pan, with double-tap to zoom, backed by UIScrollView for
/// the same feel as Photos.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.display(image)
        return view
    }

    func updateUIView(_ uiView: ZoomingScrollView, context: Context) {
        if uiView.imageView.image !== image { uiView.display(image) }
    }

    final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
        let imageView = UIImageView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            showsHorizontalScrollIndicator = false
            showsVerticalScrollIndicator = false
            decelerationRate = .fast
            contentInsetAdjustmentBehavior = .never
            imageView.contentMode = .scaleAspectFit
            imageView.accessibilityIgnoresInvertColors = true
            addSubview(imageView)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            addGestureRecognizer(doubleTap)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func display(_ image: UIImage) {
            imageView.image = image
            zoomScale = 1
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
            if zoomScale == 1 {
                let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
                imageView.frame = CGRect(origin: .zero, size: CGSize(width: image.size.width * fit, height: image.size.height * fit))
                contentSize = imageView.frame.size
                minimumZoomScale = 1
                maximumZoomScale = max(4, 1 / fit)
            }
            centerImage()
        }

        private func centerImage() {
            let x = max((bounds.width - imageView.frame.width) / 2, 0)
            let y = max((bounds.height - imageView.frame.height) / 2, 0)
            contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            if zoomScale > minimumZoomScale {
                setZoomScale(minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let scale = min(maximumZoomScale, 2.5)
                let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
                zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// A multi-page PDF viewer.
struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.backgroundColor = .systemGroupedBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

/// The system share sheet (AirDrop, Messages, Save to Files…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in onComplete() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// The system "New Event" sheet. It needs no calendar permission: the event
/// is only saved if the person taps Add.
struct EventEditView: UIViewControllerRepresentable {
    let title: String
    let date: Date
    let notes: String?
    var onDismiss: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = true
        event.startDate = date
        event.endDate = date
        event.notes = notes
        event.addAlarm(EKAlarm(relativeOffset: -60 * 60 * 24 * 30))
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDismiss: (Bool) -> Void
        init(onDismiss: @escaping (Bool) -> Void) { self.onDismiss = onDismiss }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDismiss(action == .saved)
        }
    }
}
