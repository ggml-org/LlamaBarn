import AppKit

enum ModelVariantPalette {
  static func titleColor(isDownloaded: Bool, compatible: Bool) -> NSColor {
    if isDownloaded || compatible { return .labelColor }
    return .tertiaryLabelColor
  }

  static func metadataColor(compatible: Bool) -> NSColor {
    compatible ? .secondaryLabelColor : .tertiaryLabelColor
  }

  static func familyMetadataColor(downloaded: Bool, compatible: Bool) -> NSColor {
    // Surface supported variants (even if not installed) with the same prominence as installed ones
    // so users can quickly spot which sizes will run on their Mac.
    if downloaded || compatible { return .labelColor }
    // Unsupported variants share the same tint everywhere; use a slightly less transparent tertiary color
    // so they stay legible when rendered next to label-colored siblings or on highlighted rows.
    return NSColor.tertiaryLabelColor.withAlphaComponent(0.6)
  }
}
