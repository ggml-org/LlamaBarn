import Foundation

enum ByteFormatters {
  /// Formats bytes as decimal gigabytes with two fractional digits (e.g., "3.14 GB").
  /// Uses 1 GB = 1,000,000,000 bytes to match network/download UI conventions.
  static func gbTwoDecimals(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_000_000_000.0
    return String(format: "%.2f GB", gb)
  }
}

enum DateFormatters {
  /// Cached medium style date formatter for UI labels.
  private static let medium: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df
  }()

  /// Cached month and year style date formatter for UI labels.
  private static let monthAndYear: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "MMM yyyy"
    return df
  }()

  static func mediumString(_ date: Date) -> String { medium.string(from: date) }

  static func monthAndYearString(_ date: Date) -> String { monthAndYear.string(from: date) }
}

enum TokenFormatters {
  /// Formats token counts like 262_144 as "262k" or "32k" for UI chips.
  static func shortTokens(_ tokens: Int) -> String {
    if tokens >= 1_000_000 {
      return String(format: "%.0fm", Double(tokens) / 1_000_000.0)
    } else if tokens >= 10_000 {
      return String(format: "%.0fk", Double(tokens) / 1_000.0)
    } else if tokens >= 1_000 {
      return String(format: "%.1fk", Double(tokens) / 1_000.0)
    } else {
      return "\(tokens)"
    }
  }
}
