import AppKit
import Foundation

/// Submenu header that shows the model family "business card":
/// circular family icon, family name, and a short description.
final class FamilyInfoMenuItemView: NSView {
  private let iconView = CircularIconView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let metaLabel = NSTextField(labelWithString: "")
  private let descriptionLabel = NSTextField(labelWithString: "")
  private let chipsStack = NSStackView()
  private let container = NSView()

  init(familyName: String, iconName: String, blurb: String, releaseDate: Date?, contextTokens: Int?) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    setup(familyName: familyName, iconName: iconName, blurb: blurb, releaseDate: releaseDate, contextTokens: contextTokens)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 70) }

  private func setup(familyName: String, iconName: String, blurb: String, releaseDate: Date?, contextTokens: Int?) {
    // Accessibility
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("\(familyName) info")

    container.translatesAutoresizingMaskIntoConstraints = false

    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.setImage(NSImage(named: iconName))
    iconView.isActive = false

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = MenuTypography.primarySemibold
    titleLabel.stringValue = familyName
    titleLabel.lineBreakMode = .byTruncatingTail

    metaLabel.translatesAutoresizingMaskIntoConstraints = false
    metaLabel.font = MenuTypography.subtitle
    metaLabel.textColor = .tertiaryLabelColor
    metaLabel.stringValue = "" // We now use chips for metadata; keep this for future copy if needed.
    metaLabel.isHidden = true

    descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
    descriptionLabel.font = MenuTypography.subtitle
    descriptionLabel.textColor = .secondaryLabelColor
    descriptionLabel.stringValue = blurb
    descriptionLabel.lineBreakMode = .byWordWrapping

    chipsStack.orientation = .horizontal
    chipsStack.alignment = .centerY
    chipsStack.spacing = 6
    chipsStack.translatesAutoresizingMaskIntoConstraints = false

    // Build chips: date and context length
    if let date = releaseDate {
      chipsStack.addArrangedSubview(ChipView(text: DateFormatters.mediumString(date)))
    }
    if let ctx = contextTokens {
      chipsStack.addArrangedSubview(ChipView(text: "Ctx \(TokenFormatters.shortTokens(ctx))"))
    }

    let textStack = NSStackView(views: [titleLabel, chipsStack, descriptionLabel])
    textStack.orientation = .vertical
    textStack.spacing = 2
    textStack.alignment = .leading
    textStack.translatesAutoresizingMaskIntoConstraints = false

    let hStack = NSStackView(views: [iconView, textStack])
    hStack.orientation = .horizontal
    hStack.spacing = 8
    hStack.alignment = .top
    hStack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(container)
    container.addSubview(hStack)

    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuMetrics.outerHorizontalPadding),
      container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuMetrics.outerHorizontalPadding),
      container.topAnchor.constraint(equalTo: topAnchor),
      container.bottomAnchor.constraint(equalTo: bottomAnchor),

      iconView.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      iconView.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),

      hStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: MenuMetrics.innerHorizontalPadding),
      hStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -MenuMetrics.innerHorizontalPadding),
      hStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
      hStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
    ])
  }
}

// Simple rounded chip used for metadata in the family info view.
  private final class ChipView: NSView {
  private let label = NSTextField(labelWithString: "")
  private let paddingX: CGFloat = 6
  private let paddingY: CGFloat = 2

  init(text: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = MenuTypography.chip
    label.textColor = .secondaryLabelColor
    label.stringValue = text
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: paddingX),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -paddingX),
      label.topAnchor.constraint(equalTo: topAnchor, constant: paddingY),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -paddingY),
    ])
    layer?.cornerRadius = 6
    layer?.backgroundColor = NSColor.cgColor(.lbBadgeBackground, in: self)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
