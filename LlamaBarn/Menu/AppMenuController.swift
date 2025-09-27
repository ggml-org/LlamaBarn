import AppKit
import Foundation
import SwiftUI

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
  private var settingsView: NSHostingView<SettingsMenuItemView>?
  private var isSettingsVisible = false
  private var menuWidth: CGFloat = 260
  // No stored reference needed for the memory footer.
  private var observers: [NSObjectProtocol] = []
  // Single source of truth for the Installed section's empty placeholder title
  private static let installedPlaceholderTitle = "No installed models"

  init(modelManager: ModelManager = .shared, server: LlamaServer = .shared) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager
    self.server = server
    self.llamaCppVersion = AppInfo.llamaCppVersion
    super.init()
    configureStatusItem()
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
    isSettingsVisible = false
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()
    addHeader(to: menu)
    if isSettingsVisible {
      addSettings(to: menu)
      menu.addItem(.separator())
    }
    addInstalled(to: menu)
    addCatalog(to: menu)
    addVersionFooter(to: menu)

    if menu.size.width > 0 {
      self.menuWidth = menu.size.width
    }
  }

  private func addHeader(to menu: NSMenu) {
    let tView = HeaderMenuItemView(
      server: server, llamaCppVersion: llamaCppVersion, isSettingsVisible: isSettingsVisible)
    titleView = tView
    menu.addItem(NSMenuItem.viewItem(with: tView, minHeight: 40))
    menu.addItem(.separator())
  }

  private func addInstalled(to menu: NSMenu) {
    let header = makeSectionHeaderItem("Installed")
    // Tag the Installed header so we can locate this section reliably later.
    header.representedObject = "installed-header"
    menu.addItem(header)

    let downloadingModels = ModelCatalog.allEntries().filter { m in
      if case .downloading = modelManager.getModelStatus(m) { return true }
      return false
    }
    // Keep ordering consistent with family submenus: smallest size first
    let installed = (modelManager.downloadedModels + downloadingModels)
      .sorted(by: ModelCatalogEntry.displayOrder(_:_:))
    if installed.isEmpty {
      let emptyItem = NSMenuItem()
      emptyItem.title = Self.installedPlaceholderTitle
      emptyItem.isEnabled = false
      menu.addItem(emptyItem)
    } else {
      for model in installed {
        let view = InstalledModelMenuItemView(
          model: model, server: server, modelManager: modelManager
        ) {
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
    menu.addItem(makeSectionHeaderItem("Available"))

    for family in families.sorted(by: { $0.name < $1.name }) {
      let models = family.models.flatMap { model -> [ModelCatalogEntry] in
        let allBuilds = [model.build] + model.quantizedBuilds
        return allBuilds.map { build in build.asEntry(family: family, model: model) }
      }
      let famView = FamilyHeaderMenuItemView(
        family: family.name, models: models, modelManager: modelManager)
      let familyItem = NSMenuItem.viewItem(with: famView)
      familyItem.isEnabled = true  // must be enabled so the submenu opens on hover
      familyItem.representedObject = family.name as NSString
      let submenu = NSMenu(title: family.name)
      submenu.autoenablesItems = false
      // Add family "business card" header inside the submenu
      let infoView = FamilyInfoMenuItemView(
        familyName: family.name,
        iconName: family.iconName,
        blurb: family.blurb
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

  private func addSettings(to menu: NSMenu) {
    let rootView = SettingsMenuItemView()
    let view = NSHostingView(rootView: rootView)
    self.settingsView = view
    let height = view.fittingSize.height
    view.frame = NSRect(x: 0, y: 0, width: self.menuWidth, height: height)
    let item = NSMenuItem.viewItem(with: view)
    item.isEnabled = true
    menu.addItem(item)
  }

  private func addVersionFooter(to menu: NSMenu) {
    menu.addItem(.separator())
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let versionLabel = NSTextField(
      labelWithString:
        "\(AppInfo.shortVersion) · build \(AppInfo.buildNumber) · llama.cpp \(AppInfo.llamaCppVersion)"
    )
    versionLabel.font = Typography.primary
    versionLabel.textColor = .secondaryLabelColor
    versionLabel.lineBreakMode = .byTruncatingMiddle
    versionLabel.translatesAutoresizingMaskIntoConstraints = false

    let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
    quitButton.font = Typography.secondary
    quitButton.bezelStyle = .texturedRounded
    quitButton.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(versionLabel)
    container.addSubview(quitButton)

    let horizontalPadding = MenuMetrics.outerHorizontalPadding + MenuMetrics.innerHorizontalPadding

    if menuWidth > 0 {
      container.widthAnchor.constraint(equalToConstant: menuWidth).isActive = true
    }

    NSLayoutConstraint.activate([
      container.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
      versionLabel.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: horizontalPadding),
      versionLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      quitButton.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -horizontalPadding),
      quitButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      versionLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: quitButton.leadingAnchor, constant: -8),
    ])

    let item = NSMenuItem.viewItem(with: container, minHeight: 30)
    item.isEnabled = true
    menu.addItem(item)
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

    // Remove placeholder if present (match by title only), then recompute range to be safe
    if let placeholderAbsolute = menu.items[range].firstIndex(where: {
      Self.isInstalledPlaceholder($0)
    }) {
      menu.removeItem(at: placeholderAbsolute)
      if let newRange = installedSectionRange(in: menu) { range = newRange }
    }

    // Insert a new InstalledModelMenuItemView row at the end of the Installed section
    let view = InstalledModelMenuItemView(model: model, server: server, modelManager: modelManager)
    { [weak self] in
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
    if let absoluteIdx = menu.items[range].firstIndex(where: {
      ($0.representedObject as? NSString) == (model.id as NSString)
    }) {
      menu.removeItem(at: absoluteIdx)
      // If Installed section becomes empty, show the placeholder again
      let remaining = menu.items[installedSectionRange(in: menu) ?? range]
      let hasRows = remaining.contains { $0.view is InstalledModelMenuItemView }
      if !hasRows {
        let emptyItem = NSMenuItem()
        emptyItem.title = Self.installedPlaceholderTitle
        emptyItem.isEnabled = false
        if let newRange = installedSectionRange(in: menu) {
          menu.insertItem(emptyItem, at: newRange.startIndex)
        }
      }
    }
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  /// Returns the open interval range [start, end) of items that belong to the Installed section.
  /// The range starts just after the Installed header and ends at the next separator or end of menu.
  private func installedSectionRange(in menu: NSMenu) -> Range<Int>? {
    guard
      let headerIndex = menu.items.firstIndex(where: {
        ($0.representedObject as? String) == "installed-header"
      })
    else { return nil }
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
    observers.append(
      center.addObserver(forName: .LBServerStateDidChange, object: nil, queue: .main) {
        [weak self] _ in
        self?.performRefresh()
      })
    observers.append(
      center.addObserver(forName: .LBServerMemoryDidChange, object: nil, queue: .main) {
        [weak self] _ in
        self?.performRefresh()
      })
    observers.append(
      center.addObserver(forName: .LBModelDownloadsDidChange, object: nil, queue: .main) {
        [weak self] _ in
        self?.performRefresh()
      })
    observers.append(
      center.addObserver(forName: .LBModelDownloadedListDidChange, object: nil, queue: .main) {
        [weak self] _ in
        // Model membership might change; refresh rows (closure actions still rebuild on user intent)
        self?.performRefresh()
      })
    observers.append(
      center.addObserver(forName: .LBToggleSettingsVisibility, object: nil, queue: .main) {
        [weak self] _ in
        self?.isSettingsVisible.toggle()
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
      })
    observers.append(
      center.addObserver(forName: .LBUserSettingsDidChange, object: nil, queue: .main) {
        [weak self] _ in
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
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

    if let menu = statusItem.menu, let range = installedSectionRange(in: menu) {
      let staleModels: [ModelCatalogEntry] = menu.items[range].compactMap { item in
        guard
          let id = item.representedObject as? NSString,
          let entry = ModelCatalog.entry(forId: id as String)
        else { return nil }
        if case .available = modelManager.getModelStatus(entry) { return entry }
        return nil
      }
      staleModels.forEach { removeInstalledRow(for: $0) }
    }

    // While any model is downloading, ensure the Installed placeholder is hidden.
    if let menu = statusItem.menu, !modelManager.activeDownloads.isEmpty,
      let range = installedSectionRange(in: menu),
      let absoluteIdx = menu.items[range].firstIndex(where: { Self.isInstalledPlaceholder($0) })
    {
      menu.removeItem(at: absoluteIdx)
    }
  }

  // MARK: - Helpers

  private static func isInstalledPlaceholder(_ item: NSMenuItem) -> Bool {
    item.title == installedPlaceholderTitle
  }

}
