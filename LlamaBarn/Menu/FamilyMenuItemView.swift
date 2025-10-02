import AppKit
import Foundation

/// Interactive menu item that triggers a submenu for a model family, showing model size indicators with download/compatibility status.
///
/// Background and hover handling provided by MenuItemView.
/// Size indicators are rebuilt on each refresh rather than tracked statefully for simplicity.
final class FamilyMenuItemView: MenuItemView {
  // MARK: - Properties

  private let family: String
  private let sortedModels: [CatalogEntry]
  private unowned let modelManager: Manager

  private let iconView = RoundedRectIconView()
  private let familyLabel = NSTextField(labelWithString: "")
  private let metadataLabel = NSTextField(labelWithString: "")
  private let chevron = NSImageView()

  // MARK: - Initialization

  init(family: String, sortedModels: [CatalogEntry], modelManager: Manager) {
    self.family = family
    self.sortedModels = sortedModels
    self.modelManager = modelManager
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 40) }

  // MARK: - Setup

  /// Configures the view hierarchy and layout constraints.
  private func setup() {
    wantsLayer = true

    // Configure icon view
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.setImage(NSImage(named: sortedModels.first?.icon ?? ""))
    // Family rows trigger submenus rather than actions, so never show active state.
    iconView.isActive = false

    // Configure family name label
    familyLabel.stringValue = family
    familyLabel.font = Typography.primary
    familyLabel.translatesAutoresizingMaskIntoConstraints = false

    // Configure metadata label (shows model sizes)
    metadataLabel.font = Typography.secondary
    metadataLabel.textColor = .secondaryLabelColor
    metadataLabel.lineBreakMode = .byTruncatingTail
    metadataLabel.translatesAutoresizingMaskIntoConstraints = false

    // Configure chevron indicator
    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    // Match InstalledModelMenuItemView trailing indicator sizing for alignment.
    chevron.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    chevron.contentTintColor = .secondaryLabelColor
    chevron.translatesAutoresizingMaskIntoConstraints = false

    // Build layout hierarchy: icon + text column on left, chevron on right
    let textColumn = NSStackView(views: [familyLabel, metadataLabel])
    textColumn.orientation = .vertical
    textColumn.spacing = 2
    textColumn.alignment = .leading
    textColumn.translatesAutoresizingMaskIntoConstraints = false

    // Center icon vertically against two-line text to match InstalledModelMenuItemView layout.
    let leadingStack = NSStackView(views: [iconView, textColumn])
    leadingStack.orientation = .horizontal
    leadingStack.spacing = 6
    leadingStack.alignment = .centerY
    leadingStack.translatesAutoresizingMaskIntoConstraints = false

    // Main row with flexible space between leading content and chevron
    let hStack = NSStackView(views: [leadingStack, NSView(), chevron])
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY
    hStack.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      iconView.heightAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      chevron.widthAnchor.constraint(equalToConstant: Metrics.iconSize),
      chevron.heightAnchor.constraint(equalToConstant: Metrics.iconSize),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  // MARK: - Refresh

  /// Updates the metadata line with current model size states.
  func refresh() {
    metadataLabel.attributedStringValue = makeMetadataLine()
    needsDisplay = true
  }

  // MARK: - Metadata Line Construction

  /// Builds an attributed string showing each unique model build in this family,
  /// highlighting downloads with a checkmark and compatible models with darker text.
  private func makeMetadataLine() -> NSAttributedString {
    // Deduplicate by the underlying build so separate quantized entries remain visible once.
    var used: Set<String> = []
    let line = NSMutableAttributedString()

    for model in sortedModels {
      guard used.insert(model.id).inserted else { continue }

      let status = modelManager.getModelStatus(model)
      let downloaded = (status == .downloaded)
      let compatible = Catalog.isModelCompatible(model)
      // Use darker text for downloaded or compatible models to make them stand out.
      let color: NSColor = (downloaded || compatible) ? .labelColor : .secondaryLabelColor

      // Add separator between entries
      if line.length > 0 {
        line.append(MetadataSeparator.make(color: .tertiaryLabelColor))
      }

      line.append(attributedSizeLabel(for: model, downloaded: downloaded, color: color))
    }

    return line
  }

  private func shortQuantizationLabel(_ quantization: String) -> String {
    let upper = quantization.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !upper.isEmpty else { return upper }
    if let idx = upper.firstIndex(where: { $0 == "_" || $0 == "-" }) {
      let prefix = upper[..<idx]
      if !prefix.isEmpty { return String(prefix) }
    }
    return upper
  }

  /// Creates an attributed string for a model size label.
  /// Downloaded models show a green checkmark to indicate they're already installed.
  private func attributedSizeLabel(
    for model: CatalogEntry,
    downloaded: Bool,
    color: NSColor
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let baseFont = Typography.secondary

    if downloaded {
      result.append(
        MetadataLabel.makeIconOnly(
          icon: MetadataIcons.checkSymbol,
          color: .llamaGreen,
          baselineOffset: MetadataIcons.checkBaselineOffset
        )
      )
      result.append(NSAttributedString(string: " "))
    }

    result.append(
      NSAttributedString(
        string: model.size,
        attributes: [
          .font: baseFont,
          .foregroundColor: color,
        ]
      )
    )

    if !model.isFullPrecision {
      let quantLabel = shortQuantizationLabel(model.quantization)
      if !quantLabel.isEmpty {
        result.append(
          NSAttributedString(
            string: quantLabel,
            attributes: [
              .font: baseFont,
              .foregroundColor: color,
            ]
          ))
      }
    }

    return result
  }
}
