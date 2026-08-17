import AppKit
import os.log

/// The API snippet builder: a page that composes a request against the local
/// server (thinking, streaming, structured output, images, tools), shows it as
/// runnable curl / Python / JavaScript, and can send it in place.
///
/// It opens in the browser rather than an in-app window, matching "Chat with
/// model" next to it in the menu -- two adjacent rows that both lead to a web
/// page should behave the same way. It also keeps this a plain web page, which
/// is the shape it needs to be in if it ever moves into the server's own web
/// UI upstream.
///
/// The page ships as a bundled resource rather than being served, so opening
/// it means staging a copy on disk with the app's config baked in and handing
/// the browser a file URL.
enum SnippetBuilder {
  private static let log = Logger(subsystem: Logging.subsystem, category: "SnippetBuilder")

  /// Where the staged page lives. A stable path (rather than a unique temp
  /// file per open) so repeated opens reuse the same URL: the browser treats
  /// it as the same page, reloading the existing tab's content instead of
  /// accumulating one tab per click.
  private static var stagedPageURL: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("llama-build-request.html")
  }

  /// Stages the page with `modelId` preselected and returns its URL, or nil if
  /// the resource is missing or can't be written.
  ///
  /// Fetches from the page run cross-origin (a file URL's origin is opaque),
  /// which works because the server sends permissive CORS headers -- it
  /// reflects the request's `Origin`, including the `null` a file URL sends.
  @MainActor
  static func stagePage(modelId: String) -> URL? {
    guard let source = Bundle.main.url(forResource: "SnippetBuilder", withExtension: "html"),
      let page = try? String(contentsOf: source, encoding: .utf8)
    else {
      log.error("SnippetBuilder.html missing from the bundle")
      return nil
    }

    let base = "http://\(LlamaServer.resolvedHost):\(LlamaServer.port)"
    // Encoded as JSON so a model id containing quotes can't break out of the
    // surrounding script.
    guard let json = try? JSONSerialization.data(withJSONObject: ["baseUrl": base, "model": modelId]),
      let config = String(data: json, encoding: .utf8)
    else { return nil }

    // Injected ahead of the page's own script, which reads `LLAMA_CONFIG` for
    // the server address and preselected model. Scoped to the first `<script>`
    // so this can't silently apply twice if the page grows another one.
    let staged = page.replacingOccurrences(
      of: "<script>",
      with: "<script>window.LLAMA_CONFIG = \(config);",
      options: [],
      range: page.range(of: "<script>")
    )

    do {
      try staged.write(to: stagedPageURL, atomically: true, encoding: .utf8)
    } catch {
      log.error("Failed to stage the builder page: \(error.localizedDescription, privacy: .public)")
      return nil
    }

    return stagedPageURL
  }
}
