import AppKit

/// Submenu header that shows the model family "business card":
/// rounded-rect family icon, family name, and a short description.
final class FamilyHeaderView: NSView {
  private static let menuWidth: CGFloat = 320
  private static let iconTextSpacing: CGFloat = 8

  private let iconView = IconBadgeView(cornerStyle: .rounded)
  private let titleLabel = Typography.makePrimaryLabel()
  private let descriptionLabel = Typography.makeSecondaryLabel()

  init(familyName: String, iconName: String, blurb: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false

    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("\(familyName) info")

    iconView.setImage(NSImage(named: iconName))
    titleLabel.stringValue = familyName
    titleLabel.lineBreakMode = .byTruncatingTail
    descriptionLabel.stringValue = blurb
    descriptionLabel.lineBreakMode = .byWordWrapping
    descriptionLabel.usesSingleLineMode = false
    descriptionLabel.maximumNumberOfLines = 0

    // Calculate available width for text wrapping
    let horizontalPadding = (Layout.outerHorizontalPadding + Layout.innerHorizontalPadding) * 2
    let availableWidth =
      Self.menuWidth - horizontalPadding - Layout.iconBadgeSize - Self.iconTextSpacing
    descriptionLabel.preferredMaxLayoutWidth = availableWidth

    let textStack = NSStackView(views: [titleLabel, descriptionLabel])
    textStack.orientation = .vertical
    textStack.spacing = 2
    textStack.alignment = .leading

    let hStack = NSStackView(views: [iconView, textStack])
    hStack.orientation = .horizontal
    hStack.spacing = Self.iconTextSpacing
    hStack.alignment = .top
    hStack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(hStack)

    NSLayoutConstraint.activate([
      hStack.leadingAnchor.constraint(
        equalTo: leadingAnchor,
        constant: Layout.outerHorizontalPadding + Layout.innerHorizontalPadding),
      hStack.trailingAnchor.constraint(
        equalTo: trailingAnchor,
        constant: -(Layout.outerHorizontalPadding + Layout.innerHorizontalPadding)),
      hStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      hStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

      iconView.widthAnchor.constraint(equalToConstant: Layout.iconBadgeSize),
      iconView.heightAnchor.constraint(equalToConstant: Layout.iconBadgeSize),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: Self.menuWidth, height: 70) }
}
