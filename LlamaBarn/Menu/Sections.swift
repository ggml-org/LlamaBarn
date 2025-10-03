import AppKit
import Foundation
import SwiftUI

/// Shared helpers that build individual sections of the status bar menu.
/// Breaks the large Controller into focused collaborators so each
/// section owns its layout and mutation logic.

private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
  let view = SectionHeaderView(title: title)
  let item = NSMenuItem.viewItem(with: view, minHeight: 18)
  item.isEnabled = false
  return item
}

final class MenuHeaderSection {
  private let server: LlamaServer
  private var titleView: HeaderView?

  init(server: LlamaServer) {
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
  func add(to menu: NSMenu, menuWidth: CGFloat) {
    let rootView = SettingsView()
    let view = NSHostingView(rootView: rootView)
    let height = view.fittingSize.height
    view.frame = NSRect(x: 0, y: 0, width: menuWidth, height: height)
    let item = NSMenuItem.viewItem(with: view)
    item.isEnabled = true
    menu.addItem(item)
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
    populateSection(in: menu)
  }

  /// Rebuilds the installed section to reflect current model state.
  /// Called during live refresh to keep the UI in sync while menu stays open.
  func refresh(in menu: NSMenu) {
    guard let range = installedSectionRange(in: menu) else { return }
    for index in range.reversed() {
      menu.removeItem(at: index)
    }
    populateSection(in: menu)
  }

  private func populateSection(in menu: NSMenu) {
    guard let range = installedSectionRange(in: menu) else { return }
    let installed = getInstalledModels()

    guard !installed.isEmpty else {
      menu.insertItem(makePlaceholderItem(), at: range.startIndex)
      return
    }

    installed.enumerated().forEach { offset, model in
      menu.insertItem(makeInstalledRow(for: model), at: range.startIndex + offset)
    }
  }

  private func getInstalledModels() -> [CatalogEntry] {
    let downloading = Catalog.allEntries().filter {
      if case .downloading = modelManager.getModelStatus($0) { return true }
      return false
    }
    return (modelManager.downloadedModels + downloading)
      .sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  private func makePlaceholderItem() -> NSMenuItem {
    let item = NSMenuItem()
    item.title = Constants.placeholderTitle
    item.isEnabled = false
    return item
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

  /// Locates the installed section boundaries. The section starts after the header
  /// and ends at the next separator or menu end.
  private func installedSectionRange(in menu: NSMenu) -> Range<Int>? {
    guard
      let headerIndex = menu.items.firstIndex(where: {
        ($0.representedObject as? String) == Constants.headerIdentifier
      })
    else { return nil }

    let start = headerIndex + 1
    let end = menu.items[start...].firstIndex(where: \.isSeparatorItem) ?? menu.items.endIndex
    return start..<end
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

    for family in families {
      // Filter cached entries to avoid rebuilding ~30 structs on every menu refresh.
      let models = Catalog.allEntries().filter { entry in
        entry.family == family.name && (showQuantized || entry.isFullPrecision)
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
      // Disable auto-enabling so we control item state explicitly (e.g., incompatible models stay disabled)
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
