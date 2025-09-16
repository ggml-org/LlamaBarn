import AppKit
import Foundation

/// Header row showing app name and server status.
final class HeaderMenuItemView: NSView {

  private unowned let server: LlamaServer
  private let titleLabel = NSTextField(labelWithString: "")
  private let subtitleLabel = NSTextField(labelWithString: "")
  private lazy var subtitleClickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(openServerURL))
  private let backgroundView = NSView()
  private let appBaseTitle = "LlamaBarn"
  private let versionString: String
  private let buildString: String
  private let llamaCppVersion: String

  init(server: LlamaServer, llamaCppVersion: String) {
    self.server = server
    // App version/build
    let ver =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    self.versionString = ver
    self.buildString = build
    self.llamaCppVersion = llamaCppVersion
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

    titleLabel.font = MenuTypography.primarySemibold
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.lineBreakMode = .byTruncatingTail

    subtitleLabel.font = MenuTypography.secondary
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.lineBreakMode = .byTruncatingTail
    // Subtitle content now reflects server status; versions move to Settings submenu.
    subtitleLabel.stringValue = ""
    subtitleLabel.addGestureRecognizer(subtitleClickRecognizer)
    subtitleClickRecognizer.isEnabled = false

    let stack = NSStackView(views: [titleLabel, subtitleLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(backgroundView)
    backgroundView.addSubview(stack)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: MenuMetrics.outerHorizontalPadding),
      backgroundView.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -MenuMetrics.outerHorizontalPadding),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(
        equalTo: backgroundView.leadingAnchor, constant: MenuMetrics.innerHorizontalPadding),
      stack.trailingAnchor.constraint(
        equalTo: backgroundView.trailingAnchor, constant: -MenuMetrics.innerHorizontalPadding),
      stack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -6),
    ])
  }

  func refresh() {
    // Always show a clean title.
    titleLabel.attributedStringValue = NSAttributedString(
      string: appBaseTitle,
      attributes: [
        .font: MenuTypography.primarySemibold,
        .foregroundColor: NSColor.labelColor,
      ]
    )

    // Merge server status into the header subtitle. Include server memory footprint when running.
    if server.isRunning {
      let base = "Running on "
      let linkText = "localhost:\(LlamaServer.defaultPort)"
      let full = base + linkText

      let attributed = NSMutableAttributedString(string: full, attributes: [
        .font: MenuTypography.secondary,
        .foregroundColor: NSColor.labelColor,
      ])
      // Make just the host:port look like a link.
      if let range = full.range(of: linkText) {
        let nsRange = NSRange(range, in: full)
        attributed.addAttributes([
          .foregroundColor: NSColor.linkColor,
          .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: nsRange)
      }
      subtitleLabel.attributedStringValue = attributed
      subtitleLabel.toolTip = "Open llama-server"
      subtitleClickRecognizer.isEnabled = true
    } else {
      subtitleLabel.attributedStringValue = NSAttributedString(
        string: "Server not running",
        attributes: [
          .font: MenuTypography.secondary,
          .foregroundColor: NSColor.secondaryLabelColor,
        ]
      )
      subtitleLabel.toolTip = nil
      subtitleClickRecognizer.isEnabled = false
    }

    needsDisplay = true
  }

  @objc private func openServerURL() {
    guard server.isRunning else { return }
    if let url = URL(string: "http://localhost:\(LlamaServer.defaultPort)/") {
      NSWorkspace.shared.open(url)
    }
  }

}
