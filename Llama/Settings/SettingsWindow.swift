import SwiftUI

/// Settings window controller -- manages the settings window lifecycle.
/// Uses SwiftUI for the content but AppKit for window management to ensure
/// proper behavior as a menu bar app (no dock icon, proper activation).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowController()

  private var window: NSWindow?
  private var observer: NSObjectProtocol?

  /// The selected sidebar section. Held here (rather than as SwiftUI state)
  /// because the window title tracks it.
  private let tabSelection = SettingsTabSelection()

  /// Retained so the toolbar delegate can hand out a tracking separator for
  /// this split view.
  private var splitVC: NSSplitViewController?

  private override init() {
    super.init()
    // Listen for settings show requests
    observer = NotificationCenter.default.addObserver(
      forName: .LBShowSettings, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.showSettings()
      }
    }
  }

  func showSettings() {
    // Build the window on first show; afterwards it's reused (and just
    // brought back to the front by the tail of this method).
    if window == nil {
      observeTabChanges()

      // Sidebar pane -- fixed width and non-collapsible: it's the window's
      // only navigation, so there's nothing to gain from hiding it.
      let sidebarHost = NSHostingController(rootView: SettingsSidebar(tabSelection: tabSelection))
      let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
      sidebarItem.canCollapse = false
      sidebarItem.minimumThickness = 170
      sidebarItem.maximumThickness = 170
      sidebarItem.titlebarSeparatorStyle = .none

      let detailHost = NSHostingController(rootView: SettingsDetail(tabSelection: tabSelection))
      let detailItem = NSSplitViewItem(viewController: detailHost)
      detailItem.titlebarSeparatorStyle = .none

      // An AppKit NSSplitViewController (rather than SwiftUI's
      // NavigationSplitView) is what gives a real full-height sidebar -- one
      // that runs up under the titlebar with the traffic lights sitting on
      // it, as in System Settings.
      let svc = NSSplitViewController()
      svc.addSplitViewItem(sidebarItem)
      svc.addSplitViewItem(detailItem)
      self.splitVC = svc

      let window = NSWindow(contentViewController: svc)
      window.setContentSize(NSSize(width: 700, height: 540))
      window.styleMask = [.titled, .closable, .fullSizeContentView]
      // The title names the selected section and renders in the detail pane's
      // titlebar area, courtesy of the unified toolbar style.
      window.title = tabSelection.tab.title
      window.titleVisibility = .visible
      window.titlebarSeparatorStyle = .none

      // The toolbar itself is empty, but its tracking separator is what tells
      // AppKit where the sidebar divider is -- without it the sidebar stops
      // below the titlebar instead of extending through it.
      let toolbar = NSToolbar(identifier: "SettingsToolbar")
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      window.toolbar = toolbar
      window.toolbarStyle = .unified

      window.isReleasedWhenClosed = false
      window.center()
      window.delegate = self
      self.window = window
    }

    // Show window and activate app
    NSApp.setActivationPolicy(.regular)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Keeps the window title in sync with the selected section. Observation
  /// tracking is one-shot, so the callback re-arms it.
  private func observeTabChanges() {
    withObservationTracking {
      _ = tabSelection.tab
    } onChange: {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        window?.title = tabSelection.tab.title
        observeTabChanges()
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

// MARK: - Toolbar

extension SettingsWindowController: NSToolbarDelegate {
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.sidebarTrackingSeparator]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.sidebarTrackingSeparator]
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    guard itemIdentifier == .sidebarTrackingSeparator, let splitVC else { return nil }

    return NSTrackingSeparatorToolbarItem(
      identifier: itemIdentifier,
      splitView: splitVC.splitView,
      dividerIndex: 0
    )
  }
}

/// A single settings row: a title and its description stacked in a left
/// column, with a trailing control (toggle, picker, button) in a right column.
/// The control is vertically centered against the text block, so the gap
/// between title and description stays uniform regardless of the control's
/// height -- unlike a layout where the title shares a row with the control.
private struct SettingRow<Control: View>: View {
  let title: String
  let description: String
  @ViewBuilder let control: () -> Control

  var body: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)

        Text(description)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }

      Spacer()

      control()
    }
  }
}

/// A borderless circular-arrow button that resets a setting to its default.
/// Centralizes the reset affordance's glyph, styling, and tooltip so they
/// stay consistent across rows; call sites supply only the reset action and
/// decide when to show it (typically only when a custom value is set).
private struct RestoreDefaultButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.counterclockwise")
        .foregroundStyle(.secondary)
    }
    .buttonStyle(PressableStyle())
    .help("Restore the default")
  }
}

/// The settings window's top-level sections, one per sidebar item.
enum SettingsTab: CaseIterable, Identifiable {
  case general
  case webUI
  case advanced

  var id: Self { self }

  var title: String {
    switch self {
    case .general: "General"
    case .webUI: "Web UI"
    case .advanced: "Advanced"
    }
  }

  var icon: String {
    switch self {
    case .general: "gearshape"
    case .webUI: "macwindow"
    case .advanced: "wrench.and.screwdriver"
    }
  }
}

/// The selected section, shared between the sidebar, the detail pane, and the
/// window controller (which mirrors it into the window title).
@Observable
final class SettingsTabSelection {
  var tab: SettingsTab = .general
}

/// The sidebar -- one row per section, with the open-source link pinned below.
struct SettingsSidebar: View {
  @Bindable var tabSelection: SettingsTabSelection

  /// Height of the link's one-row list: a 32pt row (measured off the live view
  /// hierarchy) plus the list's own vertical padding.
  private static let linkListHeight: CGFloat = 40

  /// The gap the list leaves between its last row and its bottom edge -- also
  /// measured, and 2pt shy of the side inset below.
  private static let linkListBottomPadding: CGFloat = 8

  /// How far the list insets a row's selection fill from the pane edge. The
  /// link row draws no fill of its own, but the sections above do -- matching
  /// it below the link keeps the column as far from the bottom edge as from
  /// the sides.
  private static let rowSideInset: CGFloat = 10

  var body: some View {
    VStack(spacing: 0) {
      List(SettingsTab.allCases, selection: $tabSelection.tab) { tab in
        Label(tab.title, systemImage: tab.icon)
      }
      // Set explicitly: hosted in an NSSplitViewItem the list doesn't reliably
      // inherit the sidebar look, and without it renders as a plain table.
      .listStyle(.sidebar)

      // The repository link. It lives in the sidebar rather than at the foot of
      // a tab because its job is to tell people who downloaded the app from the
      // website that it's open source -- that only works if it's on screen
      // whichever section they're looking at.
      //
      // It's a second one-row List rather than a button laid out by hand: the
      // row metrics (height, content inset, the icon-to-title gap) then come
      // from the same list machinery as the sections above, so the link lines up
      // with them by construction. Restating those numbers by hand does not --
      // they aren't API, and they drift with the OS.
      List {
        // Named for the destination, like the rows above -- "Open source" reads
        // as a statement (or worse, as a verb) where every other label in the
        // column is a noun. GitHub goes unsaid: the octocat names it, and the
        // full string wraps at this width.
        // A Button, not a tap gesture: it's what makes the row reachable by
        // keyboard and announced as a control by VoiceOver. `.plain` keeps the
        // label rendering exactly as the list drew it.
        Button {
          NSWorkspace.shared.open(URL(string: "https://github.com/ggml-org/Llama-macOS")!)
        } label: {
          Label {
            Text("Source code")
              .lineLimit(1)
          } icon: {
            Image(.gitHubMark)
              .resizable()
              .frame(width: 14, height: 14)
          }
          // The whole row is the target, not just the text and icon -- height
          // included, so the band above and below the label clicks too.
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          // Trailing arrow: the row leaves the app, unlike every other row in
          // the column, which switches section. It carries that on its own --
          // the row draws no hover fill, so there's no highlight to say it.
          .overlay(alignment: .trailing) {
            Image(systemName: "arrow.up.forward")
              .imageScale(.small)
              // A sidebar list insets its leading edge more than its trailing
              // one (the leading inset is the icon column's allowance), so the
              // arrow would otherwise sit nearer the edge than the octocat
              // does. Measured off the live view, the two sides differ by
              // about this much.
              .padding(.trailing, 8)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .listStyle(.sidebar)
      .scrollDisabled(true)
      // One row's worth of list, so it doesn't claim the empty column above it.
      .frame(height: Self.linkListHeight)
      // The list leaves its own gap under the row; this tops it up to the gap
      // the fill keeps at the sides, so the link isn't nearer the bottom edge
      // than the side edges.
      .padding(.bottom, Self.rowSideInset - Self.linkListBottomPadding)
    }
  }
}

/// The detail pane -- shows the selected section's form.
struct SettingsDetail: View {
  var tabSelection: SettingsTabSelection

  var body: some View {
    SettingsView(tab: tabSelection.tab)
      // Pull the grouped form up under the transparent titlebar, so its first
      // card sits just below the title rather than a band of empty space.
      .padding(.top, -20)
  }
}

/// SwiftUI view for settings content.
struct SettingsView: View {
  /// The section to render.
  var tab: SettingsTab = .general

  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var sleepIdleTime = UserSettings.sleepIdleTime
  @State private var agentMode = UserSettings.agentMode
  @State private var hfCacheDir = UserSettings.hfCacheDirectory
  @State private var globalShortcut = UserSettings.globalInputShortcut
  @State private var hfToken = UserSettings.hfToken ?? ""
  @State private var showingHFTokenSheet = false
  // Effective server port; re-read after the edit sheet saves so the row updates.
  @State private var serverPort = LlamaServer.port
  @State private var showingServerPortSheet = false
  @State private var networkAccess = UserSettings.networkAccess

  var body: some View {
    switch tab {
    case .general: generalForm
    case .webUI: webUIForm
    case .advanced: advancedForm
    }
  }

  /// The General tab -- everything that isn't specific to the web UI.
  private var generalForm: some View {
    Form {
      // Launch at login section
      Section {
        SettingRow(
          title: "Launch at login",
          description: "Sits idle in the menu bar, using minimal memory."
        ) {
          Toggle("", isOn: $launchAtLogin)
            .labelsHidden()
            .onChange(of: launchAtLogin) { _, newValue in
              _ = LaunchAtLogin.setEnabled(newValue)
            }
        }
      }

      // Sleep idle time section
      Section {
        SettingRow(
          title: "Unload when idle",
          description: "Auto-unloads model when not in use."
        ) {
          // The setting is written inside the binding (not `.onChange`) so the
          // defaults value is current before SwiftUI recomputes the body --
          // otherwise the server-command preview renders one change behind.
          PillPicker(
            options: UserSettings.SleepIdleTime.allCases.map { ($0, $0.displayName) },
            selection: Binding(
              get: { sleepIdleTime },
              set: { newValue in
                UserSettings.sleepIdleTime = newValue
                sleepIdleTime = newValue
              })
          )
        }
      }

      // Server port section
      Section {
        SettingRow(
          title: "Server port",
          description: "The port the server listens on. Default \(String(LlamaServer.defaultPort))."
        ) {
          HStack(spacing: 6) {
            // Only offer a reset when a custom port is set.
            if UserSettings.serverPort != nil {
              RestoreDefaultButton {
                // nil resets to the default; the setter restarts the server once.
                UserSettings.serverPort = nil
                serverPort = LlamaServer.port
              }
            }

            Button {
              showingServerPortSheet = true
            } label: {
              Text(String(serverPort))
            }
            .controlSize(.small)
          }
          .font(.callout)
        }
      }
      .sheet(isPresented: $showingServerPortSheet) {
        ServerPortSheet(currentPort: serverPort) { newPort in
          // nil resets to the default; the setter restarts the server once.
          UserSettings.serverPort = newPort
          serverPort = LlamaServer.port
        }
      }

      // Network access section
      Section {
        SettingRow(title: "Allow network access", description: networkAccessDescription) {
          networkAccessControl
        }
      }

      // Optional HF access token section
      Section {
        SettingRow(
          title: "Hugging Face Token",
          description: "Authenticate model downloads; optional."
        ) {
          Button {
            showingHFTokenSheet = true
          } label: {
            if hfToken.isEmpty {
              Text("Set")
            } else {
              Text(truncatedToken(hfToken))
            }
          }
          .font(.callout)
          .controlSize(.small)
        }
      }
      .sheet(isPresented: $showingHFTokenSheet) {
        HFTokenSheet(currentToken: hfToken) { newToken in
          hfToken = newToken
          UserSettings.hfToken = newToken.isEmpty ? nil : newToken
        }
      }
      // HF cache directory section
      Section {
        SettingRow(
          title: "Model directory",
          description: "Where downloaded models are stored."
        ) {
          HStack(spacing: 6) {
            // Only offer a reset when a custom directory is set.
            if UserSettings.hasCustomHFCacheDirectory {
              RestoreDefaultButton {
                UserSettings.hfCacheDirectory = UserSettings.defaultHFCacheDirectory
                hfCacheDir = UserSettings.hfCacheDirectory
                ModelManager.shared.refreshDownloadedModels()
              }
            }

            // One button opens the picker; it shows the current path (already
            // middle-truncated by `abbreviatedPath`) next to a folder icon.
            Button {
              chooseCacheFolder()
            } label: {
              HStack(spacing: 6) {
                Text(abbreviatedPath(hfCacheDir))
                  .lineLimit(1)

                Image(systemName: "folder")
              }
            }
            .controlSize(.small)
          }
          .font(.callout)
        }
      }
    }
    .formStyle(.grouped)
  }

  /// The Web UI tab -- settings that shape the chat interface the server
  /// serves: what models are allowed to do in it, and how to summon it.
  private var webUIForm: some View {
    Form {
      // Agent mode section
      Section {
        SettingRow(
          title: "Agent mode",
          description:
            "Lets models read and edit files and run commands on this Mac. With network access on, that applies to anyone on the network too."
        ) {
          // The setting is written inside the binding (not `.onChange`) so the
          // defaults value is current before SwiftUI recomputes the body --
          // otherwise the server-command preview renders one toggle behind.
          // The setter posts the settings-change notification, which restarts
          // the server with/without `--agent`.
          Toggle(
            "",
            isOn: Binding(
              get: { agentMode },
              set: { newValue in
                UserSettings.agentMode = newValue
                agentMode = newValue
              })
          )
          .labelsHidden()
        }
      }

      // Global-input shortcut section. It belongs here rather than in General:
      // the panel it opens only hands the prompt off to the web UI, so the
      // setting is meaningless to someone who uses the server through the API
      // or a third-party app.
      Section {
        SettingRow(
          title: "Quick prompt",
          description: "A keyboard shortcut that opens a prompt window from any app."
        ) {
          HStack(spacing: 6) {
            // Resetting means clearing: no shortcut is the default.
            if globalShortcut != nil {
              RestoreDefaultButton {
                UserSettings.globalInputShortcut = nil
                globalShortcut = nil
              }
            }

            ShortcutRecorder(
              combo: Binding(
                get: { globalShortcut },
                set: { newValue in
                  // The setter posts the change notification that makes the
                  // controller re-register the hotkey immediately.
                  UserSettings.globalInputShortcut = newValue
                  globalShortcut = newValue
                })
            )
          }
          .font(.callout)
        }
      }
    }
    .formStyle(.grouped)
  }

  /// The Advanced tab -- power-user surfaces that aren't settings to change.
  private var advancedForm: some View {
    Form {
      // Server command section -- exposes the actual `llama serve` invocation
      // behind the GUI. It's read-only, but reflects the other tabs' settings:
      // change the port, idle timeout, or model directory and it updates.
      // Shown expanded: this tab exists to be read, so hiding its one item
      // behind a disclosure would just add a click.
      Section {
        VStack(alignment: .leading, spacing: 2) {
          Text("Server command")

          Text("The command that starts the server, reflecting your settings.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }

        // The command itself: monospaced, wrapping, and selectable so a user
        // can read or grab any part of it. Lightly syntax-highlighted to make
        // the structure (env vars, flags, values) easier to scan. Its own row
        // in the section (no panel of its own), so the form draws its native
        // separator between the header and the command.
        Text(highlightedCommand)
          .font(.system(size: 11, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
  }

  /// This Mac's Tailscale address, re-read on every render rather than
  /// captured: signing in, signing out, or switching tailnets while this
  /// window is open all change the answer, and a stale one makes the row
  /// describe a state the server isn't in.
  private var tailscaleAddress: String? {
    TailscaleInterface.address()
  }

  /// The control for network access: a three-way picker when Tailscale is
  /// available, otherwise the plain on/off it would collapse to anyway. A
  /// hand-set address gets neither -- it was configured outside the app, so
  /// the app reports it rather than offering to overwrite it.
  @ViewBuilder private var networkAccessControl: some View {
    if case .custom(let address) = networkAccess {
      Text(address)
        .font(.callout)
        .foregroundStyle(.secondary)
    } else if tailscaleAddress != nil || networkAccess == .tailscale {
      PillPicker(
        options: [
          (UserSettings.NetworkAccess.off, "Off"),
          (.tailscale, "Tailscale"),
          (.localNetwork, "This network"),
        ],
        selection: networkAccessBinding
      )
      .help(tailscaleAddress.map { "Tailscale: \($0)" } ?? "Tailscale is not available")
    } else {
      Toggle(
        "",
        isOn: Binding(
          get: { networkAccess == .localNetwork },
          set: { networkAccessBinding.wrappedValue = $0 ? .localNetwork : .off })
      )
      .labelsHidden()
    }
  }

  /// Writes through to defaults before updating the mirror, so the
  /// server-command preview on the Advanced tab doesn't render one change
  /// behind. The setter posts the change notification, which restarts the
  /// server on the new host.
  private var networkAccessBinding: Binding<UserSettings.NetworkAccess> {
    Binding(
      get: { networkAccess },
      set: { newValue in
        UserSettings.setNetworkAccess(newValue)
        networkAccess = UserSettings.networkAccess
      })
  }

  /// Says what the current choice actually means. Worth varying: the warning
  /// that matters for `.localNetwork` (no password, anyone on this wifi) is
  /// simply untrue of Tailscale, which authenticates every device itself.
  private var networkAccessDescription: String {
    switch networkAccess {
    case .off:
      return "Only this Mac can reach the server."
    case .tailscale where tailscaleAddress == nil:
      // Selected, but there's no address to bind: the server has fallen back
      // to loopback on its own. Say so rather than describing what the setting
      // would do if Tailscale were running.
      return "Tailscale isn't running, so only this Mac can reach the server for now."
    case .tailscale:
      return "Reachable from your Tailscale devices, anywhere. Stays invisible on the network you're on."
    case .localNetwork:
      return "Anyone on your current network can reach the server. It has no password -- only turn this on for a network you trust."
    case .custom:
      return "Bound to an address set outside the app."
    }
  }

  /// The shell command that starts the server, built from the current
  /// settings. Reads the `@State` mirrors of the relevant settings (port, idle
  /// timeout, model directory) so SwiftUI recomputes this whenever one of them
  /// changes -- the actual spec is sourced from `LlamaServer` so it stays in
  /// lockstep with what `start()` runs.
  private var serverCommand: String {
    _ = (serverPort, sleepIdleTime, hfCacheDir, agentMode, networkAccess)  // establish SwiftUI dependencies
    return LlamaServer.buildLaunchSpec()?.displayCommand ?? "llama not installed"
  }


  /// Appearance-adaptive palette for the server-command syntax highlighting.
  /// Kept deliberately low-saturation and Xcode-flavored so the block reads as
  /// "structured" rather than a rainbow. Each color carries a light and a dark
  /// variant via `NSColor.dynamic`. Tuned in a standalone playground.
  private enum CommandColors {
    /// `--flags` and the `export` keyword.
    static let flag = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 45 / 255, green: 108 / 255, blue: 168 / 255, alpha: 1),
      dark: NSColor(srgbRed: 111 / 255, green: 176 / 255, blue: 232 / 255, alpha: 1)))
    /// Env-var names (`KEY` in `KEY=value`).
    static let env = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 58 / 255, green: 125 / 255, blue: 92 / 255, alpha: 1),
      dark: NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 168 / 255, alpha: 1)))
    /// The `serve` subcommand.
    static let serve = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 31 / 255, green: 45 / 255, blue: 92 / 255, alpha: 1),
      dark: NSColor(srgbRed: 155 / 255, green: 180 / 255, blue: 255 / 255, alpha: 1)))
    /// The leading binary path.
    static let path = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 43 / 255, green: 58 / 255, blue: 103 / 255, alpha: 1),
      dark: NSColor(srgbRed: 155 / 255, green: 180 / 255, blue: 255 / 255, alpha: 1)))
    /// Integer values (ports, counts, seconds).
    static let int = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 176 / 255, green: 105 / 255, blue: 31 / 255, alpha: 1),
      dark: NSColor(srgbRed: 217 / 255, green: 165 / 255, blue: 102 / 255, alpha: 1)))
    /// String / path values.
    static let string = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 160 / 255, green: 74 / 255, blue: 63 / 255, alpha: 1),
      dark: NSColor(srgbRed: 224 / 255, green: 143 / 255, blue: 128 / 255, alpha: 1)))
  }

  /// `serverCommand` with light syntax highlighting applied per token, so the
  /// command's structure is easy to scan. Purely cosmetic -- the underlying
  /// text is identical to `serverCommand`. Coloring rules, by token shape:
  /// `export` and `--flags` share the flag color; env-var names read as keys;
  /// the `serve` subcommand and the leading binary path each get their own
  /// tint; values (env-var RHS and flag arguments) color as integers or
  /// strings; the trailing line-continuation `\` is dimmed.
  private var highlightedCommand: AttributedString {
    var result = AttributedString()

    let lines = serverCommand.components(separatedBy: "\n")
    for (lineIdx, line) in lines.enumerated() {
      if lineIdx > 0 { result.append(AttributedString("\n")) }

      // Preserve the leading indent verbatim, then tokenize the rest.
      let indent = line.prefix { $0 == " " }
      result.append(AttributedString(String(indent)))

      let tokens = tokenize(String(line.dropFirst(indent.count)))
      // `prevWasFlag` marks that the previous token was a `--flag`, so this
      // token is its value and colors as a value rather than by its own shape.
      // `inComment` latches at a `#` token: it and everything after it on the
      // line (the "# custom arguments" tag) dims as a comment.
      var prevWasFlag = false
      var inComment = false
      for (tokenIdx, token) in tokens.enumerated() {
        if tokenIdx > 0 { result.append(AttributedString(" ")) }
        if inComment || token.hasPrefix("#") {
          inComment = true
          var attr = AttributedString(token)
          attr.foregroundColor = .secondary
          result.append(attr)
          continue
        }
        result.append(highlight(token, isFirstOnLine: tokenIdx == 0, isFlagValue: prevWasFlag))
        prevWasFlag = token.hasPrefix("--")
      }
    }

    return result
  }

  /// Splits a command line into space-delimited tokens, but keeps a
  /// single-quoted span (which may contain spaces, e.g. the `models.ini` path)
  /// as a single token so it can be colored as one string.
  private func tokenize(_ line: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var inQuotes = false
    for char in line {
      if char == "'" {
        inQuotes.toggle()
        current.append(char)
      } else if char == " " && !inQuotes {
        tokens.append(current)
        current = ""
      } else {
        current.append(char)
      }
    }
    tokens.append(current)
    return tokens
  }

  /// Colors a single token according to its shape and position (see
  /// `highlightedCommand`).
  private func highlight(_ token: String, isFirstOnLine: Bool, isFlagValue: Bool) -> AttributedString {
    var attr = AttributedString(token)

    if token == "\\" {
      // Trailing line-continuation backslash -- dim, it's just glue.
      attr.foregroundColor = .secondary
    } else if token == "export" {
      // The `export` keyword -- same tint as flags.
      attr.foregroundColor = CommandColors.flag
    } else if token == "serve" {
      // The subcommand.
      attr.foregroundColor = CommandColors.serve
    } else if token.hasPrefix("--") {
      // A flag.
      attr.foregroundColor = CommandColors.flag
    } else if isFlagValue {
      // A flag's argument -- color by its value shape.
      attr.foregroundColor = valueColor(for: token)
    } else if let eq = token.firstIndex(of: "="),
      token[..<eq].allSatisfy({ $0.isUppercase || $0 == "_" }), !token.isEmpty
    {
      // An env-var assignment `KEY=value`: tint the key, color the value by its
      // shape, and leave the `=` default. Built by concatenation so there's no
      // index math or empty-value edge case.
      let value = String(token[token.index(after: eq)...])
      var key = AttributedString(token[..<eq])
      key.foregroundColor = CommandColors.env
      var val = AttributedString(value)
      val.foregroundColor = valueColor(for: value)
      return key + AttributedString("=") + val
    } else if isFirstOnLine && token.contains("/") {
      // The leading binary path on the `llama serve` line.
      attr.foregroundColor = CommandColors.path
    }

    return attr
  }

  /// The color for a value token -- integer tint for all-digit values,
  /// string tint otherwise (paths, quoted strings).
  private func valueColor(for token: String) -> Color {
    let allDigits = !token.isEmpty && token.allSatisfy { $0.isNumber }
    return allDigits ? CommandColors.int : CommandColors.string
  }

  /// Opens a folder picker and updates the HF cache directory
  private func chooseCacheFolder() {
    let selection = ModalPresentation.run { () -> URL? in
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.canCreateDirectories = true
      panel.allowsMultipleSelection = false
      panel.message = "Choose a directory for downloaded models"
      panel.prompt = "Select"

      // Start in the current cache directory
      panel.directoryURL = hfCacheDir

      return panel.runModal() == .OK ? panel.url : nil
    }

    if let url = selection {
      UserSettings.hfCacheDirectory = url
      // Re-read for the canonical representation (the panel's URL may
      // differ in trailing slash / symlink resolution)
      hfCacheDir = UserSettings.hfCacheDirectory
      ModelManager.shared.refreshDownloadedModels()
    }
  }

  /// Truncated HF token for display -- e.g. "hf_...xyz1"
  private func truncatedToken(_ token: String) -> String {
    guard token.count > 7 else { return token }
    return "\(token.prefix(3))...\(token.suffix(4))"
  }

  /// Abbreviates a path for display: replaces the home directory with `~`,
  /// then middle-truncates to `maxLen` characters so a long path can't stretch
  /// the layout. Capping the string (rather than the view's width) lets the
  /// label hug short paths instead of always reserving the full cap width.
  private func abbreviatedPath(_ url: URL, maxLen: Int = 38) -> String {
    let path = url.path
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let abbreviated = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path

    guard abbreviated.count > maxLen else { return abbreviated }
    // Keep the head and tail, eliding the middle -- the ends carry the most
    // meaning (the `~`/root and the leaf directory).
    let keep = maxLen - 1  // reserve one char for the ellipsis
    let head = abbreviated.prefix(keep - keep / 2)
    let tail = abbreviated.suffix(keep / 2)
    return "\(head)…\(tail)"
  }
}

/// Compact pill-style segmented picker -- the SwiftUI counterpart of the
/// menu's context tier picker (ExpandedModelDetailsView): a row of clickable
/// pills on a solid neutral background (no outline), echoing the native
/// switch and button styling in the settings window. The selected pill gets
/// a thumb-like solid fill and primary text; hairline dividers separate
/// unselected neighbors.
struct PillPicker<Option: Hashable>: View {
  let options: [(value: Option, label: String)]
  @Binding var selection: Option

  private var selectedIdx: Int {
    options.firstIndex { $0.value == selection } ?? 0
  }

  var body: some View {
    HStack(spacing: 1) {
      ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
        if idx > 0 {
          divider(hidden: idx == selectedIdx || idx - 1 == selectedIdx)
        }

        let selected = idx == selectedIdx
        // A plain Button (not onTapGesture) -- gestures on Form rows are
        // unreliable on macOS, buttons always receive clicks
        Button {
          selection = option.value
        } label: {
          Text(option.label)
            .font(.callout)
            // All segments use primary text -- dimming the unselected ones
            // reads as disabled; the thumb alone marks the selection (matches
            // native segmented controls)
            .foregroundStyle(Color(nsColor: Theme.Colors.textPrimary))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
              // Thumb-like fill, lighter than the track in both appearances
              selected ? Color(nsColor: Theme.Colors.pillThumb) : .clear,
              in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
      }
    }
    // Equal breathing room between the pills and the row edge on all sides
    .padding(.horizontal, 3)
    .padding(.vertical, 3)
    .background(Color(nsColor: Theme.Colors.pillTrack), in: RoundedRectangle(cornerRadius: 6))
  }

  /// Hairline divider; hidden ones keep their layout slot (clear color) so
  /// pills don't shift as the selection moves. The dividers adjacent to the
  /// selected pill are hidden -- its background already delimits the gap.
  private func divider(hidden: Bool) -> some View {
    Rectangle()
      .fill(hidden ? Color.clear : Color(nsColor: Theme.Colors.separator))
      .frame(width: 1, height: 8)
  }
}

/// Sheet for editing the Hugging Face access token.
struct HFTokenSheet: View {
  let currentToken: String
  let onSave: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var tokenText: String = ""

  private var trimmed: String {
    tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Hugging Face Token")
          .font(.headline)

        Text("Used to download gated and private models.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      TextEditor(text: $tokenText)
        .font(.system(size: 11, design: .monospaced))
        .frame(height: 50)
        .scrollContentBackground(.hidden)
        .padding(.vertical, 4)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )

      HStack {
        // Validation hint replaces the link once there's something to correct.
        if !trimmed.isEmpty && !UserSettings.isValidHFToken(trimmed) {
          Text("Invalid token format")
            .font(.caption)
            .foregroundStyle(.red)
        } else {
          // The sheet is modal, so it needs its own way out to the token page.
          Link(
            "Create a token \u{2197}",
            destination: URL(string: "https://huggingface.co/settings/tokens")!
          )
          .font(.caption)
        }

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("Save") {
          onSave(trimmed)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!trimmed.isEmpty && !UserSettings.isValidHFToken(trimmed))
      }
    }
    .padding(20)
    .frame(width: 400)
    .onAppear {
      tokenText = currentToken
    }
  }
}

/// Sheet for editing the server port. `onSave` receives the new port, or nil
/// to reset to the default (when the field is cleared or set to the default).
struct ServerPortSheet: View {
  let currentPort: Int
  let onSave: (Int?) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var portText: String = ""
  // Set only after a failed Save attempt, so the error isn't flashed while
  // the user is still editing; cleared as soon as the field changes again.
  @State private var error: String?

  private var trimmed: String {
    portText.trimmingCharacters(in: .whitespaces)
  }

  /// Parsed port, or nil if the field isn't a valid in-range number.
  private var parsedPort: Int? {
    guard let port = Int(trimmed), UserSettings.serverPortRange.contains(port) else {
      return nil
    }
    return port
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Server Port")
        .font(.headline)

      TextField(String(LlamaServer.defaultPort), text: $portText)
        .textFieldStyle(.roundedBorder)
        // Enter saves, matching the Save button.
        .onSubmit { save() }
        // Editing clears a stale error so it never lingers mid-type.
        .onChange(of: portText) { _, _ in error = nil }

      HStack {
        // Validation hint -- shown only after a failed Save, not while typing.
        if let error {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("Save") {
          save()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 320)
    .onAppear {
      portText = String(currentPort)
    }
  }

  /// Saves the edited port. Empty or the default resets the override (nil).
  /// Otherwise the value must be in range and the port free to bind -- on
  /// failure the sheet stays open with an explanation.
  private func save() {
    if trimmed.isEmpty || parsedPort == LlamaServer.defaultPort {
      onSave(nil)
      dismiss()
      return
    }

    guard let port = parsedPort else {
      let range = UserSettings.serverPortRange
      error = "Port must be between \(String(range.lowerBound)) and \(String(range.upperBound))."
      return
    }

    // Re-selecting the current port is a no-op; skip the availability check,
    // which would otherwise fail because our own server already holds it.
    if port != currentPort && !LlamaServer.isPortAvailable(port) {
      error = "Port \(String(port)) is already in use. Pick another."
      return
    }

    onSave(port)
    dismiss()
  }
}

#Preview {
  SettingsView()
}
