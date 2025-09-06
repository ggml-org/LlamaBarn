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
  // Proper control for delete; avoids manual hit-testing.
  private let deleteButton = NSButton()

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
    indicatorImageView.isHidden = true

    progressLabel.font = MenuTypography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    bytesLabel.font = MenuTypography.secondary
    bytesLabel.textColor = .secondaryLabelColor
    bytesLabel.alignment = .left
    bytesLabel.translatesAutoresizingMaskIntoConstraints = false
    bytesLabel.isHidden = false

    deleteButton.translatesAutoresizingMaskIntoConstraints = false
    deleteButton.isBordered = false
    deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete model")
    deleteButton.contentTintColor = .tertiaryLabelColor
    deleteButton.target = self
    deleteButton.action = #selector(handleDelete)
    deleteButton.toolTip = "Delete model"
    deleteButton.isHidden = true

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
    let rightStack = NSStackView(views: [stateContainer, progressLabel, deleteButton, indicatorImageView])
    rightStack.translatesAutoresizingMaskIntoConstraints = false
    rightStack.orientation = .horizontal
    rightStack.spacing = 6
    rightStack.alignment = .centerY
    // Hidden arranged subviews should be fully detached from layout so they
    // don't reserve space when not visible (e.g., the legacy play/stop slot).
    rightStack.detachesHiddenViews = true

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
      deleteButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      deleteButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.progressWidth),
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

  // Row click recognizer to toggle, letting the delete button handle its own action.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if gestureRecognizers.isEmpty {
      let click = NSClickGestureRecognizer(target: self, action: #selector(didClickRow))
      addGestureRecognizer(click)
    }
  }

  @objc private func didClickRow() { toggle() }

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
      deleteButton.isHidden = !highlighted
    } else {
      deleteButton.isHidden = true
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
      let completedText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      if progress.totalUnitCount > 0 {
        let totalText = ByteFormatters.gbTwoDecimals(progress.totalUnitCount)
        bytesLabel.stringValue = "\(completedText) / \(totalText)"
      } else {
        bytesLabel.stringValue = completedText
      }
      bytesLabel.isHidden = false
      indicatorImageView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
      indicatorImageView.contentTintColor = .systemRed
      indicatorImageView.isHidden = false
      deleteButton.isHidden = true
    case .downloaded:
      // Memory usage now lives in the header; keep the right side empty when not downloading.
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      // No play/stop affordance; active state is conveyed by circular icon.
      indicatorImageView.image = nil
      indicatorImageView.isHidden = true
      // Only show on hover
      deleteButton.isHidden = !isHoverHighlighted
    case .available:
      progressLabel.stringValue = ""
      bytesLabel.stringValue = defaultSecondary
      bytesLabel.isHidden = false
      indicatorImageView.image = nil
      indicatorImageView.isHidden = true
      deleteButton.isHidden = true
    }
    // Update leading circular badge state and tinting
    // Icon should become blue only after the model is done loading (running)
    circleIcon.isActive = isRunning
    applyIconTint(isActive: isRunning)
    applyDeleteTint()
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
      // Consider active (blue) only when the server is running
      statusIsActive = isActiveModel && server.isRunning
    }
    // When active, circular view sets white tint; only tweak in inactive state.
    if !statusIsActive {
      circleIcon.imageView.contentTintColor = isHoverHighlighted ? .labelColor : .secondaryLabelColor
    }
  }

  // Neutral adaptive tint for the delete (trash) symbol; avoid semantic "destructive" red to reduce visual noise.
  private func applyDeleteTint() {
    guard !deleteButton.isHidden else { return }
    let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    if isHoverHighlighted {
      deleteButton.contentTintColor = increaseContrast ? .labelColor : .secondaryLabelColor
    } else {
      deleteButton.contentTintColor =
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
