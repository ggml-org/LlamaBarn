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
    addServer(to: menu)
    addSettings(to: menu)
    addDebugFooterIfNeeded(to: menu)
    addQuit(to: menu)
  }

  private func addHeader(to menu: NSMenu) {
    let tView = HeaderMenuItemView(server: server, llamaCppVersion: llamaCppVersion)
    titleView = tView
    menu.addItem(NSMenuItem.viewItem(with: tView, minHeight: 40))
    menu.addItem(.separator())
  }

  private func addInstalled(to menu: NSMenu) {
    menu.addItem(makeSectionHeaderItem("Installed models"))

    let downloadingModels = ModelCatalog.models.filter { m in
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
    let familiesDict = Dictionary(grouping: ModelCatalog.models, by: { $0.family })
    let sortedFamilies = familiesDict.keys.sorted()
    guard !sortedFamilies.isEmpty else { return }
    menu.addItem(.separator())
    menu.addItem(makeSectionHeaderItem("Catalog"))

    for family in sortedFamilies {
      guard let models = familiesDict[family] else { continue }
      let famView = FamilyHeaderMenuItemView(family: family, models: models, modelManager: modelManager)
      let familyItem = NSMenuItem.viewItem(with: famView)
      familyItem.isEnabled = true  // must be enabled so the submenu opens on hover
      familyItem.representedObject = family as NSString
      let submenu = NSMenu(title: family)
      submenu.autoenablesItems = false
      let sortedModels = models.sorted(by: ModelCatalogEntry.displayOrder(_:_:))
      for model in sortedModels {
        let view = VariantMenuItemView(model: model, modelManager: modelManager) {
          [weak self] in
          if let menu = self?.statusItem.menu { self?.rebuildMenu(menu) }
        }
        let modelItem = NSMenuItem.viewItem(with: view, minHeight: 26)
        modelItem.representedObject = model.id as NSString
        submenu.addItem(modelItem)
      }
      familyItem.submenu = submenu
      menu.addItem(familyItem)
    }
  }

  private func addServer(to menu: NSMenu) {
    menu.addItem(.separator())
    let serverView = ServerMenuItemView(server: server) { [weak self] in
      guard let url = URL(string: "http://localhost:\(LlamaServer.defaultPort)/") else { return }
      NSWorkspace.shared.open(url)
      self?.statusItem.menu?.cancelTracking()
    }
    menu.addItem(NSMenuItem.viewItem(with: serverView, minHeight: 32))
  }

  private func addSettings(to menu: NSMenu) {
    menu.addItem(.separator())
    let launchAtLogin = NSMenuItem(
      title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    launchAtLogin.target = self
    launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
    menu.addItem(launchAtLogin)

    let updatesItem = NSMenuItem(
      title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    updatesItem.target = self
    menu.addItem(updatesItem)
  }

  private func addDebugFooterIfNeeded(to menu: NSMenu) {
    #if DEBUG
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
      menu.addItem(.separator())
      menu.addItem(memItem)
    #endif
  }

  private func addQuit(to menu: NSMenu) {
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
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
      if let view = menuItem.view as? ServerMenuItemView { view.refresh() }
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
