import AppKit

// Custom colors for the app. Prefer system semantic colors (.labelColor, .separatorColor, etc.) everywhere else.
extension NSColor {
  /// Green for status indicators and active badges.
  static let llamaGreen = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(srgbRed: 0.40, green: 0.84, blue: 0.47, alpha: 1.0)  // #65D679
      : NSColor(srgbRed: 0.12, green: 0.50, blue: 0.23, alpha: 1.0)  // #1F7F3A
  }

  /// Hover background for interactive menu rows.
  static let lbHoverBackground = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor.white.withAlphaComponent(0.11)
      : NSColor.black.withAlphaComponent(0.06)
  }

  /// Background for inactive icon badges.
  static let lbBadgeBackground = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor.white.withAlphaComponent(0.10)
      : NSColor.black.withAlphaComponent(0.05)
  }
}

// Helper for using dynamic NSColors with CALayer (which requires CGColor).
extension CALayer {
  func setBackgroundColor(_ color: NSColor, in view: NSView) {
    var resolved: CGColor = NSColor.clear.cgColor
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      resolved = color.cgColor
    }
    backgroundColor = resolved
  }
}
