import AppKit

enum CatalogModelPresenter {
  struct Display {
    enum StatusIcon {
      case installed
      case downloading(percent: Int)
      case available(compatible: Bool)
    }

    let title: String
    let metadataText: NSAttributedString
    let infoTooltip: String?
    let warningTooltip: String?
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

    let usableCtx = Catalog.usableCtxWindow(for: model)

    let infoTooltip: String? =
      compatible
      ? nil
      : (Catalog.incompatibilitySummary(model) ?? "not compatible")

    let warningTooltip: String? =
      compatible && usableCtx != nil && usableCtx! < model.ctxWindow
      ? "Can run at reduced context window"
      : nil

    let statusIcon: Display.StatusIcon
    let progressText: String?
    let rowTooltip: String?
    switch status {
    case .installed:
      statusIcon = .installed
      progressText = nil
      rowTooltip = "Already installed"
    case .downloading(let progress):
      statusIcon = .downloading(percent: ProgressFormatters.percent(progress))
      progressText = ProgressFormatters.percentText(progress)
      rowTooltip = nil
    case .available:
      statusIcon = .available(compatible: compatible)
      progressText = nil
      rowTooltip = nil
    }

    let memoryMb = Catalog.runtimeMemoryUsageMb(
      for: model,
      ctxWindowTokens: Double(usableCtx ?? model.ctxWindow)
    )

    let metadataText = makeMetadataText(
      model: model,
      memoryMb: memoryMb,
      usableCtx: usableCtx,
      compatible: compatible
    )

    return Display(
      title: model.menuTitle,
      metadataText: metadataText,
      infoTooltip: infoTooltip,
      warningTooltip: warningTooltip,
      status: statusIcon,
      progressText: progressText,
      rowTooltip: rowTooltip,
      isActionable: actionable,
      isCompatible: compatible
    )
  }

  private static func makeMetadataText(
    model: CatalogEntry,
    memoryMb: UInt64,
    usableCtx: Int?,
    compatible: Bool
  ) -> NSAttributedString {
    let line = NSMutableAttributedString()

    line.append(MetadataLabel.make(icon: MetadataLabel.sizeSymbol, text: model.totalSize))
    line.append(MetadataLabel.makeSeparator())
    line.append(
      MetadataLabel.make(
        icon: MetadataLabel.memorySymbol, text: MemoryFormatters.gbOneDecimal(memoryMb)))
    line.append(MetadataLabel.makeSeparator())

    // Context window
    if !compatible {
      line.append(
        MetadataLabel.make(icon: MetadataLabel.contextSymbol, text: "Won't run on this device."))
    } else if let usable = usableCtx, usable < model.ctxWindow {
      // Show strikethrough max with usable value, plus warning icon
      line.append(MetadataLabel.makeIconOnly(icon: MetadataLabel.contextSymbol))
      line.append(NSAttributedString(string: " "))
      var attrs = Typography.secondaryAttributes
      attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
      line.append(
        NSAttributedString(string: TokenFormatters.shortTokens(model.ctxWindow), attributes: attrs))
      line.append(NSAttributedString(string: " ", attributes: Typography.secondaryAttributes))
      line.append(
        NSAttributedString(
          string: TokenFormatters.shortTokens(usable), attributes: Typography.secondaryAttributes))
      line.append(MetadataLabel.makeSeparator())
      line.append(MetadataLabel.makeIconOnly(icon: MetadataLabel.warningSymbol))
    } else {
      let text = model.ctxWindow > 0 ? TokenFormatters.shortTokens(model.ctxWindow) : "—"
      line.append(MetadataLabel.make(icon: MetadataLabel.contextSymbol, text: text))
    }

    return line
  }

}
