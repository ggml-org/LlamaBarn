import Foundation

// Shared comparator for consistent model ordering in menus.
extension CatalogEntry {
  /// Groups models by family, then sorts by size within each family.
  /// Used for installed models list to keep related models together.
  static func displayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.family != rhs.family { return lhs.family < rhs.family }
    if lhs.fileSize != rhs.fileSize { return lhs.fileSize < rhs.fileSize }
    return lhs.id < rhs.id
  }

  /// Orders catalog entries for display within a family submenu.
  /// Sorts by file size, which naturally orders by parameter count for full-precision models.
  static func familyDisplayOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
    if lhs.fileSize != rhs.fileSize { return lhs.fileSize < rhs.fileSize }
    return lhs.id < rhs.id
  }
}
