import AppKit

/// Circular container (28pt) for catalog model icons with outline border.
/// The icon itself remains 16pt, centered within the container.
/// Unlike IconView, this is non-interactive with no state transitions.
final class CatalogIconView: NSView {
  /// The image view containing the model icon. Set the `image` property directly.
  let imageView = NSImageView()

  var isHighlighted: Bool = false { didSet { refresh() } }
  var backgroundColor: NSColor = .lbSubtleBackground { didSet { refresh() } }

  override init(frame frameRect: NSRect = .zero) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: Layout.uiIconSize, weight: .regular)
    imageView.contentTintColor = Typography.primaryColor

    addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
      imageView.heightAnchor.constraint(lessThanOrEqualToConstant: Layout.uiIconSize),
    ])
    refresh()
  }

  override func layout() {
    super.layout()
    // Make circular by setting corner radius to half the view's size
    layer?.cornerRadius = bounds.width / 2
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  private func refresh() {
    guard let layer else { return }
    layer.setBackgroundColor(backgroundColor, in: self)
  }
}
