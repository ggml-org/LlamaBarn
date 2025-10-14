import AppKit

// Custom colors.
extension NSColor {
  /// Green for status indicators and active icon containers.
  static let llamaGreen = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor(srgbRed: 0.40, green: 0.84, blue: 0.47, alpha: 1.0)  // #65D679
      : NSColor(srgbRed: 0.12, green: 0.50, blue: 0.23, alpha: 1.0)  // #1F7F3A
  }

  /// Subtle background for hover states and inactive icon containers.
  static let lbSubtleBackground = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      ? NSColor.white.withAlphaComponent(0.11)
      : NSColor.black.withAlphaComponent(0.06)
  }

  /// Create NSColor from hex string (e.g., "#3e2c61" or "3e2c61")
  static func fromHex(_ hex: String) -> NSColor? {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    guard hexSanitized.count == 6 else { return nil }

    var rgb: UInt64 = 0
    guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

    let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let b = CGFloat(rgb & 0x0000FF) / 255.0

    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
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
