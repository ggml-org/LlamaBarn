import AppKit

/// Circular container (28pt) for installed model icons that displays state transitions.
/// The icon itself is 16pt, centered within the container.
/// - Inactive: subtle background, tinted icon
/// - Active: blue background, white icon
/// - Loading: shows spinner in place of icon
/// - Downloading: the icon faded, minus the background, with a progress ring
///   around the rim in the icon's own tint at the icon's own fade -- see
///   `downloadFraction`. Pausing dims the ring below that shared weight.
///
/// The chip is a state display in every one of these; the row's controls all
/// live in its trailing slot.
final class IconView: NSView {
  /// Ring stroke. Runs along the chip's own rim, inset by half the stroke.
  private static let ringLineWidth: CGFloat = 2.5

  /// Icon opacity while a download is in flight. The mark stays legible enough
  /// to identify the model, but reads as "not fully here yet" against the solid
  /// marks of the installed rows around it.
  private static let downloadingIconAlpha: CGFloat = 0.45

  /// Progress-arc opacity while the download is paused -- below the shared
  /// icon/arc weight, but still clear of the track beneath it.
  private static let pausedArcAlpha: CGFloat = 0.25

  /// The image view containing the model icon. Set the `image` property directly.
  let imageView = NSImageView()
  private let spinner = NSProgressIndicator()

  /// Ring layers: a faint full-circle track with a progress arc on top, drawn
  /// with `strokeEnd`. Hidden unless `downloadFraction` is set.
  private let trackLayer = CAShapeLayer()
  private let progressLayer = CAShapeLayer()

  var isActive: Bool = false { didSet { refresh() } }
  private var isLoading: Bool = false { didSet { refresh() } }
  var inactiveTintColor: NSColor = Theme.Colors.textPrimary { didSet { refresh() } }

  var inactiveBackgroundColor: NSColor = Theme.Colors.subtleBackground { didSet { refresh() } }

  /// Download progress in 0...1, or nil when not downloading. Non-nil swaps the
  /// chip into its downloading look: background dropped, ring shown.
  /// The arc floors at a small visible sliver so a just-started download reads
  /// as "a ring beginning to fill" rather than an empty circle.
  var downloadFraction: Double? {
    didSet {
      updateRingProgress()
      // Only rebuild the whole look on show/hide, not on every progress tick.
      if (downloadFraction == nil) != (oldValue == nil) { refresh() }
    }
  }

  /// Whether the download this chip is showing is paused. Dims the progress arc
  /// so a stalled download reads as stalled from the chip alone, without having
  /// to read the subtitle. Ignored while `downloadFraction` is nil.
  var isDownloadPaused: Bool = false {
    didSet { if isDownloadPaused != oldValue { refresh() } }
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

    for shape in [trackLayer, progressLayer] {
      shape.fillColor = nil
      shape.lineWidth = Self.ringLineWidth
      shape.lineCap = .round
      shape.isHidden = true
      layer?.addSublayer(shape)
    }

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

    // Ring path along the rim, inset by half the stroke so it isn't clipped.
    // Start at 12 o'clock and run visually clockwise: in the layer's default
    // (y-up) coordinates that's from π/2 sweeping through decreasing angles.
    let radius = bounds.width / 2 - Self.ringLineWidth / 2
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let path = CGMutablePath()
    path.addArc(
      center: center, radius: radius,
      startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
    trackLayer.frame = bounds
    progressLayer.frame = bounds
    trackLayer.path = path
    progressLayer.path = path
    updateRingProgress()
  }

  private func updateRingProgress() {
    guard let fraction = downloadFraction else { return }
    // Snap to each progress sample instead of trailing behind with an implicit fade.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    progressLayer.strokeEnd = CGFloat(max(0.04, min(1, fraction)))
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
    // Downloading look: ring in place of the chip background, restored the
    // moment the download ends. The icon stays put but fades -- the chip only
    // ever reports state, so the model stays identifiable while it downloads.
    let isDownloading = downloadFraction != nil
    trackLayer.isHidden = !isDownloading
    progressLayer.isHidden = !isDownloading
    trackLayer.setStrokeColor(Theme.Colors.subtleBackground, in: self)
    imageView.alphaValue = isDownloading ? Self.downloadingIconAlpha : 1

    // The arc takes the icon's own tint at the icon's own fade, so ring and mark
    // read as one object at one weight -- the ring is the mark's progress, not a
    // separate indicator competing with it. Pausing drops it below that shared
    // weight, which is what makes a stalled download legible from the chip
    // alone. Opacity rather than a dimmer color keeps the two tied to the icon:
    // a change to `inactiveTintColor` carries to the arc for free.
    progressLayer.setStrokeColor(inactiveTintColor, in: self)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    progressLayer.opacity =
      Float(isDownloadPaused ? Self.pausedArcAlpha : Self.downloadingIconAlpha)
    CATransaction.commit()

    // Spinner appears in the center and the icon hides while loading.
    imageView.isHidden = isLoading
    spinner.isHidden = !isLoading

    if isActive {
      layer.setBackgroundColor(.controlAccentColor, in: self)
      imageView.contentTintColor = .white
      // Spinner always white on blue background regardless of theme
      spinner.appearance = NSAppearance(named: .darkAqua)
    } else {
      layer.setBackgroundColor(isDownloading ? .clear : inactiveBackgroundColor, in: self)
      imageView.contentTintColor = inactiveTintColor
    }
  }
}
