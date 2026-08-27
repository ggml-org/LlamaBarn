import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Shows the server's URL as a QR code, so the phone that's going to use it
/// doesn't have to be typed at.
///
/// Turning on network access gives you an address like `100.117.107.123:9931`.
/// The Mac knows it and the menu displays it, but the device that needs it is
/// the one in your hand -- and copying an IP across by reading it off a screen
/// is where people give up. A camera solves the transfer: point, tap, the web
/// UI opens.
///
/// Only offered when the server is bound somewhere other than loopback; a QR
/// code for `localhost` would be a code for the phone's own self.
final class ServerQRPopover: NSViewController, NSPopoverDelegate {
  private let url: URL
  private let popover = NSPopover()
  private var observer: NSObjectProtocol?

  /// Big enough to scan from a comfortable distance without dominating the
  /// screen. Below ~160pt phones start needing to be held close.
  private static let codeSize: CGFloat = 180

  init(url: URL) {
    self.url = url
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }

  override func loadView() {
    let image = NSImageView()
    image.image = Self.qrImage(for: url.absoluteString, size: Self.codeSize)
    image.frame = NSRect(x: 20, y: 44, width: Self.codeSize, height: Self.codeSize)

    // The address in text as well: it's the fallback when a camera won't
    // cooperate, and it lets the user confirm what they're about to scan.
    let caption = NSTextField(labelWithString: url.host ?? url.absoluteString)
    caption.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    caption.textColor = .secondaryLabelColor
    caption.alignment = .center
    caption.frame = NSRect(x: 0, y: 22, width: Self.codeSize + 40, height: 14)

    let hint = NSTextField(labelWithString: "Scan to open on your phone")
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .controlTextColor
    hint.alignment = .center
    hint.frame = NSRect(x: 0, y: Self.codeSize + 52, width: Self.codeSize + 40, height: 16)

    let content = NSView(
      frame: NSRect(x: 0, y: 0, width: Self.codeSize + 40, height: Self.codeSize + 80))
    content.addSubview(image)
    content.addSubview(caption)
    content.addSubview(hint)
    view = content
  }

  /// Renders `string` as a QR code.
  ///
  /// The generator emits one module per pixel, so the raw output is tiny and
  /// would come out blurred by interpolation -- scaling it up first keeps the
  /// edges hard, which is what a camera needs to lock onto.
  private static func qrImage(for string: String, size: CGFloat) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    // Medium correction: a screen is a clean scanning surface, so the extra
    // redundancy of a higher level would only make the modules smaller.
    filter.correctionLevel = "M"

    guard let output = filter.outputImage else { return nil }
    let scale = size / output.extent.width
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
  }

  /// Shows the code pointing at the status bar button, matching `HintPopover`.
  func show(from statusItem: NSStatusItem) {
    guard let button = statusItem.button else { return }

    popover.contentViewController = self
    popover.delegate = self
    // Transient rather than semitransient: this one is dismissed by looking
    // away, and it has nothing to interact with.
    popover.behavior = .transient
    popover.animates = true

    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

    // Reopening the menu means the user has moved on.
    observer = NotificationCenter.default.addObserver(
      forName: NSMenu.didBeginTrackingNotification, object: statusItem.menu, queue: .main
    ) { [weak self] _ in
      self?.close()
    }
  }

  func close() {
    popover.performClose(nil)
    if let observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
  }
}
