import AppKit
import LaunchAtLogin
import Sparkle
import SwiftUI

struct ContentView: View {
  // Access shared instances through environment
  @Environment(ModelManager.self) var modelManager
  @Environment(LlamaServer.self) var llamaServer
  @Environment(UpdaterController.self) var updaterController
  @Environment(\.dismiss) private var dismiss

  @State private var isServerStatusHovered = false
  @State private var isMoreMenuHovered = false
  @State private var showAvailableInfo = false
  @Environment(\.colorScheme) private var colorScheme

  // Filter models by download status for display organization
  private var downloadedModels: [ModelCatalogEntry] {
    modelManager.downloadedModels
  }

  // Models currently being downloaded
  private var downloadingModels: [ModelCatalogEntry] {
    ModelCatalog.models.filter { model in
      if case .downloading = modelManager.getModelStatus(model) {
        return true
      }
      return false
    }
  }

  // Group all models by family for the menu interface
  private var allModelFamilies: [(family: String, models: [ModelCatalogEntry], icon: String)] {
    Dictionary(grouping: ModelCatalog.models, by: { $0.family })
      .map { (family, models) in
        (family: family, models: models, icon: models.first?.icon ?? "ModelLogos/OpenAI")
      }
      .sorted { $0.family < $1.family }
  }

  // Utility to open URLs in the default system browser
  private func openURL(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
  }

  var body: some View {
    // Main container for the popover content with organized model sections
    VStack(alignment: .leading, spacing: 0) {
      // Header with app title and settings menu
      HStack {
        Text("LlamaBarn")
          .font(.system(size: 14, weight: .regular))

        if llamaServer.memoryUsageMB > 0 {
          let memoryUsageGB = llamaServer.memoryUsageMB / 1024.0
          Text(String(format: "(%.2f GB)", memoryUsageGB))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.leading, 4)
        }

        Spacer()

        Menu {
          LaunchAtLogin.Toggle {
            Text("Launch at Login")
          }

          Divider()

          CheckForUpdatesButton(updater: updaterController.updater)

          Divider()

          VStack(alignment: .leading, spacing: 2) {
            Text(
              "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
            )
            Text("llama.cpp \(llamaServer.getLlamaCppVersion())")
          }
          .font(.caption)
          .foregroundColor(.secondary)

          Divider()

          Button("Quit") {
            NSApplication.shared.terminate(nil)
          }
          .keyboardShortcut("q", modifiers: .command)
        } label: {
          Image(systemName: "ellipsis")
            .foregroundColor(.secondary)
            .frame(width: 32, height: 32)
            .background(
              isMoreMenuHovered
                ? Color.primary.opacity(0.05) : Color.clear
            )
            .contentShape(Rectangle())
            .cornerRadius(4)
            .onHover { hovering in
              isMoreMenuHovered = hovering
            }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 8)

      // Visual separator between header and content
      Divider()
        .padding(.horizontal, 8)

      // Organized model sections: Downloaded models first, then available for download
      VStack(spacing: 0) {
        // Downloaded and downloading models section - shows models ready to run and currently downloading
        if !downloadedModels.isEmpty || !downloadingModels.isEmpty {
          VStack(spacing: 4) {
            // Section header
            Text("Installed")
              .font(.subheadline)
              .foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 8)

            // List of downloaded models with run/stop controls
            VStack(spacing: 0) {
              ForEach(downloadedModels, id: \.id) { model in
                ModelRow(model: model)
              }

              // Show downloading models in the installed section
              ForEach(downloadingModels, id: \.id) { model in
                ModelRow(model: model)
              }
            }
          }
          .padding(.vertical, 8)

          // Separator between sections (only if both sections have content)
          if !allModelFamilies.isEmpty {
            Divider()
              .padding(.horizontal, 8)
          }
        }

        // Available model families section - shows expandable menus for each family
        if !allModelFamilies.isEmpty {
          VStack(spacing: 4) {
            // Section header
            HStack {
              Text("Available")

              Spacer()
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)

            // List of model families that can be downloaded
            VStack(spacing: 0) {
              ForEach(allModelFamilies, id: \.family) { familyInfo in
                ModelFamilyRow(
                  family: familyInfo.family,
                  models: familyInfo.models,
                  icon: familyInfo.icon
                )
              }
            }
          }
          .padding(.vertical, 8)
        }
      }

      // Visual separator between model list and server status
      Divider()
        .padding(.horizontal, 8)

      // Server status footer - shows current llama-server state and web interface link
      ServerStatusView(llamaServer: llamaServer, isHovered: $isServerStatusHovered) {
        if llamaServer.isRunning {
          openURL("http://localhost:\(LlamaServer.defaultPort)/")
          dismiss()
        }
      }
      .padding(.vertical, 8)

      // dev-only status information
      #if DEBUG
        Divider()
          .padding(.horizontal, 8)

        HStack {
          Image(systemName: "memorychip")
            .font(.system(size: 14))
            .frame(width: 18, height: 18)
            .padding(.trailing, 4)
            .opacity(0.9)

          Text(SystemMemory.formatMemory())
            .font(.system(size: 12))
            .foregroundColor(.secondary)

          Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
      #endif
    }
    .padding(.horizontal, 8)
    .frame(width: 300)
    .task {
      // Refresh downloaded models when view appears
      modelManager.refreshDownloadedModels()
    }
  }
}

#Preview {
  // SwiftUI preview for design-time development and testing
  // Create a mock UpdaterController for preview purposes
  let mockUpdater = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

  ContentView()
    .environment(UpdaterController(updater: mockUpdater.updater))
    .environment(ModelManager.shared)
    .environment(LlamaServer.shared)
}
