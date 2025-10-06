import AppKit
import Foundation

/// Header row showing app name and server status.
final class HeaderView: NSView {

  private unowned let server: LlamaServer
  private let appNameLabel = Typography.makePrimaryLabel()
  private let serverStatusLabel = Typography.makeSecondaryLabel()
  private let backgroundView = NSView()
  private let settingsButton = NSButton()
  private let isSettingsVisible: Bool

  init(server: LlamaServer, isSettingsVisible: Bool) {
    self.server = server
    self.isSettingsVisible = isSettingsVisible
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 40) }

  private func setup() {
    wantsLayer = true
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true

    appNameLabel.stringValue = "LlamaBarn"

    serverStatusLabel.allowsEditingTextAttributes = true
    serverStatusLabel.isSelectable = true

    let stack = NSStackView(views: [appNameLabel, serverStatusLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2

    // Trailing Settings and Quit controls (header buttons)
    settingsButton.title = ""
    let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
      .applying(.init(paletteColors: [isSettingsVisible ? .linkColor : .controlTextColor]))
    settingsButton.image = gearImage?.withSymbolConfiguration(symbolConfig)
    settingsButton.isBordered = false
    settingsButton.bezelStyle = .rounded
    settingsButton.target = self
    settingsButton.action = #selector(toggleSettings)
    settingsButton.keyEquivalent = ","

    // Horizontal container: [stack][spacer][settings][quit]
    let headerStackView = NSStackView()
    headerStackView.translatesAutoresizingMaskIntoConstraints = false
    headerStackView.orientation = .horizontal
    headerStackView.alignment = .centerY
    headerStackView.spacing = 8
    headerStackView.addArrangedSubview(stack)
    headerStackView.addArrangedSubview(NSView())  // flexible spacer
    headerStackView.addArrangedSubview(settingsButton)
    (headerStackView.arrangedSubviews[1]).setContentHuggingPriority(.defaultLow, for: .horizontal)
    (headerStackView.arrangedSubviews[1]).setContentCompressionResistancePriority(
      .defaultLow, for: .horizontal)

    addSubview(backgroundView)
    backgroundView.addSubview(headerStackView)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Layout.outerHorizontalPadding),
      backgroundView.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Layout.outerHorizontalPadding),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      headerStackView.leadingAnchor.constraint(
        equalTo: backgroundView.leadingAnchor, constant: Layout.innerHorizontalPadding),
      headerStackView.trailingAnchor.constraint(
        equalTo: backgroundView.trailingAnchor, constant: -Layout.innerHorizontalPadding),
      headerStackView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 6),
      headerStackView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -6),
      settingsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
    ])
  }

  func refresh() {
    // Update server status based on server state.
    if server.isRunning {
      let linkText = "localhost:\(LlamaServer.defaultPort)"
      let full = "Running on \(linkText)"
      let url = URL(string: "http://\(linkText)/")!

      let attributed = NSMutableAttributedString(
        string: full,
        attributes: [
          .font: Typography.secondary,
          .foregroundColor: NSColor.controlTextColor,
        ])
      // Use .link attribute so NSTextField handles clicks automatically.
      if let range = full.range(of: linkText) {
        let nsRange = NSRange(range, in: full)
        attributed.addAttributes(
          [
            .link: url,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
          ], range: nsRange)
      }
      serverStatusLabel.attributedStringValue = attributed
      serverStatusLabel.toolTip = "Open llama-server"
    } else {
      serverStatusLabel.attributedStringValue = NSAttributedString(
        string: "Server not running",
        attributes: [
          .font: Typography.secondary,
          .foregroundColor: NSColor.controlTextColor,
        ]
      )
      serverStatusLabel.toolTip = nil
    }

    needsDisplay = true
  }

  @objc private func toggleSettings() {
    NotificationCenter.default.post(name: .LBToggleSettingsVisibility, object: nil)
  }

}
