import AppKit
import Foundation

/// Menu row representing a single installed model.
/// Visual states:
/// - Idle: circular icon (inactive) + label
/// - Loading: circular icon (active) + spinner
/// - Running: circular icon (active)
final class InstalledModelMenuItemView: MenuRowView {
  private let model: ModelCatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  // Subviews
  private let circleIcon = CircularIconView()
  private let labelField = NSTextField(labelWithString: "")
  private let stateContainer = NSView()
  private let spinner = NSProgressIndicator()
  private let indicatorImageView = NSImageView()
  private let progressLabel = NSTextField(labelWithString: "")
  // Second-line label: used for progress during downloads and for
  // consistent two-line layout (size/badges) when idle/running.
  private let bytesLabel = NSTextField(labelWithString: "")
  // Replaces prior NSButton (which rendered black in dark mode inside menu views) with template image view.
  private let deleteImageView = NSImageView()

  // Hover handling is provided by MenuRowView

  init(
    model: ModelCatalogEntry, server: LlamaServer, modelManager: ModelManager,
    membershipChanged: @escaping () -> Void
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

    labelField.stringValue = model.displayName
    labelField.font = MenuTypography.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.isDisplayedWhenStopped = false

    indicatorImageView.translatesAutoresizingMaskIntoConstraints = false
    indicatorImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    indicatorImageView.contentTintColor = .controlAccentColor

    progressLabel.font = MenuTypography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    bytesLabel.font = MenuTypography.secondary
    bytesLabel.textColor = .secondaryLabelColor
    bytesLabel.alignment = .left
    bytesLabel.translatesAutoresizingMaskIntoConstraints = false
    bytesLabel.isHidden = false

    deleteImageView.image = NSImage(
      systemSymbolName: "trash", accessibilityDescription: "Delete model")
    deleteImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    if let img = deleteImageView.image { img.isTemplate = true }
    deleteImageView.translatesAutoresizingMaskIntoConstraints = false
    // Start with a low-emphasis tertiary tint; hover/highlight will elevate contrast slightly.
    deleteImageView.contentTintColor = .tertiaryLabelColor
    deleteImageView.toolTip = "Delete model"
    deleteImageView.isHidden = true

    // Order: icon | (label over bytes) | spacer | (state, progress, delete, action)
    // Spacer expands so trailing visuals sit flush right.
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    labelField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    labelField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    progressLabel.setContentHuggingPriority(.required, for: .horizontal)
    progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    // Left: icon aligned with first text line, then two-line text column
    let nameStack = NSStackView(views: [labelField, bytesLabel])
    nameStack.translatesAutoresizingMaskIntoConstraints = false
    nameStack.orientation = .vertical
    nameStack.spacing = 1
    nameStack.alignment = .leading

    let leading = NSStackView(views: [circleIcon, nameStack])
    leading.translatesAutoresizingMaskIntoConstraints = false
    leading.orientation = .horizontal
    // Vertically center the circular icon relative to the two-line text, like Wi‑Fi menu
    leading.alignment = .centerY
    leading.spacing = 6

    // Right: status/progress/delete/action in a row
    let rightStack = NSStackView(views: [stateContainer, progressLabel, deleteImageView, indicatorImageView])
    rightStack.translatesAutoresizingMaskIntoConstraints = false
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
      circleIcon.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      circleIcon.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      stateContainer.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      stateContainer.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      indicatorImageView.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      indicatorImageView.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      deleteImageView.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      deleteImageView.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.progressWidth),
      rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  // Custom hit test so clicking the trash icon deletes instead of toggling run state.
  override func mouseDown(with event: NSEvent) {
    let loc = convert(event.locationInWindow, from: nil)
    if !deleteImageView.isHidden && deleteImageView.frame.contains(loc) {
      handleDelete()
      return
    }
    toggle()
  }

  private func toggle() {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .downloaded:
      if server.isActive(model: model) { server.stop() } else { server.start(model: model) }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged()
    case .available:
      break
    }
    refresh()
  }

  override func hoverHighlightDidChange(_ highlighted: Bool) {
    // Show delete only when hovered & model is downloaded
    let status = modelManager.getModelStatus(model)
    if case .downloaded = status {
      deleteImageView.isHidden = !highlighted
    } else {
      deleteImageView.isHidden = true
    }
    // Update icon tint when highlight changes.
    applyIconTint()
    applyDeleteTint()
  }

  func refresh() {
    // Determine state
    let status = modelManager.getModelStatus(model)
    let isActive = server.isActive(model: model)
    let isLoadingServer = isActive && server.isLoading
    let isRunning = isActive && server.isRunning

    // Clear state container
    stateContainer.subviews.forEach { $0.removeFromSuperview() }
    spinner.stopAnimation(nil)

    if isLoadingServer {
      stateContainer.addSubview(spinner)
      NSLayoutConstraint.activate([
        spinner.centerXAnchor.constraint(equalTo: stateContainer.centerXAnchor),
        spinner.centerYAnchor.constraint(equalTo: stateContainer.centerYAnchor),
      ])
      spinner.startAnimation(nil)
    }
    // Compose a default secondary line (size + capability badges) used when not downloading
    let defaultSecondary: String = model.totalSize

    // Download progress / action area
    switch status {
    case .downloading(let progress):
      let percent: Int
      if progress.totalUnitCount > 0 {
        percent = Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
      } else {
        percent = 0
      }
      progressLabel.stringValue = "\(percent)%"
      // Second line: show downloaded/total in GB with two decimals
      func formatGB(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        return String(format: "%.2f GB", gb)
      }
      let completedText = formatGB(progress.completedUnitCount)
      if progress.totalUnitCount > 0 {
        let totalText = formatGB(progress.totalUnitCount)
        bytesLabel.stringValue = "\(completedText) / \(totalText)"
      } else {
        bytesLabel.stringValue = completedText
      }
      bytesLabel.isHidden = false
      indicatorImageView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
      indicatorImageView.contentTintColor = .systemRed
      deleteImageView.isHidden = true
    case .downloaded:
      // Memory usage now lives in the header; keep the right side empty when not downloading.
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      // No play/stop affordance; active state is conveyed by circular icon.
      indicatorImageView.image = nil
      // Only show on hover
      if isHoverHighlighted { deleteImageView.isHidden = false }
    case .available:
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      indicatorImageView.image = nil
      deleteImageView.isHidden = true
    }
    // Update leading circular badge state and tinting
    circleIcon.isActive = isLoadingServer || isRunning
    applyIconTint(isActive: isLoadingServer || isRunning)
    needsDisplay = true
  }

  /// Adjusts the icon tint to reduce excessive contrast of colorful brand logos vs text labels.
  /// Idle/normal: secondary label color so text (primary) leads.
  /// Active (loading/running) or highlighted: primary label color for emphasis.
  private func applyIconTint(isActive: Bool? = nil) {
    let statusIsActive: Bool
    if let isActive = isActive {
      statusIsActive = isActive
    } else {
      let isActiveModel = server.isActive(model: model)
      statusIsActive = isActiveModel && (server.isLoading || server.isRunning)
    }
    // When active, circular view sets white tint; only tweak in inactive state.
    if !statusIsActive {
      circleIcon.imageView.contentTintColor = isHoverHighlighted ? .labelColor : .secondaryLabelColor
    }
  }

  // Neutral adaptive tint for the delete (trash) symbol; avoid semantic "destructive" red to reduce visual noise.
  private func applyDeleteTint() {
    guard !deleteImageView.isHidden else { return }
    let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    if isHoverHighlighted {
      deleteImageView.contentTintColor = increaseContrast ? .labelColor : .secondaryLabelColor
    } else {
      deleteImageView.contentTintColor =
        increaseContrast ? .secondaryLabelColor : .tertiaryLabelColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyDeleteTint()
  }

  @objc private func handleDelete() {
    let status = modelManager.getModelStatus(model)
    guard case .downloaded = status else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged()
  }
}
