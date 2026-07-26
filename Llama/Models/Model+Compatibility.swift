import Foundation

extension Model {
  // MARK: - Memory Calculations

  /// We evaluate compatibility assuming a 4k-token context, which is the
  /// default llama.cpp launches with when no explicit value is provided.
  /// Models must also support at least this context length to launch.
  static let compatibilityCtxWindowTokens: Double = 4_096

  /// Slack (in MB) left inside the GPU working set for what the memory
  /// estimate can't see: allocation rounding, a model still resident while the
  /// next one loads. llama.cpp's own default for `--fit-target`, and their
  /// number for the error in the fit we rely on.
  static let fitSlackMb: Double = 1024

  /// Physical RAM (in MB) kept out of a model's reach for macOS and other
  /// apps. Absolute rather than proportional, because the desktop's needs
  /// don't shrink on a small Mac -- which is the whole reason this exists.
  /// On roomy machines the working set already leaves far more than this
  /// unused, so the term does nothing; on an 8 GB Mac the working set leaves
  /// only ~2 GB outside itself and this is what pulls the budget down.
  static let osFloorMb: Double = 4096

  /// Overhead multiplier applied to the model file size when estimating weight
  /// memory without a MemProfile measurement. 1.05 = 5% overhead.
  static let weightOverheadMultiplier = 1.05

  /// The memory a model may use on this device -- whichever of the two limits
  /// binds first:
  ///
  /// - `workingSet - fitSlack`: what the GPU will hold, less llama.cpp's
  ///   margin. We read Metal's working set rather than taking a fraction of
  ///   `hw.memsize` because Apple's ratio varies by machine (~75% on common
  ///   configurations, 84% measured on a 128 GB Mac) -- assuming 75%
  ///   understated large Macs and blocked sizes that run fine. llama.cpp
  ///   treats the same figure as the device's total and fits against it, so
  ///   this side matches `serve`'s own limit.
  /// - `physicalRam - osFloor`: leaves the desktop enough to work with. Only
  ///   binds on small Macs, where the memory outside the working set isn't
  ///   enough to host macOS on its own.
  static var deviceMemoryBudgetMb: Double {
    let workingSetMb = Double(SystemMemory.gpuWorkingSetMb)
    let physicalMb = Double(SystemMemory.memoryMb)
    return max(min(workingSetMb - fitSlackMb, physicalMb - osFloorMb), 0)
  }

  /// The margin to hand `serve` as `--fit-target`: everything between the
  /// working set and our budget, so its runtime fit lands on the same number
  /// our predictions do. Larger than `fitSlackMb` exactly when the OS floor is
  /// the binding limit.
  static var fitTargetMb: Double {
    max(Double(SystemMemory.gpuWorkingSetMb) - deviceMemoryBudgetMb, 0)
  }

  /// Rough pre-download fit check used by the deeplink resolver and the
  /// Discover picks: model weight memory ≈ fileSize × 1.05 must be within
  /// budget. Unknown sizes pass — don't filter out. The real compatibility
  /// check runs at launch once the MemProfile probe has measured resident bytes.
  static func estimatedWeightFits(bytes: Int64?, budgetMb: Double) -> Bool {
    guard let bytes, bytes > 0 else { return true }
    let weightMb = Double(bytes) / 1_048_576.0 * weightOverheadMultiplier
    return weightMb <= budgetMb
  }

  func isCompatible(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> Bool {
    compatibilityInfo(ctxWindowTokens: ctxWindowTokens).isCompatible
  }

  func incompatibilitySummary(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> String? {
    compatibilityInfo(ctxWindowTokens: ctxWindowTokens).incompatibilitySummary
  }

  func runtimeMemoryUsageMb(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> UInt64 {
    // Memory calculations use binary units so they line up with Activity Monitor.
    let weightMb = weightMemoryMb
    let ctxMultiplier = ctxWindowTokens / 1_000.0
    let ctxBytes = Double(ctxBytesPer1kTokens) * ctxMultiplier
    let ctxMb = ctxBytes / 1_048_576.0
    let totalMb = weightMb + ctxMb
    return UInt64(ceil(totalMb))
  }

  // MARK: - Private Helpers

  /// Converts bytes to megabytes using binary units (1 MB = 2^20 bytes)
  private static func bytesToMb(_ bytes: Int64) -> Double {
    Double(bytes) / 1_048_576.0
  }

  /// Weight memory (MB) used by compatibility math.
  /// Prefers the measured `residentBytes` (correct for MoE models). Falls
  /// back to `fileSize * weightOverheadMultiplier` when the MemProfile probe
  /// hasn't landed yet (pre-download placeholders).
  private var weightMemoryMb: Double {
    if residentBytes > 0 {
      return Double(residentBytes) / 1_048_576.0
    }
    let fileSizeMb = Self.bytesToMb(fileSize)
    return fileSizeMb * Self.weightOverheadMultiplier
  }

  /// Computes compatibility info for a model
  private func compatibilityInfo(
    ctxWindowTokens: Double = compatibilityCtxWindowTokens
  ) -> CompatibilityInfo {
    if Double(ctxWindow) < Self.compatibilityCtxWindowTokens {
      return CompatibilityInfo(
        isCompatible: false,
        incompatibilitySummary: "requires models with ≥4k context"
      )
    }

    if ctxWindowTokens > 0 && ctxWindowTokens > Double(ctxWindow) {
      // Model's native context window is smaller than requested
      let maxLabel = nativeMaxTier?.label ?? "\(ctxWindow / 1024)k"
      return CompatibilityInfo(
        isCompatible: false,
        incompatibilitySummary: "model max is \(maxLabel)"
      )
    }

    let budgetMb = Self.deviceMemoryBudgetMb
    let estimatedMemoryUsageMb = runtimeMemoryUsageMb(
      ctxWindowTokens: ctxWindowTokens)

    func memoryRequirementSummary() -> String {
      // Work back from the requirement to a Mac that could meet it, inverting
      // both limbs of the budget and taking whichever demands more RAM. The
      // working-set limb needs Apple's ratio, which we can only measure on
      // *this* machine, so sizing another one assumes the usual ~75% -- fine
      // for naming a memory tier, too rough to gate anything on.
      let neededMb = Double(estimatedMemoryUsageMb)
      let fromWorkingSet = (neededMb + Self.fitSlackMb) / 0.75
      let fromOsFloor = neededMb + Self.osFloorMb
      let requiredTotalMb = max(fromWorkingSet, fromOsFloor)
      let gb = ceil(requiredTotalMb / 1024.0)

      let commonSizes: [Double] = [8, 16, 18, 24, 32, 36, 48, 64, 96, 128, 192]
      let displayGb = commonSizes.first(where: { $0 >= gb }) ?? gb

      return String(format: "Requires a Mac with %.0f GB+ of memory", displayGb)
    }

    // No budget means we couldn't read the device's memory at all; report the
    // requirement rather than guessing that it fits.
    guard budgetMb > 0 else {
      return CompatibilityInfo(
        isCompatible: false,
        incompatibilitySummary: memoryRequirementSummary()
      )
    }

    let isCompatible = estimatedMemoryUsageMb <= UInt64(budgetMb)

    return CompatibilityInfo(
      isCompatible: isCompatible,
      incompatibilitySummary: isCompatible ? nil : memoryRequirementSummary()
    )
  }

  /// Context tiers this device can actually run -- the ones the picker leaves
  /// selectable.
  /// When the MemProfile probe is still pending (or failed), returns only 4K as a safe
  /// default — without `ctxBytesPer1kTokens`, memory estimates are artificially low and
  /// all tiers would falsely appear compatible.
  var supportedContextTiers: [ContextTier] {
    if ctxBytesPer1kTokens <= 0 {
      return [.k4]
    }

    var tiers = ContextTier.standardTiers.filter { tier in
      isCompatible(ctxWindowTokens: Double(tier.rawValue))
    }

    if isCompatible(ctxWindowTokens: Double(ContextTier.k256.rawValue)),
      !tiers.contains(.k256)
    {
      tiers.append(.k256)
    }

    return tiers.sorted()
  }

  /// All tiers the model itself supports (within its native context window),
  /// regardless of whether this device has the memory to run them. The picker
  /// shows these, disabling the ones not in `supportedContextTiers`, so the
  /// user can see the model's full range rather than a silently truncated one.
  var displayContextTiers: [ContextTier] {
    if ctxBytesPer1kTokens <= 0 {
      return [.k4]
    }

    var tiers = ContextTier.standardTiers.filter { $0.rawValue <= ctxWindow }
    if ContextTier.k256.rawValue <= ctxWindow {
      tiers.append(.k256)
    }
    return tiers.sorted()
  }

  /// The largest standard tier that fits within the model's native context window.
  /// Independent of device RAM -- this is the model's spec ceiling.
  var nativeMaxTier: ContextTier? {
    ContextTier.allCases.last { $0.rawValue <= ctxWindow }
  }

  /// The effective context tier for this model.
  /// Returns user's selection if set and still compatible, otherwise 4K.
  var effectiveCtxTier: ContextTier? {
    let supported = supportedContextTiers
    guard !supported.isEmpty else { return nil }

    // Check if user has a saved preference that's still valid
    if let selected = UserSettings.selectedCtxTier(for: id),
      supported.contains(selected)
    {
      return selected
    }

    return .k4
  }

  private struct CompatibilityInfo {
    let isCompatible: Bool
    let incompatibilitySummary: String?
  }
}
