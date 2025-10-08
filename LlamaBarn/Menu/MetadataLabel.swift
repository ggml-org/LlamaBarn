import AppKit

/// Helper for creating metadata labels with SF Symbol icons and text.
/// Colors are set explicitly: text uses secondaryLabelColor, separators use tertiaryLabelColor.
enum MetadataLabel {
  // MARK: - Attributed String Builders

  /// Creates an attributed string containing only an icon (no text).
  /// Used for status indicators like checkmarks.
  static func makeIconOnly(icon: NSImage?) -> NSAttributedString {
    guard let icon else { return NSAttributedString() }
    return NSAttributedString(attachment: iconAttachment(for: icon))
  }

  /// Creates an attributed string with an icon followed by text (e.g., "📦 2.5 GB").
  /// If no icon provided, returns plain text with font and color applied.
  static func make(
    icon: NSImage?,
    text: String,
    font: NSFont = Typography.secondary
  ) -> NSAttributedString {
    guard let icon else {
      return NSAttributedString(string: text, attributes: Typography.secondaryAttributes)
    }

    let composed = NSMutableAttributedString(attachment: iconAttachment(for: icon))
    composed.append(
      NSAttributedString(string: " \(text)", attributes: Typography.secondaryAttributes))
    return composed
  }

  /// Creates a bullet separator for metadata lines (e.g., "2.5 GB • 128k • 4 GB").
  static func makeSeparator(font: NSFont = Typography.secondary) -> NSAttributedString {
    NSAttributedString(string: " • ", attributes: Typography.tertiaryAttributes)
  }

  // MARK: - Private Helpers

  /// Creates an NSTextAttachment for an icon.
  private static func iconAttachment(for icon: NSImage) -> NSTextAttachment {
    let attachment = NSTextAttachment()
    attachment.image = icon
    return attachment
  }
}
