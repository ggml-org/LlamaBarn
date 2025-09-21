import Foundation

// Shared comparator for consistent model ordering in menus.
extension ModelCatalogEntry {
  /// Sorts smaller download sizes first; tie-break by parameter size.
  static func displayOrder(_ lhs: ModelCatalogEntry, _ rhs: ModelCatalogEntry) -> Bool {
    if lhs.fileSizeMB != rhs.fileSizeMB { return lhs.fileSizeMB < rhs.fileSizeMB }
    // Stable fallback to keep deterministic ordering when sizes match
    return lhs.id < rhs.id
  }
}
