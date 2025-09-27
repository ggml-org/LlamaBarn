import AppKit

/// Shared type ramp for the app.
enum Typography {
  static let primary = NSFont.systemFont(ofSize: 13)
  // Secondary/line-2 text used across rows for consistency
  static let secondary = NSFont.systemFont(ofSize: 11, weight: .regular)
}
