import AppKit

/// Shared UI metrics and helpers for NSMenu custom rows.
enum MenuMetrics {
  static let outerHorizontalPadding: CGFloat = 5
  static let innerHorizontalPadding: CGFloat = 8
  static let verticalPadding: CGFloat = 4
  static let cornerRadius: CGFloat = 6
  static let iconSize: CGFloat = 16
  static let smallIconSize: CGFloat = 14
  static let progressWidth: CGFloat = 48
}

/// Shared type ramp for menu rows.
enum MenuTypography {
  static let primary = NSFont.systemFont(ofSize: 13)
  static let primarySemibold = NSFont.systemFont(ofSize: 13, weight: .semibold)
  static let secondary = NSFont.systemFont(ofSize: 10, weight: .medium)
  static let subtitle = NSFont.systemFont(ofSize: 10)
  static let chip = NSFont.systemFont(ofSize: 8, weight: .medium)
}

extension NSView {
  /// Applies or clears the standard hover highlight background on a container view.
  /// Uses dynamic colors resolved for the view’s effective appearance and sets a rounded corner.
  func lbSetHoverHighlighted(_ highlighted: Bool, cornerRadius: CGFloat = MenuMetrics.cornerRadius) {
    wantsLayer = true
    let color: NSColor = highlighted ? .lbHoverBackground : .clear
    layer?.backgroundColor = NSColor.cgColor(color, in: self)
    layer?.cornerRadius = cornerRadius
  }
}

extension NSMenuItem {
  /// Creates a disabled NSMenuItem backed by a custom view and optional minimum height.
  static func viewItem(with view: NSView, minHeight: CGFloat? = nil) -> NSMenuItem {
    let item = NSMenuItem()
    item.isEnabled = false
    item.view = view
    if let minHeight { view.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true }
    return item
  }
}
