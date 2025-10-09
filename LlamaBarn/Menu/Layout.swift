import AppKit

/// Shared UI layout constants and helpers for NSMenu custom rows.
enum Layout {
  static let outerHorizontalPadding: CGFloat = 5
  static let innerHorizontalPadding: CGFloat = 8
  static let verticalPadding: CGFloat = 4
  static let cornerRadius: CGFloat = 6
  // Visual size for small inline glyphs.
  static let iconSize: CGFloat = 16
  // Circular badge container size for leading model icon (closer to Wi‑Fi menu).
  static let iconBadgeSize: CGFloat = 28
  static let smallIconSize: CGFloat = 18
  static let progressWidth: CGFloat = 48
}

extension NSView {
  /// Applies or clears the standard selection highlight background on a container view.
  /// Uses dynamic colors resolved for the view's effective appearance and sets a rounded corner.
  func setHighlight(_ highlighted: Bool, cornerRadius: CGFloat = Layout.cornerRadius) {
    wantsLayer = true
    let color: NSColor = highlighted ? .lbSubtleBackground : .clear
    layer?.setBackgroundColor(color, in: self)
    layer?.cornerRadius = cornerRadius
  }
}

extension NSMenuItem {
  /// Creates a disabled NSMenuItem backed by a custom view and optional minimum height.
  static func viewItem(with view: NSView, minHeight: CGFloat? = nil) -> NSMenuItem {
    let item = NSMenuItem()
    item.isEnabled = false
    item.view = view
    if let minHeight {
      view.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
    }
    return item
  }
}
