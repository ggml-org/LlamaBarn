import Cocoa

/// AppleScript command handler for "show global input"
/// Usage: tell application "Llama" to show global input
///
/// Opens the global-input capture panel on demand, so we can bring the panel up
/// while iterating on it.
/// DEBUG-only: a no-op in release builds -- it's a development affordance, not
/// a supported scripting interface.
class ShowGlobalInputCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    #if DEBUG
      NotificationCenter.default.post(name: .LBShowGlobalInput, object: nil)
    #endif
    return nil
  }
}
