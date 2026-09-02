import SwiftUI

/// Syntax highlighting for the server command shown on the Command tab.
/// Pure string-to-`AttributedString` work with no view state, kept apart from
/// the settings window so that file stays about the window.
enum ServerCommandHighlighter {
  /// Appearance-adaptive palette for the server-command syntax highlighting.
  /// Kept deliberately low-saturation and Xcode-flavored so the block reads as
  /// "structured" rather than a rainbow. Each color carries a light and a dark
  /// variant via `NSColor.dynamic`. Tuned in a standalone playground.
  private enum Colors {
    /// `--flags` and the `export` keyword.
    static let flag = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 45 / 255, green: 108 / 255, blue: 168 / 255, alpha: 1),
      dark: NSColor(srgbRed: 111 / 255, green: 176 / 255, blue: 232 / 255, alpha: 1)))
    /// Env-var names (`KEY` in `KEY=value`).
    static let env = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 58 / 255, green: 125 / 255, blue: 92 / 255, alpha: 1),
      dark: NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 168 / 255, alpha: 1)))
    /// The `serve` subcommand.
    static let serve = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 31 / 255, green: 45 / 255, blue: 92 / 255, alpha: 1),
      dark: NSColor(srgbRed: 155 / 255, green: 180 / 255, blue: 255 / 255, alpha: 1)))
    /// The leading binary path.
    static let path = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 43 / 255, green: 58 / 255, blue: 103 / 255, alpha: 1),
      dark: NSColor(srgbRed: 155 / 255, green: 180 / 255, blue: 255 / 255, alpha: 1)))
    /// Integer values (ports, counts, seconds).
    static let int = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 176 / 255, green: 105 / 255, blue: 31 / 255, alpha: 1),
      dark: NSColor(srgbRed: 217 / 255, green: 165 / 255, blue: 102 / 255, alpha: 1)))
    /// String / path values.
    static let string = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 160 / 255, green: 74 / 255, blue: 63 / 255, alpha: 1),
      dark: NSColor(srgbRed: 224 / 255, green: 143 / 255, blue: 128 / 255, alpha: 1)))
  }

  /// `command` with light syntax highlighting applied per token, so the
  /// command's structure is easy to scan. Purely cosmetic -- the underlying
  /// text is identical to `command`. Coloring rules, by token shape:
  /// `export` and `--flags` share the flag color; env-var names read as keys;
  /// the `serve` subcommand and the leading binary path each get their own
  /// tint; values (env-var RHS and flag arguments) color as integers or
  /// strings; the trailing line-continuation `\` is dimmed.
  static func highlight(_ command: String) -> AttributedString {
    var result = AttributedString()

    let lines = command.components(separatedBy: "\n")
    for (lineIdx, line) in lines.enumerated() {
      if lineIdx > 0 { result.append(AttributedString("\n")) }

      // Preserve the leading indent verbatim, then tokenize the rest.
      let indent = line.prefix { $0 == " " }
      result.append(AttributedString(String(indent)))

      let tokens = tokenize(String(line.dropFirst(indent.count)))
      // `prevWasFlag` marks that the previous token was a `--flag`, so this
      // token is its value and colors as a value rather than by its own shape.
      // `inComment` latches at a `#` token: it and everything after it on the
      // line (the "# custom arguments" tag) dims as a comment.
      var prevWasFlag = false
      var inComment = false
      for (tokenIdx, token) in tokens.enumerated() {
        if tokenIdx > 0 { result.append(AttributedString(" ")) }
        if inComment || token.hasPrefix("#") {
          inComment = true
          var attr = AttributedString(token)
          attr.foregroundColor = .secondary
          result.append(attr)
          continue
        }
        result.append(highlight(token, isFirstOnLine: tokenIdx == 0, isFlagValue: prevWasFlag))
        prevWasFlag = token.hasPrefix("--")
      }
    }

    return result
  }

  /// Splits a command line into space-delimited tokens, but keeps a
  /// single-quoted span (which may contain spaces, e.g. the `models.ini` path)
  /// as a single token so it can be colored as one string.
  private static func tokenize(_ line: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var inQuotes = false
    for char in line {
      if char == "'" {
        inQuotes.toggle()
        current.append(char)
      } else if char == " " && !inQuotes {
        tokens.append(current)
        current = ""
      } else {
        current.append(char)
      }
    }
    tokens.append(current)
    return tokens
  }

  /// Colors a single token according to its shape and position (see
  /// `highlight(_:)`).
  private static func highlight(_ token: String, isFirstOnLine: Bool, isFlagValue: Bool) -> AttributedString {
    var attr = AttributedString(token)

    if token == "\\" {
      // Trailing line-continuation backslash -- dim, it's just glue.
      attr.foregroundColor = .secondary
    } else if token == "export" {
      // The `export` keyword -- same tint as flags.
      attr.foregroundColor = Colors.flag
    } else if token == "serve" {
      // The subcommand.
      attr.foregroundColor = Colors.serve
    } else if token.hasPrefix("--") {
      // A flag.
      attr.foregroundColor = Colors.flag
    } else if isFlagValue {
      // A flag's argument -- color by its value shape.
      attr.foregroundColor = valueColor(for: token)
    } else if let eq = token.firstIndex(of: "="),
      token[..<eq].allSatisfy({ $0.isUppercase || $0 == "_" }), !token.isEmpty
    {
      // An env-var assignment `KEY=value`: tint the key, color the value by its
      // shape, and leave the `=` default. Built by concatenation so there's no
      // index math or empty-value edge case.
      let value = String(token[token.index(after: eq)...])
      var key = AttributedString(token[..<eq])
      key.foregroundColor = Colors.env
      var val = AttributedString(value)
      val.foregroundColor = valueColor(for: value)
      return key + AttributedString("=") + val
    } else if isFirstOnLine && token.contains("/") {
      // The leading binary path on the `llama serve` line.
      attr.foregroundColor = Colors.path
    }

    return attr
  }

  /// The color for a value token -- integer tint for all-digit values,
  /// string tint otherwise (paths, quoted strings).
  private static func valueColor(for token: String) -> Color {
    let allDigits = !token.isEmpty && token.allSatisfy { $0.isNumber }
    return allDigits ? Colors.int : Colors.string
  }
}
