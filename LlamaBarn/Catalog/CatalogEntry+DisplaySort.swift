import Foundation

// Shared comparator for consistent model ordering in menus.
extension CatalogEntry {
  /// Sorts smaller download sizes first; tie-break by ID for stable ordering.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.fileSize != rhs.fileSize { return lhs.fileSize < rhs.fileSize }
    return lhs.id < rhs.id
  }

  /// Orders catalog entries for display within a family submenu.
  /// Sorts by file size, which naturally orders by parameter count for full-precision models.
  static func familyDisplayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    return displayOrder(lhs, rhs)
  }
}
