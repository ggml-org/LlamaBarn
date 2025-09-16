import Foundation

/// Centralized access to simple persisted preferences.
enum UserSettings {
  private enum Keys {
    static let showQuantizedVariants = "showQuantizedVariants"
  }

  private static let defaults = UserDefaults.standard

  /// Whether quantized model builds should appear in the catalog.
  /// Defaults to `false` to emphasize full-precision variants for most users.
  static var showQuantizedVariants: Bool {
    get {
      defaults.bool(forKey: Keys.showQuantizedVariants)
    }
    set {
      guard defaults.bool(forKey: Keys.showQuantizedVariants) != newValue else { return }
      defaults.set(newValue, forKey: Keys.showQuantizedVariants)
      NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
    }
  }
}
