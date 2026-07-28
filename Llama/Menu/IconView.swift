import AppKit

/// Circular container (28pt) for installed model icons that displays state transitions.
/// The icon itself is 16pt, centered within the container.
/// - Inactive: subtle background, tinted icon
/// - Active: blue background, white icon
/// - Loading: shows spinner in place of icon
/// - Downloading: the icon faded over an empty container that fills from the
///   bottom up as the file lands, arriving at exactly the inactive look above
///   -- see `downloadFraction`. The chip's full height is the meter, so progress
///   reads at a glance and moves on small increments; the circle also keeps the
///   fill's shape independent of the mark's. Live and paused look alike here --
///   the row's trailing play/pause glyph and its subtitle both say which, and
///   the level itself means the same either way.
///
/// The chip is a state display in every one of these; the row's controls all
/// live in its trailing slot.
final class IconView: NSView {
  /// Icon opacity while a download is in flight. The mark stays legible enough
  /// to identify the model, but reads as "not fully here yet" against the solid
  /// marks of the installed rows around it.
  private static let downloadingIconAlpha: CGFloat = 0.45


  private let imageView = NSImageView()
  private let spinner = NSProgressIndicator()

  /// The rising level: a bottom-anchored slice of the chip, clipped to the
  /// circle by the view's own `masksToBounds`. Sits below the icon and draws in
  /// the chip's ordinary background color, with the chip's own background
  /// switched off meanwhile -- so the level rises toward the installed look
  /// rather than past it, and a completed download changes nothing about the
  /// circle. Anything darker would make finishing read as a step backwards.
  private let fillLayer = CALayer()

  /// The model icon. The view owns its own layering, so callers set the image
  /// rather than reaching for the image view.
  var image: NSImage? {
    didSet { imageView.image = image }
  }

  var isActive: Bool = false { didSet { refresh() } }
  private var isLoading: Bool = false { didSet { refresh() } }
  var inactiveTintColor: NSColor = Theme.Colors.textPrimary { didSet { refresh() } }

  var inactiveBackgroundColor: NSColor = Theme.Colors.subtleBackground { didSet { refresh() } }

  /// Download progress in 0...1, or nil when not downloading. Non-nil fades the
  /// mark and raises the fill to `fraction` of the chip's height. No floor: a
  /// download that has barely started shows an empty chip, which is honest --
  /// the row's subtitle carries the exact byte count.
  var downloadFraction: Double? {
    didSet {
      updateFillProgress()
      // Only rebuild the whole look on show/hide, not on every progress tick.
      if (downloadFraction == nil) != (oldValue == nil) { refresh() }
    }
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: Layout.iconViewSize, height: Layout.iconViewSize)
  }

  override init(frame frameRect: NSRect = .zero) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.symbolConfiguration = .init(pointSize: Layout.uiIconSize, weight: .regular)

    // Clip the fill to the circle. Added before the subviews so it sits behind
    // the icon: subview layers land above sublayers added here.
    layer?.masksToBounds = true
    fillLayer.isHidden = true
    layer?.addSublayer(fillLayer)

    // Configure spinner but keep it hidden until used.
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false
    spinner.controlSize = .small
    spinner.style = .spinning

    addSubview(imageView)
    addSubview(spinner)
    NSLayoutConstraint.activate([
      // Container is fixed at iconViewSize so it can't be squeezed when long titles
      // or hover buttons compete for row width. Intrinsic size alone isn't enough —
      // NSStackView will compress views with default priorities mid-animation.
      widthAnchor.constraint(equalToConstant: Layout.iconViewSize),
      heightAnchor.constraint(equalToConstant: Layout.iconViewSize),
      imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
      imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
      imageView.widthAnchor.constraint(equalToConstant: Layout.uiIconSize),
      imageView.heightAnchor.constraint(equalToConstant: Layout.uiIconSize),
      spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    refresh()
  }

  override func layout() {
    super.layout()
    // Make circular by setting corner radius to half the view's size
    layer?.cornerRadius = bounds.width / 2
  }

  /// Sizes the fill to the downloaded fraction of the chip's height, anchored at
  /// the bottom so the level rises. The circle clips the corners for free.
  private func updateFillProgress() {
    guard let fraction = downloadFraction else { return }
    // Sized off the layout constant rather than `bounds`, which is still zero
    // the first time through -- the fill would start empty and only appear on
    // the next progress tick.
    let side = Layout.iconViewSize
    // Snap to each progress sample instead of trailing behind with an implicit fade.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fillLayer.frame = CGRect(
      x: 0, y: 0,
      width: side,
      height: side * CGFloat(max(0, min(1, fraction))))
    CATransaction.commit()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refresh()
  }

  /// Show or hide a spinner centered in place of the icon.
  func setLoading(_ loading: Bool) {
    isLoading = loading
    if loading {
      spinner.startAnimation(nil)
    } else {
      spinner.stopAnimation(nil)
    }
  }

  private func refresh() {
    guard let layer else { return }
    // Downloading look: the mark fades and the chip fills from the bottom up as
    // the file lands. The model stays identifiable throughout -- the chip only
    // ever reports state.
    let isDownloading = downloadFraction != nil
    imageView.alphaValue = isDownloading ? Self.downloadingIconAlpha : 1
    fillLayer.isHidden = !isDownloading

    // Spinner appears in the center and the icon hides while loading.
    imageView.isHidden = isLoading
    spinner.isHidden = !isLoading

    // While downloading, the chip's own background steps aside and the fill
    // supplies it a slice at a time -- see `fillLayer`.
    if isActive {
      layer.setBackgroundColor(.controlAccentColor, in: self)
      imageView.contentTintColor = .white
      // Spinner always white on blue background regardless of theme
      spinner.appearance = NSAppearance(named: .darkAqua)
    } else {
      layer.setBackgroundColor(isDownloading ? .clear : inactiveBackgroundColor, in: self)
      imageView.contentTintColor = inactiveTintColor
    }

    // Set here rather than in `init` so the fill follows a light/dark switch,
    // and any change to `inactiveBackgroundColor`, the way the chip does.
    fillLayer.setBackgroundColor(inactiveBackgroundColor, in: self)
  }
}
