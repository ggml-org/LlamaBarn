import AppKit

/// Shared type ramp and color system for the app.
enum Typography {
  // MARK: - Fonts
  static let primary = NSFont.systemFont(ofSize: 13)
  // Secondary/line-2 text used across rows for consistency
  static let secondary = NSFont.systemFont(ofSize: 11, weight: .regular)

  // MARK: - Colors
  static let primaryColor: NSColor = .controlTextColor
  static let secondaryColor: NSColor = .secondaryLabelColor
  static let tertiaryColor: NSColor = .tertiaryLabelColor

  // MARK: - Label Factories
  /// Creates a label text field with primary font and proper menu text color.
  static func makePrimaryLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = primary
    label.textColor = primaryColor
    return label
  }

  /// Creates a label text field with secondary font and proper menu text color.
  static func makeSecondaryLabel(_ text: String = "") -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = secondary
    label.textColor = secondaryColor
    return label
  }

  // MARK: - Attributed String Helpers
  /// Common attributes for secondary text (metadata)
  static let secondaryAttributes: [NSAttributedString.Key: Any] = [
    .font: secondary,
    .foregroundColor: secondaryColor,
  ]

  /// Common attributes for tertiary text (separators, dimmed text)
  static let tertiaryAttributes: [NSAttributedString.Key: Any] = [
    .font: secondary,
    .foregroundColor: tertiaryColor,
  ]
}
