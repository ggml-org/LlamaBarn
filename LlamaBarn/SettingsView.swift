import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var showQuantizedVariants = UserSettings.showQuantizedVariants

  // Version summary moved to menu footer; keep string for potential future use if needed in debug/UI tests.
  private let versionSummary =
    "v\(AppInfo.shortVersion) · build \(AppInfo.buildNumber) · llama.cpp \(AppInfo.llamaCppVersion)"

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(alignment: .leading, spacing: 12) {
        Toggle("Launch at Login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLogin.isEnabled = newValue
          }
        Toggle("Show quantized model variants", isOn: $showQuantizedVariants)
          .onChange(of: showQuantizedVariants) { _, newValue in
            UserSettings.showQuantizedVariants = newValue
          }
        Button("Check for Updates…") {
          NotificationCenter.default.post(name: .LBCheckForUpdates, object: nil)
        }
      }

      Divider()

      #if DEBUG
        VStack(alignment: .leading, spacing: 4) {
          Text(SystemMemory.formatMemory())
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      #endif
    }
    .onAppear {
      launchAtLogin = LaunchAtLogin.isEnabled
      showQuantizedVariants = UserSettings.showQuantizedVariants
    }
    .padding(24)
    .frame(minWidth: 360)
  }
}

#Preview {
  SettingsView()
}
