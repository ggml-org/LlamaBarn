import AppKit
import Foundation

/// Interactive menu item for a downloadable model build inside a family submenu.
final class CatalogModelItemView: ItemView {
  private let model: CatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let statusIndicator = NSImageView()
  private let labelField = Typography.makePrimaryLabel()
  private let metadataLabel = Typography.makeSecondaryLabel()
  private let progressLabel = Typography.makeSecondaryLabel()
  private var rowClickRecognizer: NSClickGestureRecognizer?
  // Background handled by MenuItemView

  // Hover handling provided by MenuItemView

  init(
    model: CatalogEntry, modelManager: ModelManager, membershipChanged: @escaping () -> Void
  ) {
    self.model = model
    self.modelManager = modelManager
    self.membershipChanged = membershipChanged
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 40) }

  // Only allow highlight for actionable rows (available/compatible or downloading).
  override var highlightEnabled: Bool {
    let status = modelManager.status(for: model)
    switch status {
    case .available:
      return Catalog.isModelCompatible(model)
    case .downloading:
      return true
    case .installed:
      return false
    }
  }

  private func setup() {
    wantsLayer = true
    statusIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    progressLabel.alignment = .right

    // Two-line text column (title + metadata)
    let textColumn = NSStackView(views: [labelField, metadataLabel])
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = 1

    // Leading group aligns status icon with first line of text
    let leading = NSStackView(views: [statusIndicator, textColumn])
    leading.orientation = .horizontal
    leading.alignment = .top
    leading.spacing = 6

    // Main horizontal row with flexible space and trailing progress label
    let hStack = NSStackView(views: [leading, NSView(), progressLabel])
    hStack.translatesAutoresizingMaskIntoConstraints = false
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      statusIndicator.widthAnchor.constraint(equalToConstant: Layout.smallIconSize),
      statusIndicator.heightAnchor.constraint(equalToConstant: Layout.smallIconSize),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.progressWidth),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard rowClickRecognizer == nil else { return }

    let click = NSClickGestureRecognizer(target: self, action: #selector(didClickRow(_:)))
    click.buttonMask = 0x1  // Left mouse button only
    addGestureRecognizer(click)
    rowClickRecognizer = click
  }

  @objc private func didClickRow(_ recognizer: NSClickGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    let location = recognizer.location(in: self)
    guard bounds.contains(location) else { return }
    guard highlightEnabled else { return }
    handleAction()
    refresh()
  }

  private func handleAction() {
    let status = modelManager.status(for: model)
    switch status {
    case .available:
      // The `highlightEnabled` check already covers compatibility, but we could also check here.
      do {
        try modelManager.downloadModel(model)
        membershipChanged()
      } catch {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.localizedDescription
        if let error = error as? LocalizedError, let recoverySuggestion = error.recoverySuggestion {
          alert.informativeText = recoverySuggestion
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged()
    case .installed:
      break
    }
  }

  func refresh() {
    let status = modelManager.status(for: model)
    let compatible = Catalog.isModelCompatible(model)
    let usableCtx = Catalog.usableCtxWindow(for: model)

    // Title and basic display
    labelField.stringValue = model.fullName

    // Metadata text (second line)
    if compatible {
      metadataLabel.attributedStringValue = ModelMetadataFormatters.makeMetadataText(for: model)
    } else {
      metadataLabel.attributedStringValue = NSAttributedString(
        string: "Won't run on this device.",
        attributes: Typography.tertiaryAttributes
      )
    }

    // Tooltips
    let infoTooltip: String? =
      compatible
      ? nil
      : (Catalog.incompatibilitySummary(model) ?? "not compatible")

    let warningTooltip: String? =
      if compatible, let ctx = usableCtx, ctx < model.ctxWindow {
        "Can run at reduced context window"
      } else {
        nil
      }

    metadataLabel.toolTip =
      [infoTooltip, warningTooltip]
      .compactMap { $0 }
      .joined(separator: "\n")
      .nilIfEmpty

    // Status-specific display
    let symbolName: String
    let rowTooltip: String?
    let progressText: String?

    switch status {
    case .installed:
      symbolName = "checkmark.circle"
      rowTooltip = "Already installed"
      progressText = nil

    case .downloading(let progress):
      symbolName = "arrow.down.circle"
      rowTooltip = nil
      progressText = ProgressFormatters.percentText(progress)

    case .available:
      symbolName = compatible ? "arrow.down.circle" : "nosign"
      rowTooltip = nil
      progressText = nil
    }

    statusIndicator.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    toolTip = rowTooltip
    progressLabel.stringValue = progressText ?? ""

    // Colors: tertiary for non-selectable items (incompatible/installed), primary otherwise
    let itemColor: NSColor =
      if compatible && status != .installed {
        Typography.primaryColor
      } else {
        Typography.tertiaryColor
      }
    labelField.textColor = itemColor
    statusIndicator.contentTintColor = itemColor

    // Override attributed text colors for installed models
    if case .installed = status,
      let current = metadataLabel.attributedStringValue.mutableCopy() as? NSMutableAttributedString
    {
      current.addAttribute(
        .foregroundColor, value: itemColor, range: NSRange(location: 0, length: current.length))
      metadataLabel.attributedStringValue = current
    }

    // Clear highlight if no longer actionable
    if !highlightEnabled { setHighlight(false) }
    needsDisplay = true
  }
}
