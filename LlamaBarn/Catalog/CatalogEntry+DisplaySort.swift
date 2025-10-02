import Foundation

// Shared comparator for consistent model ordering in menus.
extension CatalogEntry {
  /// Sorts smaller download sizes first; tie-break by parameter size.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.fileSize != rhs.fileSize { return lhs.fileSize < rhs.fileSize }
    // Stable fallback to keep deterministic ordering when sizes match
    return lhs.id < rhs.id
  }

  /// Orders catalog entries for display within a family submenu.
  /// Keeps full-precision builds ahead of quantized variants for the same base model size.
  static func familyDisplayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.size != rhs.size { return displayOrder(lhs, rhs) }
    if lhs.isFullPrecision != rhs.isFullPrecision { return lhs.isFullPrecision }
    return displayOrder(lhs, rhs)
  }
}
