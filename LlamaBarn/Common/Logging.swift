import Foundation

enum Logging {
  #if DEBUG
    static let subsystem = "app.llamabarn.LlamaBarn.dev"
  #else
    static let subsystem = "app.llamabarn.LlamaBarn"
  #endif
}
