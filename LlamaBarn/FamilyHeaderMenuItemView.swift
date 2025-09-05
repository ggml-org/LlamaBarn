import AppKit
import Foundation

/// Displays a model family with variant badges summarizing status.
final class FamilyHeaderMenuItemView: NSView {
  fileprivate enum Font {
    static let primary = NSFont.systemFont(ofSize: 13, weight: .regular)
    // Reduced chip font size from 10 -> 8 per design update
    static let chip = NSFont.systemFont(ofSize: 8, weight: .medium)
  }
  private let family: String
  private let models: [ModelCatalogEntry]
  private unowned let modelManager: ModelManager

  private let iconView = NSImageView()
  private let familyLabel = NSTextField(labelWithString: "")
  private let badgesStack = NSStackView()
  private let chevron = NSImageView()
  private let backgroundView = NSView()
  private var badgesMap: [String: BadgeView] = [:]
  // Identifier for ephemeral separator views between chips
  private let badgeSeparatorID = NSUserInterfaceItemIdentifier("badge-separator")

  private var trackingArea: NSTrackingArea?
  private var isHighlighted = false { didSet { updateHighlight() } }

  init(family: String, models: [ModelCatalogEntry], modelManager: ModelManager) {
    self.family = family
    self.models = models
    self.modelManager = modelManager
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 40) }

  private func setup() {
    wantsLayer = true
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true
    iconView.image = NSImage(named: models.first?.icon ?? "")
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.imageScaling = .scaleProportionallyDown
    if let img = iconView.image { img.isTemplate = true }
    iconView.contentTintColor = .secondaryLabelColor

    familyLabel.stringValue = family
    // Match primary row font size used elsewhere (Installed models, server status, catalog entries)
    familyLabel.font = Font.primary
    familyLabel.translatesAutoresizingMaskIntoConstraints = false

    badgesStack.orientation = .horizontal
    badgesStack.spacing = 4
    badgesStack.alignment = .centerY
    // Let badges hug their intrinsic content; default distribution avoids stretching when hugging is required
    badgesStack.translatesAutoresizingMaskIntoConstraints = false

    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    // Match trailing indicator sizing (16x16 w/ pointSize 14) used in InstalledModelMenuItemView for alignment
    chevron.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    chevron.contentTintColor = .secondaryLabelColor
    chevron.translatesAutoresizingMaskIntoConstraints = false

    let textColumn = NSStackView(views: [familyLabel, badgesStack])
    textColumn.orientation = .vertical
    textColumn.spacing = 1
    textColumn.alignment = .leading
    textColumn.translatesAutoresizingMaskIntoConstraints = false

    // Nest icon + text column so we can align icon with first line (family label) instead of vertical center.
    let leadingStack = NSStackView(views: [iconView, textColumn])
    leadingStack.orientation = .horizontal
    leadingStack.spacing = 6
    leadingStack.alignment = .top  // ensures icon top aligns with label top (first line)
    leadingStack.translatesAutoresizingMaskIntoConstraints = false

    let hStack = NSStackView(views: [leadingStack, NSView(), chevron])
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY  // overall row still vertically centered in its container
    hStack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backgroundView)
    backgroundView.addSubview(hStack)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      // Reduced from 18 -> 16 to make logos a bit smaller and align with 16x16 action icons
      iconView.widthAnchor.constraint(equalToConstant: 16),
      iconView.heightAnchor.constraint(equalToConstant: 16),
      chevron.widthAnchor.constraint(equalToConstant: 16),
      chevron.heightAnchor.constraint(equalToConstant: 16),
      hStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
      hStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
      hStack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 4),
      hStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -4),
    ])
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    trackingArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)
  }

  override func mouseEntered(with event: NSEvent) { isHighlighted = true }
  override func mouseExited(with event: NSEvent) { isHighlighted = false }

  private func updateHighlight() {
    if isHighlighted {
      backgroundView.layer?.backgroundColor = NSColor.cgColor(.lbHoverBackground, in: backgroundView)
    } else {
      backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
    }
    backgroundView.layer?.cornerRadius = 6
    applyIconTint()
  }

  func refresh() {
    let sortedModels = models.sorted(by: ModelCatalogEntry.displayOrder(_:_:))
    var seen: Set<String> = []
    // Remove any existing separators before rebuilding
    removeBadgeSeparators()
    for model in sortedModels {
      let key = model.id
      seen.insert(key)
      let status = modelManager.getModelStatus(model)
      let downloaded = (status == .downloaded)
      let compatible = ModelCatalog.isModelCompatible(model)
      let badge =
        badgesMap[key]
        ?? {
          let c = BadgeView()
          badgesMap[key] = c
          badgesStack.addArrangedSubview(c)
          return c
        }()
      badge.configure(
        text: model.variant + (model.simplifiedQuantization == "Q8" ? "+" : ""),
        showCheck: downloaded,
        downloaded: downloaded,
        compatible: compatible
      )
    }
    for (key, badge) in badgesMap where !seen.contains(key) {
      badgesStack.removeArrangedSubview(badge)
      badge.removeFromSuperview()
      badgesMap.removeValue(forKey: key)
    }
    // Ensure separators exist between all remaining badges
    rebuildBadgeSeparators()
    needsDisplay = true
  }

  private func removeBadgeSeparators() {
    for view in badgesStack.arrangedSubviews where view.identifier == badgeSeparatorID {
      badgesStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
  }

  private func rebuildBadgeSeparators() {
    // Collect badges in order as they appear
    let badges = badgesStack.arrangedSubviews.compactMap { $0 as? BadgeView }
    guard badges.count > 1 else { return }
    // Insert separators between each adjacent pair if not already present
    for (index, badge) in badges.enumerated() where index > 0 {
      let separator = BadgeSeparatorView()
      separator.identifier = badgeSeparatorID
      // Insert separator before this badge in the overall arrangedSubviews order
      if let idx = badgesStack.arrangedSubviews.firstIndex(of: badge) {
        badgesStack.insertArrangedSubview(separator, at: idx)
      }
    }
  }

  private func applyIconTint() {
    iconView.contentTintColor = isHighlighted ? .labelColor : .secondaryLabelColor
  }

}

private final class BadgeView: NSView {
  private let check = NSImageView()
  private let label = NSTextField(labelWithString: "")
  private let innerStack = NSStackView()
  private var checkVisible = false
  // Cache last state so we can reapply colors on appearance changes.
  private var lastDownloaded = false
  private var lastCompatible = false
  // Track last applied appearance to avoid double application (initial + menu vibrancy resolution) causing flash.
  private var lastAppliedAppearanceName: NSAppearance.Name?
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    check.translatesAutoresizingMaskIntoConstraints = false
    check.symbolConfiguration = .init(pointSize: 7, weight: .bold)
    // Match smaller badge font size
    label.font = FamilyHeaderMenuItemView.Font.chip
    label.translatesAutoresizingMaskIntoConstraints = false
    innerStack.orientation = .horizontal
    innerStack.spacing = 2
    innerStack.alignment = .centerY
    innerStack.translatesAutoresizingMaskIntoConstraints = false
    innerStack.addArrangedSubview(check)
    innerStack.addArrangedSubview(label)
    addSubview(innerStack)
    NSLayoutConstraint.activate([
      innerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
      innerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
      innerStack.topAnchor.constraint(equalTo: topAnchor),
      innerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    setContentHuggingPriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .horizontal)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func configure(text: String, showCheck: Bool, downloaded: Bool, compatible: Bool) {
    label.stringValue = text
    if showCheck {
      check.isHidden = false
      check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
      check.contentTintColor = .llamaGreen
    } else {
      check.isHidden = true
      check.image = nil
    }
    if showCheck != checkVisible {
      checkVisible = showCheck
      invalidateIntrinsicContentSize()
    }
    // No internal padding visuals; remove outlines and rounding
    layer?.cornerRadius = 0
    layer?.borderWidth = 0
    lastDownloaded = downloaded
    lastCompatible = compatible
    // Defer color application to next runloop so effectiveAppearance has stabilized within menu hierarchy.
    DispatchQueue.main.async { [weak self] in self?.applyColors(force: false) }
    // Ensure width recalculates if text length changes (e.g., reused view across families in future)
    invalidateIntrinsicContentSize()
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    // Re-resolve dynamic system colors (especially needed for CGColor on CALayer in dark mode).
    applyColors(force: true)
  }
  private func applyColors(force: Bool) {
    guard let layer else { return }
    // Avoid redundant work & flicker if appearance name hasn't changed unless forced.
    let currentName =
      effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? effectiveAppearance.name
    if !force, lastAppliedAppearanceName == currentName { return }
    lastAppliedAppearanceName = currentName
    // Resolve dynamic colors to concrete before bridging to CGColor to avoid second-phase shifts.
    // No border color since outlines are removed
    // Final simplified ordering to avoid confusion & accidental lower contrast for supported chips:
    // Downloaded: primary, Compatible (supported but not downloaded): secondary, Unsupported: disabled.
    if lastDownloaded {
      label.textColor = .labelColor
    } else if lastCompatible {
      label.textColor = .secondaryLabelColor
    } else {
      label.textColor = .tertiaryLabelColor
    }
  }
  override var intrinsicContentSize: NSSize {
    let labelSize = label.intrinsicContentSize
    let checkWidth: CGFloat =
      checkVisible
      ? (check.intrinsicContentSize.width == 0 ? 10 : check.intrinsicContentSize.width) + 2 : 0  // +2 for spacing when visible
    let width = checkWidth + labelSize.width
    let height = labelSize.height
    return NSSize(width: width, height: height)
  }
}

// Small centered dot between badges (replaces 1px hairline)
private final class BadgeSeparatorView: NSView {
  private let dotSize: CGFloat = 1.5
  private var sizeConstraints: [NSLayoutConstraint] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.backgroundColor = NSColor.cgColor(.lbStrongSeparator, in: self)
    layer?.cornerRadius = dotSize / 2
    setHuggingCompression()
    applySizeConstraints()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setHuggingCompression() {
    setContentHuggingPriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setContentHuggingPriority(.required, for: .vertical)
    setContentCompressionResistancePriority(.required, for: .vertical)
  }

  private func applySizeConstraints() {
    NSLayoutConstraint.deactivate(sizeConstraints)
    sizeConstraints = [
      widthAnchor.constraint(equalToConstant: dotSize),
      heightAnchor.constraint(equalToConstant: dotSize),
    ]
    NSLayoutConstraint.activate(sizeConstraints)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = NSColor.cgColor(.lbStrongSeparator, in: self)
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: dotSize, height: dotSize)
  }
}
