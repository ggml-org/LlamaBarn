import AppKit
import Combine
import Observation
import Sparkle
import SwiftUI

@main
struct LlamaBarnApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    MenuBarExtra {
      MenuContentView(appDelegate: appDelegate)
    } label: {
      MenuIconView()
        .environment(LlamaServer.shared)
    }
    .menuBarExtraStyle(.window)
  }
}

struct MenuIconView: View {
  @Environment(LlamaServer.self) private var server

  var body: some View {
    Image(server.isRunning ? "MenuIconOn" : "MenuIconOff")
  }
}

struct MenuContentView: View {
  let appDelegate: AppDelegate

  var body: some View {
    ContentView()
      .environment(ModelManager.shared)
      .environment(LlamaServer.shared)
      .environment(updaterController)
      .onAppear {
        // Refresh the list of downloaded models when menu appears
        ModelManager.shared.refreshDownloadedModels()

        #if !DEBUG
          appDelegate.updaterController?.updater.checkForUpdatesInBackground()
        #endif
      }
  }

  private var updaterController: UpdaterController {
    if let controller = appDelegate.updaterController {
      return UpdaterController(updater: controller.updater)
    } else {
      // Create a placeholder updater for when the real one isn't ready yet
      let placeholderUpdater = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
      return UpdaterController(updater: placeholderUpdater.updater)
    }
  }
}

/// ViewModel that tracks whether the Sparkle updater can currently check for updates
/// Uses modern @Observable to track state changes for the "Check for Updates" menu item
@Observable
final class CheckForUpdatesViewModel {
  var canCheckForUpdates = false

  init(updater: SPUUpdater) {
    updater.publisher(for: \.canCheckForUpdates)
      .assign(to: \.canCheckForUpdates, on: self)
      .store(in: &cancellables)
  }

  private var cancellables = Set<AnyCancellable>()
}

/// SwiftUI button component for triggering update checks
/// Uses an intermediate view to ensure proper disabled state handling in pre-Monterey macOS
/// See: https://stackoverflow.com/questions/68553092/menu-not-updating-swiftui-bug
struct CheckForUpdatesButton: View {
  @State private var checkForUpdatesViewModel: CheckForUpdatesViewModel
  private let updater: SPUUpdater

  init(updater: SPUUpdater) {
    self.updater = updater
    self._checkForUpdatesViewModel = State(initialValue: CheckForUpdatesViewModel(updater: updater))
  }

  var body: some View {
    Button("Check for Updates…", action: updater.checkForUpdates)
      .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
  }
}

/// Environment wrapper for passing the Sparkle updater through SwiftUI views
/// Allows access to updater functionality throughout the view hierarchy
@Observable
class UpdaterController {
  let updater: SPUUpdater

  init(updater: SPUUpdater) {
    self.updater = updater
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  var updaterController: SPUStandardUpdaterController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Configure app as menu bar only (removes from Dock)
    NSApp.setActivationPolicy(.accessory)

    // Set up automatic updates using Sparkle framework
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    // Initialize the shared model library manager to scan for existing models
    _ = ModelManager.shared
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    // For menu bar apps, this is only called on launch
    #if !DEBUG
      updaterController?.updater.checkForUpdatesInBackground()
    #endif
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Gracefully stop the llama-server process when app quits
    LlamaServer.shared.stop()
  }
}
