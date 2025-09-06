import AppKit

/// Small circular badge that hosts a template image centered inside.
/// - Inactive: clear background, subtle border, secondary tint.
/// - Active: filled with `controlAccentColor`, no border, white glyph.
final class CircularIconView: NSView {
  let imageView = NSImageView()

  var isActive: Bool = false { didSet { refresh() } }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: MenuMetrics.smallIconSize, weight: .regular)
    imageView.imageScaling = .scaleProportionallyDown

    addSubview(imageView)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.smallIconSize),
      imageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.smallIconSize),
    ])
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  func setImage(_ image: NSImage?) {
    imageView.image = image
    if let img = imageView.image { img.isTemplate = true }
    refresh()
  }

  private func refresh() {
    guard let layer else { return }
    if isActive {
      layer.borderWidth = 0
      layer.backgroundColor = NSColor.cgColor(.controlAccentColor, in: self)
      imageView.contentTintColor = .white
    } else {
      layer.borderWidth = 0
      layer.backgroundColor = NSColor.cgColor(.lbBadgeBackground, in: self)
      // Default (may be overridden by caller for hover emphasis)
      imageView.contentTintColor = .secondaryLabelColor
    }
  }
}
