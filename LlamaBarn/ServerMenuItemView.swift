import AppKit
import Foundation

/// Menu row showing llama-server status with a link indicator.
final class ServerMenuItemView: MenuRowView {
  private unowned let server: LlamaServer
  private let onOpen: () -> Void

  private let iconView = NSImageView()
  private let textField = NSTextField(labelWithString: "")
  private let linkIndicator = NSImageView()
  // Hover handled by MenuRowView; only enable while server is running
  override var hoverHighlightEnabled: Bool { server.isRunning }

  init(server: LlamaServer, onOpen: @escaping () -> Void) {
    self.server = server
    self.onOpen = onOpen
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 32) }

  private func setup() {
    wantsLayer = true
    iconView.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)
    iconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.contentTintColor = .secondaryLabelColor

    textField.font = MenuTypography.primary
    textField.lineBreakMode = .byTruncatingTail
    textField.translatesAutoresizingMaskIntoConstraints = false

    linkIndicator.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
    linkIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    linkIndicator.translatesAutoresizingMaskIntoConstraints = false
    linkIndicator.contentTintColor = .secondaryLabelColor

    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [iconView, textField, spacer, linkIndicator])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    contentView.addSubview(stack)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      iconView.heightAnchor.constraint(equalToConstant: MenuMetrics.iconSize),
      linkIndicator.widthAnchor.constraint(equalToConstant: MenuMetrics.smallIconSize),
      linkIndicator.heightAnchor.constraint(equalToConstant: MenuMetrics.smallIconSize),
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
      stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
    ])
  }

  override func mouseDown(with event: NSEvent) {
    guard server.isRunning else { return }
    onOpen()
  }

  // Hover highlight handled by base class

  func refresh() {
    if server.isRunning {
      textField.stringValue = "Running on localhost:\(LlamaServer.defaultPort)"
      textField.textColor = .labelColor
      iconView.contentTintColor = .labelColor
      linkIndicator.contentTintColor = .linkColor
    } else {
      textField.stringValue = "Server not running"
      textField.textColor = .secondaryLabelColor
      iconView.contentTintColor = .secondaryLabelColor
      linkIndicator.contentTintColor = .tertiaryLabelColor
      setHoverHighlight(false)
    }
    needsDisplay = true
  }

}
