import AppKit

/// Minimal base class for custom NSMenu item rows.
/// Provides a shared background container with hover highlight and a content area for subclasses.
class MenuRowView: NSView {
  let backgroundView = NSView()
  let contentView = NSView()

  private var trackingArea: NSTrackingArea?
  private(set) var isHoverHighlighted = false

  // MARK: - Customization hooks

  /// Override to disable hover highlight based on dynamic state (e.g., only when server is running).
  var hoverHighlightEnabled: Bool { true }
  /// Override to change corner radius of the background.
  var hoverCornerRadius: CGFloat { MenuMetrics.cornerRadius }
  /// Called whenever the hover highlight changes.
  func hoverHighlightDidChange(_ highlighted: Bool) {}

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    setupContainers()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setupContainers() {
    wantsLayer = true
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true
    contentView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backgroundView)
    backgroundView.addSubview(contentView)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: MenuMetrics.outerHorizontalPadding),
      backgroundView.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -MenuMetrics.outerHorizontalPadding),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

      contentView.leadingAnchor.constraint(
        equalTo: backgroundView.leadingAnchor, constant: MenuMetrics.innerHorizontalPadding),
      contentView.trailingAnchor.constraint(
        equalTo: backgroundView.trailingAnchor, constant: -MenuMetrics.innerHorizontalPadding),
      contentView.topAnchor.constraint(
        equalTo: backgroundView.topAnchor, constant: MenuMetrics.verticalPadding),
      contentView.bottomAnchor.constraint(
        equalTo: backgroundView.bottomAnchor, constant: -MenuMetrics.verticalPadding),
    ])
  }

  // MARK: - Hover handling

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)
  }

  override func mouseEntered(with event: NSEvent) {
    guard hoverHighlightEnabled else { return }
    setHoverHighlight(true)
  }

  override func mouseExited(with event: NSEvent) {
    setHoverHighlight(false)
  }

  /// Programmatically set hover highlight (e.g., to clear highlight when state changes).
  func setHoverHighlight(_ highlighted: Bool) {
    guard highlighted != isHoverHighlighted else { return }
    isHoverHighlighted = highlighted
    backgroundView.lbSetHoverHighlighted(highlighted, cornerRadius: hoverCornerRadius)
    hoverHighlightDidChange(highlighted)
  }
}

