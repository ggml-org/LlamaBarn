import AppKit

enum InstalledModelPresenter {
  struct Display {
    let title: String
    let titleColor: NSColor
    let iconTintColor: NSColor
    let metadataText: NSAttributedString
    let progressText: String?
    let showsCancelButton: Bool
    let isLoading: Bool
    let isActive: Bool
  }

  static func makeDisplay(
    for model: CatalogEntry,
    status: ModelStatus,
    server: LlamaServer
  ) -> Display {
    let isActive = server.isActive(model: model)
    let isLoading = isActive && server.isLoading

    switch status {
    case .downloading(let progress):
      return Display(
        title: model.menuTitle,
        titleColor: Typography.secondaryColor,
        iconTintColor: Typography.secondaryColor,
        metadataText: ModelMetadataFormatters.makeMetadataText(for: model),
        progressText: ProgressFormatters.percentText(progress),
        showsCancelButton: true,
        isLoading: isLoading,
        isActive: isActive
      )

    case .installed, .available:
      return Display(
        title: model.menuTitle,
        titleColor: .controlTextColor,
        iconTintColor: Typography.primaryColor,
        metadataText: ModelMetadataFormatters.makeMetadataText(for: model),
        progressText: nil,
        showsCancelButton: false,
        isLoading: isLoading,
        isActive: isActive
      )
    }
  }
}
