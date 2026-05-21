import AppKit

/// Menu bar button that accepts file drops and forwards clicks.
final class DraggableStatusItemView: NSView {
    var onClick: (() -> Void)?
    var onFileDrop: ((URL) -> Void)?

    private let imageView = NSImageView()

    init(image: NSImage, size: NSSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard fileURL(from: sender) != nil else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = fileURL(from: sender) else { return false }
        onFileDrop?(url)
        return true
    }

    private func fileURL(from info: NSDraggingInfo) -> URL? {
        let pb = info.draggingPasteboard
        guard let items = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], let url = items.first else {
            return nil
        }
        return url
    }
}
