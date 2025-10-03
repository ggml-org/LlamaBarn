import AppKit

/// Helper for creating metadata labels with SF Symbol icons and text.
/// Color is inherited from the containing NSTextField's textColor rather than set explicitly.
enum MetadataLabel {
  // MARK: - Symbols

  /// Creates a template SF Symbol with specified size and weight.
  /// Size defaults to 11pt to match Typography.secondary.
  /// Template images automatically adopt the text field's tint color.
  private static func makeSymbol(
    _ name: String, pointSize: CGFloat = 11, weight: NSFont.Weight = .regular
  ) -> NSImage? {
    guard
      let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
    else { return nil }
    image.isTemplate = true
    return image
  }

  // Metadata symbols (used with text)
  static let sizeSymbol = makeSymbol("internaldrive")
  static let contextSymbol = makeSymbol("text.word.spacing")
  static let memorySymbol = makeSymbol("memorychip")

  // Status symbols (used standalone)
  static let checkSymbol = makeSymbol("checkmark")
  static let warningSymbol = makeSymbol("exclamationmark.triangle")

  // MARK: - Attributed String Builders

  /// Creates an attributed string containing only an icon (no text).
  /// Used for status indicators like checkmarks or warnings.
  static func makeIconOnly(icon: NSImage?) -> NSAttributedString {
    guard let icon else { return NSAttributedString() }
    let attachment = NSTextAttachment()
    attachment.image = icon
    return NSAttributedString(attachment: attachment)
  }

  /// Creates an attributed string with an icon followed by text (e.g., "📦 2.5 GB").
  /// If no icon provided, returns plain text with font applied.
  static func make(
    icon: NSImage?,
    text: String,
    font: NSFont = Typography.secondary
  ) -> NSAttributedString {
    guard let icon else {
      return NSAttributedString(string: text, attributes: [.font: font])
    }

    let attachment = NSTextAttachment()
    attachment.image = icon
    let composed = NSMutableAttributedString(attachment: attachment)
    composed.append(NSAttributedString(string: " \(text)", attributes: [.font: font]))
    return composed
  }

  /// Creates a bullet separator for metadata lines (e.g., "2.5 GB · 128k · 4 GB").
  static func makeSeparator(font: NSFont = Typography.secondary) -> NSAttributedString {
    NSAttributedString(string: " • ", attributes: [.font: font])
  }
}
