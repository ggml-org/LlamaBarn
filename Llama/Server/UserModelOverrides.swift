import Foundation
import OSLog

/// User-owned additions to the generated `models.ini`.
///
/// The app regenerates `models.ini` from a scan of the model cache on every
/// launch, so anything a user types into that file is lost on the next scan.
/// This is the escape hatch: a sibling file the app only ever reads, merged
/// into the generated content at write time.
///
/// Precedence is deliberately flat -- a key present in the user file always
/// wins, including over values derived from memory profiling. A conditional
/// rule ("app wins on memory-safety keys") would make overrides silently
/// no-op, which is worse than letting someone pick a `ctx-size` their machine
/// can't hold: the failure is at least legible and self-inflicted.
enum UserModelOverrides {
  private static let logger = Logger(subsystem: Logging.subsystem, category: "UserModelOverrides")

  /// Filename of the user-owned file.
  static let filename = "models.user.ini"

  /// Lives in `~/.config/llama` rather than next to the generated `models.ini`
  /// in Application Support, which is for state the app manages and is hidden
  /// in Finder -- hostile to a file whose entire purpose is being hand-edited.
  ///
  /// Not `~/.llama-app` (where the managed binary lives): that directory is
  /// only created by the installer, and a machine that resolves to a Homebrew
  /// `llama` never runs it. Config that exists on some installs and not others
  /// is worse than one more directory.
  static var configDir: URL {
    URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent(".config/llama", isDirectory: true)
  }

  static var fileURL: URL {
    configDir.appendingPathComponent(filename)
  }

  /// One `[section]` and its keys, in the order they were written.
  ///
  /// Order is preserved rather than using a dictionary so that a section the
  /// app doesn't generate can be passed through looking like what the user
  /// typed -- these files get hand-edited and diffed.
  struct Section {
    var name: String
    var pairs: [(key: String, value: String)]

    /// Sets `key`, replacing an existing entry in place or appending a new one.
    /// In-place replacement keeps app-generated keys in their original position
    /// when a user overrides one.
    mutating func set(_ key: String, _ value: String) {
      if let index = pairs.firstIndex(where: { $0.key == key }) {
        pairs[index].value = value
      } else {
        pairs.append((key: key, value: value))
      }
    }

    func serialized() -> String {
      var out = "[\(name)]\n"
      for pair in pairs {
        out += "\(pair.key) = \(pair.value)\n"
      }
      return out + "\n"
    }
  }

  /// Parses the user file, or returns an empty list if it's absent or unreadable.
  ///
  /// Absent is the overwhelmingly common case, so it isn't logged. Unreadable
  /// is: a file that exists but can't be decoded is a user who thinks they've
  /// configured something and hasn't.
  static func load() -> [Section] {
    let url = fileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }

    guard let data = try? Data(contentsOf: url),
      let text = String(data: data, encoding: .utf8)
    else {
      logger.error("Could not read \(filename) at \(url.path)")
      return []
    }

    let sections = parse(text)
    logger.info("Loaded \(sections.count) override section(s) from \(filename)")
    return sections
  }

  /// Minimal INI parse: `[section]` headers and `key = value` lines.
  ///
  /// Comments (`;` or `#`) and blank lines are dropped rather than preserved --
  /// the output is a generated file users aren't meant to edit, so carrying
  /// their comments into it would invite editing the wrong file. Keys before
  /// any section header are ignored: `models.ini` has no global section, so
  /// they'd have nowhere to go.
  static func parse(_ text: String) -> [Section] {
    var sections: [Section] = []

    for rawLine in text.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }

      if line.hasPrefix("[") && line.hasSuffix("]") {
        let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
          sections.append(Section(name: name, pairs: []))
        }
        continue
      }

      // `value` may itself contain `=` (e.g. `chat-template-kwargs`), so split
      // on the first separator only.
      guard let separator = line.firstIndex(of: "="), !sections.isEmpty else { continue }
      let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
      let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      if key.isEmpty { continue }

      sections[sections.count - 1].set(key, value)
    }

    return sections
  }

  /// Applies user overrides to app-generated sections.
  ///
  /// Matching sections are merged per-key, so overriding `temp` doesn't require
  /// restating the `model` and `mmproj` paths. Sections that match nothing the
  /// app generated are appended verbatim -- that's what lets someone define a
  /// model the scan can't produce, such as a draft model from another repo.
  static func apply(to generated: [Section], overrides: [Section]) -> [Section] {
    var merged = generated
    var indexByName: [String: Int] = [:]
    for (index, section) in merged.enumerated() {
      indexByName[section.name] = index
    }

    for override in overrides {
      if let index = indexByName[override.name] {
        for pair in override.pairs {
          merged[index].set(pair.key, pair.value)
        }
      } else {
        indexByName[override.name] = merged.count
        merged.append(override)
      }
    }

    return merged
  }
}
