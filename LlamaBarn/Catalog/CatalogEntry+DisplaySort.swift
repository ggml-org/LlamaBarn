import Foundation

// Shared comparator for consistent model ordering in menus.
extension CatalogEntry {
  /// Sorts smaller download sizes first; tie-break by parameter size.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.fileSize != rhs.fileSize { return lhs.fileSize < rhs.fileSize }
    // Stable fallback to keep deterministic ordering when sizes match
    return lhs.id < rhs.id
  }
}
