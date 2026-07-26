import Foundation
import Metal

/// Utility for system memory detection and formatting
enum SystemMemory {

  // Cache physical memory for the session; RAM doesn't change at runtime.
  // Still honors BARN_SIMULATE_MEM_GB if set at launch.
  private static let physicalMemBytes: UInt64 = {
    if let simulatedGB = ProcessInfo.processInfo.environment["BARN_SIMULATE_MEM_GB"],
      let gb = Double(simulatedGB), gb > 0
    {
      return UInt64(gb * 1024 * 1024 * 1024)
    }
    var size = MemoryLayout<UInt64>.size
    var memsize: UInt64 = 0
    let result = sysctlbyname("hw.memsize", &memsize, &size, nil, 0)
    return result == 0 ? memsize : 0
  }()

  /// How much memory Metal recommends a process hold for GPU work, cached for
  /// the session. This -- not physical RAM -- is what a model's size is
  /// measured against: llama.cpp reports it as the device's total
  /// (`ggml_metal_device_get_memory`) and fits against it. Apple sets it
  /// around three quarters of RAM on smaller Macs and higher on large ones
  /// (84% of 128 GB, measured), so it can't be derived from `hw.memsize` -- it
  /// has to be asked for.
  ///
  /// It's a recommendation, not a hard cap: allocations past it succeed and
  /// ggml only warns, trading speed for swap. So it's the right line for a
  /// default, but not proof that a larger model can't run.
  private static let gpuWorkingSetBytes: UInt64 = {
    // Fall back to the fraction Apple uses on the Macs we target when there's
    // no Metal device, and use it for simulated memory too: with `hw.memsize`
    // overridden, the real device's working set would dwarf the pretend RAM
    // and every fit check would pass.
    let approximation = UInt64(Double(physicalMemBytes) * 0.75)
    if ProcessInfo.processInfo.environment["BARN_SIMULATE_MEM_GB"] != nil {
      return approximation
    }
    guard let device = MTLCreateSystemDefaultDevice() else { return approximation }
    return device.recommendedMaxWorkingSetSize
  }()

  /// Metal's working-set limit in Mb.
  static var gpuWorkingSetMb: UInt64 { gpuWorkingSetBytes / (1024 * 1024) }

  /// Returns cached system memory in bytes for this process lifetime.
  static var memoryBytes: UInt64 { physicalMemBytes }

  /// Gets system memory in Mb
  static var memoryMb: UInt64 {
    return memoryBytes / (1024 * 1024)
  }
}
