import AppKit
import Foundation
import LaunchAtLogin

/// Controls the status bar item and its AppKit menu.
/// First iteration: only an "Installed" section listing downloaded models.
/// Each model row is a custom NSView that lets users start/stop the server
/// without dismissing the menu (like the Wi‑Fi menu behavior).
final class AppMenuController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: ModelManager
  private let server: LlamaServer
  private let llamaCppVersion: String
  private var titleView: HeaderMenuItemView?
  // No stored reference needed for the memory footer.
  private var observers: [NSObjectProtocol] = []

  init(modelManager: ModelManager = .shared, server: LlamaServer = .shared) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager
    self.server = server
    self.llamaCppVersion = AppMenuController.readLlamaCppVersion()
    super.init()
    configureStatusItem()
  }

  private static func readLlamaCppVersion() -> String {
    // Canonical location: bundle resource "version.txt". Fallback to "unknown".
    if let path = Bundle.main.path(forResource: "version", ofType: "txt"),
      let content = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(
        in: .whitespacesAndNewlines),
      !content.isEmpty
    {
      return content
    }
    return "unknown"
  }

  private func configureStatusItem() {
    if let button = statusItem.button {
      // Use existing template images if available; fallback to a simple system symbol
      button.image =
        NSImage(named: server.isRunning ? "MenuIconOn" : "MenuIconOff")
        ?? NSImage(systemSymbolName: "brain", accessibilityDescription: nil)
      button.image?.isTemplate = true
    }

    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    statusItem.menu = menu
  }

  // MARK: - NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    rebuildMenu(menu)
  }

  func menuWillOpen(_ menu: NSMenu) {
    // Ensure we have the latest list of installed models
    modelManager.refreshDownloadedModels()
    addObservers()
  }

  func menuDidClose(_ menu: NSMenu) {
    removeObservers()
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()
    addHeader(to: menu)
    addInstalled(to: menu)
    addCatalog(to: menu)
    addSettings(to: menu)
    addQuit(to: menu)
  }

  private func addHeader(to menu: NSMenu) {
    let tView = HeaderMenuItemView(server: server, llamaCppVersion: llamaCppVersion)
    titleView = tView
    menu.addItem(NSMenuItem.viewItem(with: tView, minHeight: 40))
    menu.addItem(.separator())
  }

  private func addInstalled(to menu: NSMenu) {
    let header = makeSectionHeaderItem("Installed models")
    // Tag the Installed header so we can locate this section reliably later.
    header.representedObject = "installed-header"
    menu.addItem(header)

    let downloadingModels = ModelCatalog.allEntries().filter { m in
      if case .downloading = modelManager.getModelStatus(m) { return true }
      return false
    }
    let installed = modelManager.downloadedModels + downloadingModels
    if installed.isEmpty {
      let emptyItem = NSMenuItem()
      emptyItem.title = "No installed models"
      emptyItem.isEnabled = false
      menu.addItem(emptyItem)
    } else {
      for model in installed {
        let view = InstalledModelMenuItemView(model: model, server: server, modelManager: modelManager) {
          [weak self] in
          if let menu = self?.statusItem.menu { self?.rebuildMenu(menu) }
        }
        menu.addItem(NSMenuItem.viewItem(with: view, minHeight: 28))
      }
    }
  }

  private func addCatalog(to menu: NSMenu) {
    let families = ModelCatalog.uiFamilies
    guard !families.isEmpty else { return }
    menu.addItem(.separator())
    menu.addItem(makeSectionHeaderItem("Catalog"))

    for family in families.sorted(by: { $0.name < $1.name }) {
      let models = family.variants.flatMap { variant in
        variant.builds.map { $0.asEntry(family: family, variant: variant) }
      }
      let famView = FamilyHeaderMenuItemView(family: family.name, models: models, modelManager: modelManager)
      let familyItem = NSMenuItem.viewItem(with: famView)
      familyItem.isEnabled = true  // must be enabled so the submenu opens on hover
      familyItem.representedObject = family.name as NSString
      let submenu = NSMenu(title: family.name)
      submenu.autoenablesItems = false
      // Add family "business card" header inside the submenu
      let latestRelease = family.variants.map { $0.releaseDate }.max()
      let maxContext = family.variants.map { $0.contextLength }.max()
      let infoView = FamilyInfoMenuItemView(
        familyName: family.name,
        iconName: family.icon,
        blurb: family.blurb,
        releaseDate: latestRelease,
        contextTokens: maxContext
      )
      submenu.addItem(NSMenuItem.viewItem(with: infoView, minHeight: 56))
      submenu.addItem(.separator())
      let sortedModels = models.sorted(by: ModelCatalogEntry.displayOrder(_:_:))
      for model in sortedModels {
        let view = VariantMenuItemView(model: model, modelManager: modelManager) {
          [weak self] in
          // Keep submenu open: refresh views and ensure the Installed section
          // gains a row for the newly-downloading model without a full rebuild.
          self?.didChangeDownloadStatus(for: model)
        }
        let modelItem = NSMenuItem.viewItem(with: view, minHeight: 26)
        modelItem.representedObject = model.id as NSString
        submenu.addItem(modelItem)
      }
      familyItem.submenu = submenu
      menu.addItem(familyItem)
    }
  }

  // Server status is shown in the header now; dedicated server row removed.

  private func addSettings(to menu: NSMenu) {
    menu.addItem(.separator())
    // Settings submenu container
    let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
    let settingsMenu = NSMenu(title: "Settings")
    settingsMenu.autoenablesItems = false

    // Launch at Login toggle
    let launchAtLogin = NSMenuItem(
      title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    launchAtLogin.target = self
    launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
    settingsMenu.addItem(launchAtLogin)

    // Sparkle updates
    let updatesItem = NSMenuItem(
      title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    updatesItem.target = self
    settingsMenu.addItem(updatesItem)

    // App and component versions (moved from header)
    do {
      let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
      let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
      let versionsItem = NSMenuItem()
      versionsItem.isEnabled = false
      let versionsText = "v\(ver) · build \(build) · llama.cpp \(llamaCppVersion)"
      versionsItem.attributedTitle = NSAttributedString(
        string: versionsText,
        attributes: [
          .font: NSFont.systemFont(ofSize: 11),
          .foregroundColor: NSColor.secondaryLabelColor,
        ]
      )
      settingsMenu.addItem(.separator())
      settingsMenu.addItem(versionsItem)
    }

    #if DEBUG
      // Memory info (debug only), visually subdued
      settingsMenu.addItem(.separator())
      let memItem = NSMenuItem()
      memItem.isEnabled = false
      let memText = SystemMemory.formatMemory()
      memItem.attributedTitle = NSAttributedString(
        string: memText,
        attributes: [
          .font: NSFont.systemFont(ofSize: 11),
          .foregroundColor: NSColor.secondaryLabelColor,
        ]
      )
      settingsMenu.addItem(memItem)
    #endif

    settingsItem.submenu = settingsMenu
    menu.addItem(settingsItem)
  }

  private func addQuit(to menu: NSMenu) {
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
  }

  // MARK: - Live updates without closing submenus

  /// Called from variant rows when a user starts/cancels a download.
  /// Keeps the submenu open by updating views in place and ensuring the
  /// Installed section reflects membership for downloading items.
  private func didChangeDownloadStatus(for model: ModelCatalogEntry) {
    // Reflect membership changes in the Installed section without full rebuild.
    switch modelManager.getModelStatus(model) {
    case .downloading:
      ensureInstalledRow(for: model)
    case .available:
      // Remove transient row that we might have inserted when download started.
      removeInstalledRow(for: model)
    case .downloaded:
      // Will appear via downloadedModels; no action needed here.
      break
    }
    performRefresh()
  }

  /// Inserts an Installed row for a model that just transitioned to `.downloading`,
  /// without rebuilding the entire menu. If the row already exists, no-op.
  private func ensureInstalledRow(for model: ModelCatalogEntry) {
    guard let menu = statusItem.menu else { return }
    guard var range = installedSectionRange(in: menu) else { return }

    // If already present, nothing to do
    let alreadyPresent = menu.items[range].contains {
      ($0.representedObject as? NSString) == (model.id as NSString)
    }
    if alreadyPresent { return }

    // Remove placeholder if present, then recompute range to be safe
    if let placeholderRelative = menu.items[range].firstIndex(where: { !$0.isEnabled && $0.title == "No installed models" }) {
      let absolute = placeholderRelative + range.startIndex
      menu.removeItem(at: absolute)
      if let newRange = installedSectionRange(in: menu) { range = newRange }
    }

    // Insert a new InstalledModelMenuItemView row at the end of the Installed section
    let view = InstalledModelMenuItemView(model: model, server: server, modelManager: modelManager) { [weak self] in
      // Deletions still rebuild to simplify membership updates.
      if let menu = self?.statusItem.menu { self?.rebuildMenu(menu) }
    }
    let item = NSMenuItem.viewItem(with: view, minHeight: 28)
    item.representedObject = model.id as NSString
    menu.insertItem(item, at: range.endIndex)
  }

  /// Removes an Installed row previously inserted for a model that is no longer downloading
  /// and not yet fully downloaded, without rebuilding the entire menu.
  private func removeInstalledRow(for model: ModelCatalogEntry) {
    guard let menu = statusItem.menu else { return }
    guard let range = installedSectionRange(in: menu) else { return }
    if let idx = menu.items[range].firstIndex(where: { ($0.representedObject as? NSString) == (model.id as NSString) }) {
      let absolute = idx + range.startIndex
      menu.removeItem(at: absolute)
      // If Installed section becomes empty, show the placeholder again
      let remaining = menu.items[installedSectionRange(in: menu) ?? range]
      let hasRows = remaining.contains { $0.view is InstalledModelMenuItemView }
      if !hasRows {
        let emptyItem = NSMenuItem()
        emptyItem.title = "No installed models"
        emptyItem.isEnabled = false
        if let newRange = installedSectionRange(in: menu) {
          menu.insertItem(emptyItem, at: newRange.startIndex)
        }
      }
    }
  }

  /// Returns the open interval range [start, end) of items that belong to the Installed section.
  /// The range starts just after the Installed header and ends at the next separator or end of menu.
  private func installedSectionRange(in menu: NSMenu) -> Range<Int>? {
    guard let headerIndex = menu.items.firstIndex(where: { ($0.representedObject as? String) == "installed-header" }) else { return nil }
    let tail = menu.items.suffix(from: headerIndex + 1)
    let endOffset = tail.firstIndex(where: { $0.isSeparatorItem }) ?? tail.endIndex
    let endIndex = (headerIndex + 1) + (endOffset - tail.startIndex)
    return (headerIndex + 1)..<endIndex
  }

  private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
    let view = SectionHeaderMenuItemView(title: title)
    let item = NSMenuItem.viewItem(with: view, minHeight: 18)
    item.isEnabled = false
    return item
  }

  // Observe server and download changes while the menu is open.
  private func addObservers() {
    removeObservers()
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: .LBServerStateDidChange, object: nil, queue: .main) { [weak self] _ in
      self?.performRefresh()
    })
    observers.append(center.addObserver(forName: .LBServerMemoryDidChange, object: nil, queue: .main) { [weak self] _ in
      self?.performRefresh()
    })
    observers.append(center.addObserver(forName: .LBModelDownloadsDidChange, object: nil, queue: .main) { [weak self] _ in
      self?.performRefresh()
    })
    observers.append(center.addObserver(forName: .LBModelDownloadedListDidChange, object: nil, queue: .main) { [weak self] _ in
      // Model membership might change; refresh rows (closure actions still rebuild on user intent)
      self?.performRefresh()
    })
    // Immediate refresh on open
    performRefresh()
  }

  private func removeObservers() {
    let center = NotificationCenter.default
    observers.forEach { center.removeObserver($0) }
    observers.removeAll()
  }

  private func performRefresh() {
    if let button = statusItem.button {
      let running = server.isRunning
      let imageName = running ? "MenuIconOn" : "MenuIconOff"
      if button.image?.name() != imageName {
        button.image = NSImage(named: imageName) ?? button.image
        button.image?.isTemplate = true
      }
    }
    // Update title
    titleView?.refresh()
    // Update memory footer text to reflect any env var changes or formatting
    // No need to refresh memory footer: RAM doesn't change at runtime, and
    // the menu rebuild sets it correctly on open.
    statusItem.menu?.items.forEach { menuItem in
      if let view = menuItem.view as? InstalledModelMenuItemView { view.refresh() }
      // Update all catalog model submenu items
      if let submenu = menuItem.submenu {
        for subItem in submenu.items {
          if let view = subItem.view as? VariantMenuItemView { view.refresh() }
        }
      }
      if let famView = menuItem.view as? FamilyHeaderMenuItemView { famView.refresh() }
    }
  }

  // Legacy updateTitleItem removed (replaced by HeaderMenuItemView)

  // MARK: - Catalog Helpers

  // Old catalog item update/action logic removed (replaced with custom view implementation).

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  // MARK: - Settings Item Actions

  @objc private func toggleLaunchAtLogin() {
    // Use LaunchAtLogin package (wraps SMAppService on macOS 13+) to manage login item.
    LaunchAtLogin.isEnabled = !LaunchAtLogin.isEnabled
    if let menu = statusItem.menu { rebuildMenu(menu) }
  }

  @objc private func checkForUpdates() {
    // Ask AppDelegate (which owns Sparkle) to present the updater UI.
    NotificationCenter.default.post(name: .LBCheckForUpdates, object: nil)
  }

}
