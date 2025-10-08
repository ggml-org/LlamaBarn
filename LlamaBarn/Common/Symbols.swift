import AppKit

/// SF Symbol image constants used throughout the app.
/// Symbols inherit size and color from their context (text or image view).
enum Symbols {
  static let internaldrive = NSImage(
    systemSymbolName: "internaldrive", accessibilityDescription: nil)
  static let textWordSpacing = NSImage(
    systemSymbolName: "text.word.spacing", accessibilityDescription: nil)
  static let memorychip = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil)
  static let checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
  static let trash = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
}
