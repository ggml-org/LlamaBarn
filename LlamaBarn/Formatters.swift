import Foundation

enum ByteFormatters {
  /// Formats bytes as decimal gigabytes with two fractional digits (e.g., "3.14 GB").
  /// Uses 1 GB = 1,000,000,000 bytes to match network/download UI conventions.
  static func gbTwoDecimals(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000.0
    return String(format: "%.2f GB", gb)
  }
}

