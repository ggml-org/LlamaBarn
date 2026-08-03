import Foundation

/// Shared selection policy for sidecar GGUFs (`mmproj*.gguf` vision projectors
/// and the `mtp-….gguf` / `dflash-….gguf` speculative draft heads).
///
/// Two discovery paths need the exact same policy — the deeplink resolver
/// choosing among HF API siblings (`HFRepoResolver`) and the cache scan
/// choosing among on-disk files (`HFCache`) — and the resulting attachment is
/// identity-relevant (it feeds `models.ini`), so the policy lives here once
/// instead of being mirrored in both.
enum SidecarPicker {

  /// True for a vision-projector sidecar. The ggml-org convention is an
  /// `mmproj` prefix (`mmproj-*.gguf`), but community repos also use it as a
  /// suffix (e.g. `PaddleOCR-VL-1.6-GGUF-mmproj.gguf`), so match `mmproj`
  /// anywhere in the basename. Accepts full repo-relative paths; only the
  /// basename is considered.
  static func isMmproj(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    return name.contains("mmproj") && name.hasSuffix(".gguf")
  }

  /// True for an MTP draft-head sidecar (`mtp-….gguf`) — the convention
  /// llama.cpp keys on (`find_best_mtp`). Accepts full repo-relative paths.
  static func isMtp(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    return name.hasPrefix("mtp-") && name.hasSuffix(".gguf")
  }

  /// True for a DFlash draft-head sidecar (`dflash-….gguf`). DFlash is a
  /// block-diffusion drafter with its own architecture (`LLM_ARCH_DFLASH`) that
  /// borrows the target's token embeddings and output projection, so the file
  /// can't be loaded as a model on its own -- same story as `mtp-`, different
  /// speculation scheme.
  static func isDflash(_ path: String) -> Bool {
    let name = (path as NSString).lastPathComponent.lowercased()
    return name.hasPrefix("dflash-") && name.hasSuffix(".gguf")
  }

  /// Picks the mmproj sidecar for `mainPath`. Repos routinely ship more than
  /// one (every current ggml-org VLM ships `mmproj-…-BF16` + `mmproj-…-Q8_0`),
  /// so ambiguity is the normal case, not a reason to skip: without an mmproj
  /// the model loads as text-only and image input silently disappears.
  static func mmproj(among names: [String], mainPath: String) -> String? {
    bestSibling(among: names, mainPath: mainPath, isCandidate: isMmproj)
  }

  /// Picks the MTP draft head for `mainPath`. `tag` is the main file's canonical
  /// quant tag, which lets an exact `-<TAG>.gguf` head win over a merely
  /// near-in-bits one.
  static func mtp(among names: [String], mainPath: String, tag: String?) -> String? {
    bestSibling(among: names, mainPath: mainPath, tag: tag, isCandidate: isMtp)
  }

  /// Port of llama.cpp's `find_best_sibling` (`common/download.cpp`), the
  /// function behind its `find_best_mmproj` / `find_best_mtp`. Keeping the two
  /// in step matters because the same repo has to resolve the same way whether
  /// the user installs it through us or through `llama serve -hf`.
  ///
  /// A candidate qualifies only if its directory path is a prefix of the main
  /// file's — the same directory, or an ancestor of it. That covers both
  /// real-world layouts in one rule: per-quant subdir repos that ship
  /// `Q4_K_M/mmproj-….gguf` beside the quant, and subdir repos that keep a
  /// single shared sidecar at the snapshot root. A sidecar in an unrelated
  /// sibling directory (another quant's) is rejected outright.
  ///
  /// Qualifying candidates rank by: deepest directory (so the main file's own
  /// directory beats the root), then an exact `tag` match, then the smallest
  /// distance in quant bits from the main file (`GGUFQuant.quantBits`) — which
  /// is what lands a Q4_K_M or Q8_0 model on the Q8_0 mmproj and a BF16 model
  /// on the BF16 one.
  ///
  /// One deliberate divergence: candidates are ranked in sorted order, so an
  /// exact tie resolves the same way every scan. Upstream leaves ties to
  /// manifest order; here the choice is written into `models.ini`, and a path
  /// that flips between scans would rewrite it for no reason.
  static func bestSibling(
    among names: [String],
    mainPath: String,
    tag: String? = nil,
    isCandidate: (String) -> Bool
  ) -> String? {
    let mainDirs = dirComponents(of: mainPath)
    let mainBits =
      tag.map(GGUFQuant.quantBits(forTag:)) ?? GGUFQuant.quantBits(forPath: mainPath)
    let tagUpper = tag?.uppercased()

    var best: (path: String, depth: Int, exact: Bool, diff: Int)?

    for path in names.sorted() where isCandidate(path) {
      let dirs = dirComponents(of: path)
      guard dirs.count <= mainDirs.count, mainDirs.starts(with: dirs) else { continue }

      let depth = dirs.count
      let diff = abs(GGUFQuant.quantBits(forPath: path) - mainBits)
      let exact = tagUpper.map { path.uppercased().contains("-\($0).") } ?? false

      if let best {
        let better =
          depth > best.depth
          || (depth == best.depth && exact && !best.exact)
          || (depth == best.depth && exact == best.exact && diff < best.diff)
        guard better else { continue }
      }
      best = (path, depth, exact, diff)
    }

    return best?.path
  }

  /// The directory components of a repo-relative path (`Q4_K_M/a.gguf` →
  /// `["Q4_K_M"]`, `a.gguf` → `[]`).
  private static func dirComponents(of path: String) -> [Substring] {
    Array(path.split(separator: "/").dropLast())
  }
}
