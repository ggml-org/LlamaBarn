import AppKit

enum VariantRowPresenter {
  struct DisplayData {
    enum StatusIcon {
      case downloaded
      case downloading(percent: Int)
      case available(compatible: Bool)
    }

    let title: String
    let titleColor: NSColor
    let infoColor: NSColor
    let sizeText: String
    let contextText: String
    let memoryText: String?
    let infoTooltip: String?
    let warningTooltip: String?
    let showsWarning: Bool
    let status: StatusIcon
    let progressText: String?
    let rowTooltip: String?
    let isActionable: Bool
  }

  static func isActionable(model: ModelCatalogEntry, status: ModelStatus) -> Bool {
    switch status {
    case .available:
      return ModelCatalog.isModelCompatible(model)
    case .downloading:
      return true
    case .downloaded:
      return false
    }
  }

  static func makeDisplay(for model: ModelCatalogEntry, status: ModelStatus) -> DisplayData {
    let compatible = ModelCatalog.isModelCompatible(model)
    let actionable = isActionable(model: model, status: status)

    let titleColor: NSColor
    let infoColor: NSColor
    if !compatible {
      titleColor = .tertiaryLabelColor
      infoColor = .tertiaryLabelColor
    } else if !actionable {
      titleColor = .secondaryLabelColor
      infoColor = .tertiaryLabelColor
    } else {
      titleColor = .labelColor
      infoColor = .secondaryLabelColor
    }

    let title: String = {
      var result = model.displayName
      if !model.isFullPrecision {
        result += " \(model.quantization)"
      }
      return result
    }()

    let recommendedContext = ModelCatalog.recommendedContextLength(for: model)

    let contextString: String = {
      if let recommendedContext {
        return TokenFormatters.shortTokens(recommendedContext)
      }
      guard model.contextLength > 0 else { return "—" }
      return TokenFormatters.shortTokens(model.contextLength)
    }()

    let memoryEstimate = makeMemoryEstimateString(for: model, contextLength: recommendedContext)

    let infoTooltip: String? =
      compatible
      ? nil
      : (ModelCatalog.incompatibilitySummary(model) ?? "not compatible")

    let (showsWarning, warningTooltip) = makeMaxContextWarning(for: model, compatible: compatible)

    let statusIcon: DisplayData.StatusIcon
    let progressText: String?
    let rowTooltip: String?
    switch status {
    case .downloaded:
      statusIcon = .downloaded
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

    return DisplayData(
      title: title,
      titleColor: titleColor,
      infoColor: infoColor,
      sizeText: model.totalSize,
      contextText: contextString,
      memoryText: memoryEstimate,
      infoTooltip: infoTooltip,
      warningTooltip: warningTooltip,
      showsWarning: showsWarning,
      status: statusIcon,
      progressText: progressText,
      rowTooltip: rowTooltip,
      isActionable: actionable
    )
  }

  private static func makeMaxContextWarning(
    for model: ModelCatalogEntry,
    compatible: Bool
  ) -> (Bool, String?) {
    guard compatible, model.contextLength > 0 else { return (false, nil) }
    let maxTokens = Double(model.contextLength)
    if maxTokens <= ModelCatalog.compatibilityContextLengthTokens {
      return (false, nil)
    }
    let stillFits = ModelCatalog.isModelCompatible(
      model,
      contextLengthTokens: maxTokens
    )
    guard !stillFits else { return (false, nil) }
    let reason = ModelCatalog.incompatibilitySummary(
      model,
      contextLengthTokens: maxTokens
    )
    if let reason {
      let ctxString = TokenFormatters.shortTokens(model.contextLength)
      return (true, "\(reason) for full \(ctxString) context")
    }
    return (true, "Cannot run at maximum context")
  }

  private static func makeMemoryEstimateString(
    for model: ModelCatalogEntry,
    contextLength: Int?
  ) -> String? {
    guard let contextLength, contextLength > 0 else { return nil }

    let usageMB = ModelCatalog.runtimeMemoryUsageMB(
      for: model,
      contextLengthTokens: Double(contextLength)
    )
    guard usageMB > 0 else { return nil }

    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB]
    formatter.countStyle = .binary
    let bytes = Int64(usageMB) * 1_048_576
    return formatter.string(fromByteCount: bytes)
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
