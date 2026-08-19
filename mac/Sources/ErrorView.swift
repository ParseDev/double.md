import Cocoa

/// Shown in place of the page when a load fails, so an offline launch reads as
/// "can't reach Sentrel" instead of a blank window.
final class ErrorView: NSView {
    private let retry: () -> Void

    init(message: String, retry: @escaping () -> Void) {
        self.retry = retry
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: "Can’t reach Sentrel")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center

        let detail = NSTextField(wrappingLabelWithString: message)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.isSelectable = false

        let button = NSButton(title: "Try Again", target: self, action: #selector(retryTapped))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, detail, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // Painted rather than layer-backed so the colour re-resolves on a light/dark switch.
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Palette.background.setFill()
        dirtyRect.fill()
    }

    @objc private func retryTapped() {
        retry()
    }
}
