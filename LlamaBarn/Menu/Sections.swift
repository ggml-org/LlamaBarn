import AppKit
import Foundation
import SwiftUI

/// Shared helpers that build individual sections of the status bar menu.
/// Breaks the large Controller into focused collaborators so each
/// section owns its layout and mutation logic.
final class MenuHeaderSection {
  private let server: LlamaServer
  private var titleView: HeaderView?

  init(server: LlamaServer, llamaCppVersion: String) {
    self.server = server
  }

  func add(to menu: NSMenu, isSettingsVisible: Bool) {
    let view = HeaderView(
      server: server,
      isSettingsVisible: isSettingsVisible
    )
    titleView = view
    menu.addItem(NSMenuItem.viewItem(with: view, minHeight: 40))
    menu.addItem(.separator())
  }

  func refresh() {
    titleView?.refresh()
  }
}

final class MenuSettingsSection {
  private var settingsView: NSHostingView<SettingsView>?

  func add(to menu: NSMenu, menuWidth: CGFloat) {
    let rootView = SettingsView()
    let view = NSHostingView(rootView: rootView)
    settingsView = view
    let height = view.fittingSize.height
    view.frame = NSRect(x: 0, y: 0, width: menuWidth, height: height)
    let item = NSMenuItem.viewItem(with: view)
    item.isEnabled = true
    menu.addItem(item)
  }

  func clear() {
    settingsView = nil
  }
}

final class InstalledSection {
  private enum Constants {
    static let headerIdentifier = "installed-header"
    static let placeholderTitle = "No installed models"
  }

  private let modelManager: Manager
  private let server: LlamaServer
  private let onMembershipChanged: (CatalogEntry) -> Void

  init(
    modelManager: Manager,
    server: LlamaServer,
    onMembershipChanged: @escaping (CatalogEntry) -> Void
  ) {
    self.modelManager = modelManager
    self.server = server
    self.onMembershipChanged = onMembershipChanged
  }

  func add(to menu: NSMenu) {
    let header = makeSectionHeaderItem("Installed")
    header.representedObject = Constants.headerIdentifier
    menu.addItem(header)

    let downloadingModels = Catalog.allEntries().filter { entry in
      if case .downloading = modelManager.getModelStatus(entry) { return true }
      return false
    }
    let installed = (modelManager.downloadedModels + downloadingModels)
      .sorted(by: CatalogEntry.displayOrder(_:_:))

    guard !installed.isEmpty else {
      let emptyItem = NSMenuItem()
      emptyItem.title = Constants.placeholderTitle
      emptyItem.isEnabled = false
      menu.addItem(emptyItem)
      return
    }

    installed.forEach { model in
      menu.addItem(makeInstalledRow(for: model))
    }
  }

  func ensureRow(for model: CatalogEntry, in menu: NSMenu) {
    guard var range = installedSectionRange(in: menu) else { return }
    let alreadyPresent = menu.items[range].contains {
      ($0.representedObject as? NSString) == (model.id as NSString)
    }
    if alreadyPresent { return }

    if let placeholderAbsolute = menu.items[range].firstIndex(where: { isPlaceholder($0) }) {
      menu.removeItem(at: placeholderAbsolute)
      if let newRange = installedSectionRange(in: menu) {
        range = newRange
      }
    }

    let item = makeInstalledRow(for: model)
    menu.insertItem(item, at: range.endIndex)
  }

  func removeRow(for model: CatalogEntry, in menu: NSMenu) {
    guard let range = installedSectionRange(in: menu) else { return }
    guard
      let absoluteIdx = menu.items[range].firstIndex(where: {
        ($0.representedObject as? NSString) == (model.id as NSString)
      })
    else { return }

    menu.removeItem(at: absoluteIdx)
    let remainingItems = menu.items[installedSectionRange(in: menu) ?? range]
    let hasRows = remainingItems.contains { $0.view is InstalledModelItemView }
    if !hasRows {
      let emptyItem = NSMenuItem()
      emptyItem.title = Constants.placeholderTitle
      emptyItem.isEnabled = false
      if let newRange = installedSectionRange(in: menu) {
        menu.insertItem(emptyItem, at: newRange.startIndex)
      }
    }
  }

  func pruneRows(in menu: NSMenu) {
    guard let range = installedSectionRange(in: menu) else { return }
    let staleModels: [CatalogEntry] = menu.items[range].compactMap { item in
      guard
        let id = item.representedObject as? NSString,
        let entry = Catalog.entry(forId: id as String)
      else { return nil }
      if case .available = modelManager.getModelStatus(entry) { return entry }
      return nil
    }
    staleModels.forEach { removeRow(for: $0, in: menu) }
  }

  func updatePlaceholderVisibility(in menu: NSMenu, hasActiveDownloads: Bool) {
    guard let range = installedSectionRange(in: menu) else { return }
    if hasActiveDownloads {
      if let placeholderIndex = menu.items[range].firstIndex(where: { isPlaceholder($0) }) {
        menu.removeItem(at: placeholderIndex)
      }
    }
  }

  private func makeInstalledRow(for model: CatalogEntry) -> NSMenuItem {
    let view = InstalledModelItemView(
      model: model,
      server: server,
      modelManager: modelManager
    ) { [weak self] entry in
      self?.onMembershipChanged(entry)
    }
    let item = NSMenuItem.viewItem(with: view, minHeight: 28)
    item.representedObject = model.id as NSString
    return item
  }

  private func installedSectionRange(in menu: NSMenu) -> Range<Int>? {
    guard
      let headerIndex = menu.items.firstIndex(where: {
        ($0.representedObject as? String) == Constants.headerIdentifier
      })
    else { return nil }
    let tail = menu.items.suffix(from: headerIndex + 1)
    let endOffset = tail.firstIndex(where: { $0.isSeparatorItem }) ?? tail.endIndex
    let endIndex = (headerIndex + 1) + (endOffset - tail.startIndex)
    return (headerIndex + 1)..<endIndex
  }

  private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
    let view = SectionHeaderView(title: title)
    let item = NSMenuItem.viewItem(with: view, minHeight: 18)
    item.isEnabled = false
    return item
  }

  private func isPlaceholder(_ item: NSMenuItem) -> Bool {
    item.title == Constants.placeholderTitle
  }
}

final class CatalogSection {
  private let modelManager: Manager
  private let onDownloadStatusChange: (CatalogEntry) -> Void

  init(
    modelManager: Manager,
    onDownloadStatusChange: @escaping (CatalogEntry) -> Void
  ) {
    self.modelManager = modelManager
    self.onDownloadStatusChange = onDownloadStatusChange
  }

  func add(to menu: NSMenu) {
    let showQuantized = UserSettings.showQuantizedModels
    let families = Catalog.families

    guard !families.isEmpty else { return }

    menu.addItem(.separator())
    menu.addItem(makeSectionHeaderItem("Available"))

    for family in families.sorted(by: { $0.name < $1.name }) {
      var models = [CatalogEntry]()
      for model in family.models {
        let builds = showQuantized ? ([model.build] + model.quantizedBuilds) : [model.build]
        for build in builds {
          models.append(build.asEntry(family: family, model: model))
        }
      }

      if models.isEmpty { continue }

      let sortedModels = models.sorted(by: CatalogEntry.familyDisplayOrder(_:_:))

      let familyView = FamilyItemView(
        family: family.name,
        sortedModels: sortedModels,
        modelManager: modelManager
      )
      let familyItem = NSMenuItem.viewItem(with: familyView)
      familyItem.isEnabled = true
      familyItem.representedObject = family.name as NSString

      let submenu = NSMenu(title: family.name)
      submenu.autoenablesItems = false
      submenu.delegate = menu.delegate
      let infoView = FamilyInfoView(
        familyName: family.name,
        iconName: family.iconName,
        blurb: family.blurb
      )
      submenu.addItem(NSMenuItem.viewItem(with: infoView, minHeight: 56))
      submenu.addItem(.separator())

      for model in sortedModels {
        let view = CatalogModelItemView(model: model, modelManager: modelManager) {
          [weak self] in
          self?.onDownloadStatusChange(model)
        }
        let modelItem = NSMenuItem.viewItem(with: view, minHeight: 26)
        modelItem.representedObject = model.id as NSString
        submenu.addItem(modelItem)
      }

      familyItem.submenu = submenu
      menu.addItem(familyItem)
    }
  }

  private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
    let view = SectionHeaderView(title: title)
    let item = NSMenuItem.viewItem(with: view, minHeight: 18)
    item.isEnabled = false
    return item
  }
}

final class FooterSection {
  func add(to menu: NSMenu, menuWidth: CGFloat) {
    menu.addItem(.separator())

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    // Production builds show marketing version without build number;
    // dev/test builds (0.0.0) show only build number
    let versionText: String
    if AppInfo.shortVersion == "0.0.0" {
      versionText = "build \(AppInfo.buildNumber) · llama.cpp \(AppInfo.llamaCppVersion)"
    } else {
      versionText = "\(AppInfo.shortVersion) · llama.cpp \(AppInfo.llamaCppVersion)"
    }

    let versionLabel = NSTextField(labelWithString: versionText)
    versionLabel.font = Typography.primary
    versionLabel.textColor = .labelColor
    versionLabel.lineBreakMode = .byTruncatingMiddle
    versionLabel.translatesAutoresizingMaskIntoConstraints = false

    let quitButton = NSButton(title: "Quit", target: nil, action: #selector(quitApp))
    quitButton.font = Typography.secondary
    quitButton.bezelStyle = .texturedRounded
    quitButton.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(versionLabel)
    container.addSubview(quitButton)

    let horizontalPadding = Metrics.outerHorizontalPadding + Metrics.innerHorizontalPadding

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
    quitButton.target = self
    quitButton.action = #selector(quitApp)
    menu.addItem(item)
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }
}
