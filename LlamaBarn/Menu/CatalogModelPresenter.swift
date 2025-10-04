import AppKit

enum CatalogModelPresenter {
  struct Display {
    enum StatusIcon {
      case installed
      case downloading(percent: Int)
      case available(compatible: Bool)
    }

    let title: String
    let titleColor: NSColor
    let sizeText: String
    let memoryText: String
    let contextText: String
    let infoTooltip: String?
    let warningTooltip: String?
    let showsWarning: Bool
    let status: StatusIcon
    let progressText: String?
    let rowTooltip: String?
    let isActionable: Bool
    let isCompatible: Bool
  }

  static func isActionable(model: CatalogEntry, status: ModelStatus) -> Bool {
    switch status {
    case .available:
      return Catalog.isModelCompatible(model)
    case .downloading:
      return true
    case .installed:
      return false
    }
  }

  static func makeDisplay(for model: CatalogEntry, status: ModelStatus) -> Display {
    let compatible = Catalog.isModelCompatible(model)
    let actionable = isActionable(model: model, status: status)
    let titleColor: NSColor = .labelColor

    let title: String = {
      var result = model.displayName
      if !model.isFullPrecision {
        let shortQuant = QuantizationFormatters.short(model.quantization)
        if !shortQuant.isEmpty {
          result += "-\(shortQuant)"
        }
      }
      return result
    }()

    let recommendedCtx = Catalog.recommendedCtxWindow(for: model)

    let contextString: String

    if compatible {
      contextString = {
        if let usable = recommendedCtx, usable < model.ctxWindow {
          let max = model.ctxWindow
          return "\(TokenFormatters.shortTokens(usable)) of \(TokenFormatters.shortTokens(max))"
        }
        guard model.ctxWindow > 0 else { return "—" }
        return TokenFormatters.shortTokens(model.ctxWindow)
      }()
    } else {
      contextString = "Won't run on this device."
    }

    let infoTooltip: String? =
      compatible
      ? nil
      : (Catalog.incompatibilitySummary(model) ?? "not compatible")

    let (showsWarning, warningTooltip) = makeMaxContextWarning(for: model, compatible: compatible)

    let statusIcon: Display.StatusIcon
    let progressText: String?
    let rowTooltip: String?
    switch status {
    case .installed:
      statusIcon = .installed
      progressText = nil
      rowTooltip = "Already installed"
    case .downloading(let progress):
      statusIcon = .downloading(percent: progressPercent(progress))
      progressText = progressLabel(for: progress)
      rowTooltip = nil
    case .available:
      statusIcon = .available(compatible: compatible)
      progressText = nil
      rowTooltip = nil
    }

    let memoryMB = Catalog.runtimeMemoryUsageMB(
      for: model,
      ctxWindowTokens: Double(recommendedCtx ?? model.ctxWindow)
    )

    return Display(
      title: title,
      titleColor: titleColor,
      sizeText: model.totalSize,
      memoryText: MemoryFormatters.gbOneDecimal(memoryMB),
      contextText: contextString,
      infoTooltip: infoTooltip,
      warningTooltip: warningTooltip,
      showsWarning: showsWarning,
      status: statusIcon,
      progressText: progressText,
      rowTooltip: rowTooltip,
      isActionable: actionable,
      isCompatible: compatible
    )
  }

  private static func makeMaxContextWarning(
    for model: CatalogEntry,
    compatible: Bool
  ) -> (Bool, String?) {
    guard compatible, model.ctxWindow > 0 else { return (false, nil) }
    let maxTokens = Double(model.ctxWindow)
    if maxTokens <= Catalog.compatibilityCtxWindowTokens {
      return (false, nil)
    }
    let stillFits = Catalog.isModelCompatible(
      model,
      ctxWindowTokens: maxTokens
    )
    guard !stillFits else { return (false, nil) }
    return (true, "Can run at reduced context window")
  }

  private static func progressPercent(_ progress: Progress) -> Int {
    guard progress.totalUnitCount > 0 else { return 0 }
    let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
    return max(0, min(100, Int(fraction * 100)))
  }

  private static func progressLabel(for progress: Progress) -> String? {
    let percent = progressPercent(progress)
    return "\(percent)%"
  }

}
