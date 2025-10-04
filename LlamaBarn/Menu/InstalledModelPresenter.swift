import AppKit

enum InstalledModelPresenter {
  struct Display {
    let title: String
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
    let isRunning = isActive && server.isRunning

    switch status {
    case .downloading(let progress):
      let completedSizeText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      let totalBytes = progress.totalUnitCount > 0 ? progress.totalUnitCount : model.fileSize
      let totalSizeText = ByteFormatters.gbTwoDecimals(totalBytes)

      let metadataText = MetadataLabel.make(
        icon: MetadataLabel.sizeSymbol,
        text: "\(completedSizeText) / \(totalSizeText)"
      )

      return Display(
        title: model.menuTitle,
        metadataText: metadataText,
        progressText: ProgressFormatters.percentText(progress),
        showsCancelButton: true,
        isLoading: isLoading,
        isActive: isRunning
      )

    case .installed, .available:
      let metadataText = makeMetadataText(
        for: model,
        isRunning: isRunning,
        memoryUsageMB: server.memoryUsageMB
      )

      return Display(
        title: model.menuTitle,
        metadataText: metadataText,
        progressText: nil,
        showsCancelButton: false,
        isLoading: isLoading,
        isActive: isRunning
      )
    }
  }

  private static func makeMetadataText(
    for model: CatalogEntry,
    isRunning: Bool,
    memoryUsageMB: Double
  ) -> NSAttributedString {
    let result = NSMutableAttributedString()

    result.append(MetadataLabel.make(icon: MetadataLabel.sizeSymbol, text: model.totalSize))

    if let recommendedCtx = Catalog.recommendedCtxWindow(for: model) {
      result.append(MetadataLabel.makeSeparator())
      result.append(
        MetadataLabel.make(
          icon: MetadataLabel.contextSymbol,
          text: TokenFormatters.shortTokens(recommendedCtx)
        ))
    }

    if isRunning, let memoryText = MemoryFormatters.runtime(memoryUsageMB) {
      result.append(MetadataLabel.makeSeparator())
      result.append(MetadataLabel.make(icon: MetadataLabel.memorySymbol, text: memoryText))
    }

    return result
  }
}
