import AppKit

enum MetadataLabel {
  static let sizeSymbol: NSImage? = {
    guard
      let image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    else { return nil }
    image.isTemplate = true
    return image
  }()

  static let contextSymbol: NSImage? = {
    guard
      let image = NSImage(systemSymbolName: "text.word.spacing", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    else { return nil }
    image.isTemplate = true
    return image
  }()

  static let memorySymbol: NSImage? = {
    guard
      let image = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    else { return nil }
    image.isTemplate = true
    return image
  }()

  static func makeIconOnly(
    icon: NSImage?,
    color: NSColor
  ) -> NSAttributedString {
    guard let icon else { return NSAttributedString() }
    let attachment = NSTextAttachment()
    attachment.image = icon
    let composed = NSMutableAttributedString(
      attributedString: NSAttributedString(attachment: attachment)
    )
    composed.addAttribute(
      .foregroundColor,
      value: color,
      range: NSRange(location: 0, length: composed.length)
    )
    return composed
  }

  static func make(
    icon: NSImage?,
    text: String,
    color: NSColor,
    font: NSFont = Typography.secondary
  ) -> NSAttributedString {
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
    ]

    guard let icon else {
      return NSAttributedString(string: text, attributes: attributes)
    }

    let attachment = NSTextAttachment()
    attachment.image = icon

    let composed = NSMutableAttributedString(
      attributedString: NSAttributedString(attachment: attachment)
    )
    composed.append(NSAttributedString(string: " \(text)", attributes: attributes))
    composed.addAttribute(
      .foregroundColor,
      value: color,
      range: NSRange(location: 0, length: composed.length)
    )
    return composed
  }
}

enum MetadataSeparator {
  static func make(
    font: NSFont = Typography.secondary,
    color: NSColor = .tertiaryLabelColor
  ) -> NSAttributedString {
    NSAttributedString(
      string: " • ",
      attributes: [
        .font: font,
        .foregroundColor: color,
      ]
    )
  }
}

enum MetadataIcons {
  static let checkSymbol: NSImage? = {
    guard
      let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
        .withSymbolConfiguration(
          .init(pointSize: 10, weight: .semibold)
        )
    else { return nil }
    image.isTemplate = true
    return image
  }()

  static let warningSymbol: NSImage? = {
    guard
      let image = NSImage(
        systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)?
        .withSymbolConfiguration(
          .init(pointSize: 11, weight: .regular)
        )
    else { return nil }
    image.isTemplate = true
    return image
  }()
}
