import AppKit
import Foundation

/// Interactive menu item representing a single installed model.
/// Visual states:
/// - Idle: circular icon (inactive) + label
/// - Loading: circular icon (active)
/// - Running: circular icon (active)
final class InstalledModelItemView: ItemView, NSGestureRecognizerDelegate {
  private let model: CatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: Manager
  private let membershipChanged: (CatalogEntry) -> Void

  // Subviews
  private let circleIcon = IconBadgeView()
  private let modelNameLabel = NSTextField(labelWithString: "")
  private let metadataLabel = NSTextField(labelWithString: "")
  private let progressLabel = NSTextField(labelWithString: "")
  private let cancelImageView = NSImageView()
  private let deleteImageView = NSImageView()

  // Hover handling is provided by MenuItemView
  private var rowClickRecognizer: NSClickGestureRecognizer?
  private var deleteClickRecognizer: NSClickGestureRecognizer?

  init(
    model: CatalogEntry, server: LlamaServer, modelManager: Manager,
    membershipChanged: @escaping (CatalogEntry) -> Void
  ) {
    self.model = model
    self.server = server
    self.modelManager = modelManager
    self.membershipChanged = membershipChanged
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 40) }

  private func setup() {
    wantsLayer = true
    circleIcon.setImage(NSImage(named: model.icon))

    modelNameLabel.stringValue = makeTitle()
    modelNameLabel.font = Typography.primary

    // Configure metadata label (second line showing size, context, memory)
    // Contains all metadata fields in a single attributed string (e.g., "📦 2.53 GB · 🧠 84k")
    metadataLabel.font = Typography.secondary

    progressLabel.font = Typography.secondary
    progressLabel.alignment = .right

    configureImageView(cancelImageView, symbol: "xmark", pointSize: 12, color: .systemRed)
    configureImageView(deleteImageView, symbol: "trash", pointSize: 12, color: .labelColor)

    // Spacer expands so trailing visuals sit flush right.
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    modelNameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    modelNameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    progressLabel.setContentHuggingPriority(.required, for: .horizontal)
    progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    // Left: icon aligned with first text line, then two-line text column
    let nameStack = NSStackView(views: [modelNameLabel, metadataLabel])
    nameStack.orientation = .vertical
    nameStack.spacing = 1
    nameStack.alignment = .leading

    let leading = NSStackView(views: [circleIcon, nameStack])
    leading.orientation = .horizontal
    // Vertically center the circular icon relative to the two-line text, like Wi‑Fi menu
    leading.alignment = .centerY
    leading.spacing = 6

    // Right: status/progress/delete/action in a row
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

    let rightStack = NSStackView(views: [progressLabel, cancelImageView, deleteImageView])
    rightStack.orientation = .horizontal
    rightStack.spacing = 6
    rightStack.alignment = .centerY

    let rootStack = NSStackView(views: [leading, spacer, rightStack])
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    rootStack.orientation = .horizontal
    rootStack.spacing = 6
    rootStack.alignment = .centerY
    contentView.addSubview(rootStack)

    NSLayoutConstraint.activate([
      circleIcon.widthAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      circleIcon.heightAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      cancelImageView.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.iconSize),
      cancelImageView.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.iconSize),
      deleteImageView.widthAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      deleteImageView.heightAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),

      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.progressWidth),
      rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      // Pin trailing controls to the backgroundView’s edge (hover highlight),
      // not the contentView’s inner padding, so the trash icon visually
      // reaches the end of the item.
      // Respect the item’s standard inner padding so the trash aligns
      // consistently with other rows.
      rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  // Row click recognizer to toggle, letting the delete icon handle its own action.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if rowClickRecognizer == nil {
      let click = NSClickGestureRecognizer(target: self, action: #selector(didClickRow))
      click.delegate = self
      addGestureRecognizer(click)
      rowClickRecognizer = click
    }
    if deleteClickRecognizer == nil {
      let click = NSClickGestureRecognizer(target: self, action: #selector(didClickDelete))
      deleteImageView.addGestureRecognizer(click)
      deleteClickRecognizer = click
    }
  }

  @objc private func didClickRow() { toggle() }

  @objc private func didClickDelete() { performDelete() }

  // Prevent row toggle when clicking the delete icon.
  func gestureRecognizer(
    _ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent
  ) -> Bool {
    let loc = event.locationInWindow
    let localPoint = deleteImageView.convert(loc, from: nil)
    if deleteImageView.bounds.contains(localPoint) && !deleteImageView.isHidden {
      return false
    }
    return true
  }

  private func toggle() {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .downloaded:
      if server.isActive(model: model) { server.stop() } else { server.start(model: model) }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged(model)
    case .available:
      break
    }
    refresh()
  }

  override func hoverHighlightDidChange(_ highlighted: Bool) {
    let status = modelManager.getModelStatus(model)
    deleteImageView.isHidden = !(highlighted && status == .downloaded)
  }

  func refresh() {
    let status = modelManager.getModelStatus(model)
    let isActive = server.isActive(model: model)
    let isServerLoading = isActive && server.isLoading
    let isRunning = isActive && server.isRunning

    // Update icon state
    circleIcon.setLoading(isServerLoading)
    circleIcon.isActive = isRunning
    circleIcon.imageView.contentTintColor = .labelColor

    // Build info text based on state
    switch status {
    case .downloading(let progress):
      cancelImageView.isHidden = false
      let percent =
        progress.totalUnitCount > 0
        ? Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
        : 0
      progressLabel.stringValue = "\(percent)%"

      let completedSizeText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      let totalBytes = progress.totalUnitCount > 0 ? progress.totalUnitCount : model.fileSize
      let totalSizeText = ByteFormatters.gbTwoDecimals(totalBytes)

      metadataLabel.attributedStringValue = MetadataLabel.make(
        icon: MetadataLabel.sizeSymbol,
        text: "\(completedSizeText) / \(totalSizeText)"
      )

    case .downloaded, .available:
      cancelImageView.isHidden = true
      progressLabel.stringValue = ""
      metadataLabel.attributedStringValue = buildInfoText(isRunning: isRunning)
    }

    needsDisplay = true
  }

  /// Build the info line with size, context, and optionally memory usage.
  private func buildInfoText(isRunning: Bool) -> NSAttributedString {
    let result = NSMutableAttributedString()

    result.append(MetadataLabel.make(icon: MetadataLabel.sizeSymbol, text: model.totalSize))

    if let recommendedContext = Catalog.recommendedContextLength(for: model) {
      result.append(MetadataLabel.makeSeparator())
      result.append(
        MetadataLabel.make(
          icon: MetadataLabel.contextSymbol,
          text: TokenFormatters.shortTokens(recommendedContext)
        ))
    }

    if isRunning, let memoryText = formatMemory(server.memoryUsageMB) {
      result.append(MetadataLabel.makeSeparator())
      result.append(MetadataLabel.make(icon: MetadataLabel.memorySymbol, text: memoryText))
    }

    return result
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
    deleteImageView.contentTintColor = .labelColor
  }

  @objc private func performDelete() {
    let status = modelManager.getModelStatus(model)
    guard case .downloaded = status else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged(model)
  }

  private func makeTitle() -> String {
    var title = model.displayName
    if !model.isFullPrecision,
      let quantLabel = QuantizationFormatters.short(model.quantization).nilIfEmpty
    {
      title += "-\(quantLabel)"
    }
    return title
  }

  private func configureImageView(
    _ imageView: NSImageView, symbol: String, pointSize: CGFloat, color: NSColor
  ) {
    if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
      img.isTemplate = true
      imageView.image = img
    }
    imageView.symbolConfiguration = .init(pointSize: pointSize, weight: .regular)
    imageView.contentTintColor = color
    imageView.isHidden = true
  }

  private func formatMemory(_ memMB: Double) -> String? {
    guard memMB > 0 else { return nil }
    if memMB >= 1024 {
      let gb = memMB / 1024
      return gb < 10 ? String(format: "%.1f GB", gb) : String(format: "%.0f GB", gb)
    }
    return String(format: "%.0f MB", memMB)
  }
}
