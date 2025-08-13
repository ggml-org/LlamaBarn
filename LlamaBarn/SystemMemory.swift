import Foundation

/// Utility for system memory detection and formatting
enum SystemMemory {

  /// Gets system memory in bytes
  /// Can be overridden with BARN_SIMULATE_MEM_GB environment variable for testing
  static func getMemoryBytes() -> UInt64 {
    // Check for simulated memory override (for testing different memory configurations)
    if let simulatedGB = ProcessInfo.processInfo.environment["BARN_SIMULATE_MEM_GB"],
      let gb = Double(simulatedGB), gb > 0
    {
      return UInt64(gb * 1024 * 1024 * 1024)  // Convert GB to bytes
    }

    // Use actual system memory
    var size = MemoryLayout<UInt64>.size
    var memsize: UInt64 = 0

    let result = sysctlbyname("hw.memsize", &memsize, &size, nil, 0)

    if result == 0 {
      return memsize
    } else {
      return 0
    }
  }

  /// Gets system memory in MB
  static func getMemoryMB() -> UInt64 {
    return getMemoryBytes() / (1024 * 1024)
  }

  /// Formats system memory for display
  static func formatMemory() -> String {
    let memsize = getMemoryBytes()
    let isSimulated = ProcessInfo.processInfo.environment["BARN_SIMULATE_MEM_GB"] != nil

    if memsize > 0 {
      let ramMB = memsize / (1024 * 1024)
      let ramGB = Double(ramMB) / 1024.0
      let suffix = isSimulated ? " (simulated)" : ""
      return String(format: "Memory: %.0f GB%@", ramGB, suffix)
    } else {
      return "Memory: Unknown"
    }
  }
}
