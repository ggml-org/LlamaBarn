import AppKit

enum IconLabelFormatter {
  static func make(
    icon: NSImage?,
    text: String,
    color: NSColor,
    font: NSFont = Typography.secondary,
    baselineOffset: CGFloat = -2
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
    attachment.bounds = CGRect(
      x: 0,
      y: baselineOffset,
      width: icon.size.width,
      height: icon.size.height
    )

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
