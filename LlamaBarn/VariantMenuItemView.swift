import AppKit
import Foundation

/// Menu row for a downloadable model variant inside a family submenu.
final class VariantMenuItemView: MenuRowView {
  private let model: ModelCatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let statusIndicator = NSImageView()
  private let labelField = NSTextField(labelWithString: "")
  private let infoRow = NSStackView()
  private let sizeLabel = NSTextField(labelWithString: "")
  private let ctxLabel = NSTextField(labelWithString: "")
  private let dateLabel = NSTextField(labelWithString: "")
  private let progressLabel = NSTextField(labelWithString: "")
  private let installedChip = ChipView(text: "Installed")
  // Background handled by MenuRowView

  // Hover handling provided by MenuRowView

  init(
    model: ModelCatalogEntry, modelManager: ModelManager, membershipChanged: @escaping () -> Void
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

  // Only allow hover highlight for actionable rows:
  // - available & compatible (can start download)
  // - downloading (can cancel)
  // Not for incompatible variants or already-downloaded ones.
  override var hoverHighlightEnabled: Bool {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .available:
      return ModelCatalog.isModelCompatible(model)
    case .downloading:
      return true
    case .downloaded:
      return false
    }
  }

  private func setup() {
    wantsLayer = true
    statusIndicator.translatesAutoresizingMaskIntoConstraints = false
    statusIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.font = MenuTypography.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

    let labels = [sizeLabel, ctxLabel, dateLabel]
    for label in labels {
      label.font = MenuTypography.secondary
      label.textColor = .secondaryLabelColor
      label.lineBreakMode = .byTruncatingTail
      label.translatesAutoresizingMaskIntoConstraints = false
    }

    infoRow.orientation = .horizontal
    infoRow.spacing = 4
    infoRow.alignment = .centerY
    infoRow.translatesAutoresizingMaskIntoConstraints = false
    infoRow.addArrangedSubview(dateLabel)
    infoRow.addArrangedSubview(makeSeparator())
    infoRow.addArrangedSubview(sizeLabel)
    infoRow.addArrangedSubview(makeSeparator())
    infoRow.addArrangedSubview(ctxLabel)

    progressLabel.font = MenuTypography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    // Two-line text column (title + size)
    let textColumn = NSStackView(views: [labelField, infoRow])
    textColumn.translatesAutoresizingMaskIntoConstraints = false
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = 1

    // Leading group aligns status icon with first line of text
    let leading = NSStackView(views: [statusIndicator, textColumn])
    leading.translatesAutoresizingMaskIntoConstraints = false
    leading.orientation = .horizontal
    leading.alignment = .top
    leading.spacing = 6

    // Main horizontal row with flexible space and trailing visuals (Installed chip, progress)
    let trailing = NSStackView(views: [installedChip, progressLabel])
    trailing.translatesAutoresizingMaskIntoConstraints = false
    trailing.orientation = .horizontal
    trailing.alignment = .centerY
    trailing.spacing = 6

    let hStack = NSStackView(views: [leading, NSView(), trailing])
    hStack.translatesAutoresizingMaskIntoConstraints = false
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      statusIndicator.widthAnchor.constraint(equalToConstant: MenuMetrics.smallIconSize),
      statusIndicator.heightAnchor.constraint(equalToConstant: MenuMetrics.smallIconSize),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.progressWidth),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }
  override func mouseDown(with event: NSEvent) {
    guard hoverHighlightEnabled else { return }
    handleAction()
    refresh()
  }

  private func handleAction() {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .available:
      if ModelCatalog.isModelCompatible(model) {
        modelManager.downloadModel(model)
        membershipChanged()
      }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged()
    case .downloaded:
      break
    }
  }

  // Hover highlight handled by base class

  func refresh() {
    let status = modelManager.getModelStatus(model)
    let compatible = ModelCatalog.isModelCompatible(model)
    let actionable = hoverHighlightEnabled
    var title = "\(model.displayName)"
    // Only mark true deviations from full‑precision quality.
    // Q8_0 is effectively parity, so don't label it.
    if model.quantization.uppercased() == "Q4_K_M" { title += " (quantized)" }
    labelField.stringValue = title

    sizeLabel.stringValue = model.totalSize
    ctxLabel.stringValue = "Ctx \(TokenFormatters.shortTokens(model.contextLength))"
    dateLabel.stringValue = DateFormatters.monthAndYearString(model.releaseDate)

    if !compatible {
      let reason = ModelCatalog.incompatibilitySummary(model) ?? "not compatible"
      infoRow.toolTip = reason
    }

    // Visual affordances:
    // - Incompatible: tertiary (disabled) coloring
    // - Downloaded: dim to indicate non-interactive
    // - Actionable (available or downloading): regular colors
    let infoColor: NSColor
    if !compatible {
      labelField.textColor = .tertiaryLabelColor
      infoColor = .tertiaryLabelColor
    } else if !actionable {
      labelField.textColor = .secondaryLabelColor
      infoColor = .tertiaryLabelColor
    } else {
      labelField.textColor = .labelColor
      infoColor = .secondaryLabelColor
    }
    for case let label as NSTextField in infoRow.arrangedSubviews {
      label.textColor = infoColor
    }

    progressLabel.stringValue = ""
    switch status {
    case .downloaded:
      // Installed variants are not clickable in this submenu; show a neutral check and dim colors.
      statusIndicator.image = NSImage(
        systemSymbolName: "checkmark.circle", accessibilityDescription: nil)
      statusIndicator.contentTintColor = .tertiaryLabelColor
      toolTip = "Already installed"
      installedChip.isHidden = false
    case .downloading(let progress):
      let pct: Int
      if progress.totalUnitCount > 0 {
        pct = Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
      } else {
        pct = 0
      }
      // Monochrome progress indicator.
      statusIndicator.image = NSImage(
        systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
      statusIndicator.contentTintColor = .secondaryLabelColor
      progressLabel.stringValue = "\(pct)%"
      installedChip.isHidden = true
    case .available:
      if compatible {
        statusIndicator.image = NSImage(
          systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        statusIndicator.contentTintColor = .secondaryLabelColor
      } else {
        statusIndicator.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
        // Monochrome disabled/incompatible indicator.
        statusIndicator.contentTintColor = .tertiaryLabelColor
      }
      installedChip.isHidden = true
    }
    // If the item is no longer actionable, clear any lingering hover highlight.
    if !hoverHighlightEnabled { setHoverHighlight(false) }
    needsDisplay = true
  }

  private func makeSeparator() -> NSView {
    let sep = NSTextField(labelWithString: "•")
    sep.font = MenuTypography.secondary
    sep.textColor = .tertiaryLabelColor
    return sep
  }
}

// Lightweight rounded chip used in variant rows for short status labels.
private final class ChipView: NSView {
  private let label = NSTextField(labelWithString: "")
  private let paddingX: CGFloat = 6
  private let paddingY: CGFloat = 2

  init(text: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = MenuTypography.chip
    label.textColor = .secondaryLabelColor
    label.stringValue = text
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: paddingX),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -paddingX),
      label.topAnchor.constraint(equalTo: topAnchor, constant: paddingY),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -paddingY),
    ])
    layer?.cornerRadius = 6
    layer?.backgroundColor = NSColor.cgColor(.lbBadgeBackground, in: self)
    isHidden = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
