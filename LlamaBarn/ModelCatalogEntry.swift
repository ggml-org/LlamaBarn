import Foundation

/// Represents a complete AI model configuration with metadata and file locations
struct ModelCatalogEntry: Identifiable, Codable {
  let id: String  // Unique identifier for the model
  let family: String  // Model family name (e.g., "Qwen 3", "Gemma 3n")
  let variant: String  // Size/variant identifier (e.g., "8B", "E4B")
  let sizeInBillions: Double  // Number of parameters in billions
  let releaseDate: Date  // Model release date
  let supportsVision: Bool  // Can process images/visual input
  let supportsAudio: Bool  // Can process audio input
  let supportsTools: Bool  // Supports function calling/tools
  let contextLength: Int  // Maximum context length in tokens
  let fileSizeMB: Int  // File size for progress tracking and display
  let downloadUrl: URL  // Remote download URL
  let visionFile: URL?  // Optional multimodal projection file for vision
  let serverArgs: [String]  // Additional command line arguments for llama-server
  let icon: String  // Asset name for the model's brand logo
  let quantization: String  // Quantization method (e.g., "Q4_K_M", "Q8_0")

  /// Display name combining family and variant
  var displayName: String {
    "\(family) \(variant)"
  }

  /// Total size including all model files
  var totalSize: String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB]
    formatter.countStyle = .decimal
    let bytes = Int64(fileSizeMB * 1_000_000)
    return formatter.string(fromByteCount: bytes)
  }

  /// Simplified quantization display (e.g., "Q4" from "Q4_K_M")
  var simplifiedQuantization: String {
    String(quantization.prefix(2))
  }

  /// Check if all required files exist locally
  var isDownloaded: Bool {
    let modelFileExists = FileManager.default.fileExists(atPath: modelFilePath)
    let visionFileExists: Bool
    if let visionPath = visionFilePath {
      visionFileExists = FileManager.default.fileExists(atPath: visionPath)
    } else {
      visionFileExists = true  // No vision file required
    }
    return modelFileExists && visionFileExists
  }

  /// The local file system path where the model file will be stored
  var modelFilePath: String {
    Self.getModelStorageDirectory().appendingPathComponent(downloadUrl.lastPathComponent).path
  }

  /// The local file system path where the vision file will be stored
  var visionFilePath: String? {
    guard let visionFile = visionFile else { return nil }
    return Self.getModelStorageDirectory().appendingPathComponent(visionFile.lastPathComponent).path
  }

  /// Returns the directory where AI models are stored, creating it if necessary
  private static func getModelStorageDirectory() -> URL {
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    let modelsDirectory = homeDirectory.appendingPathComponent(".llamabarn", isDirectory: true)

    if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
      do {
        try FileManager.default.createDirectory(
          at: modelsDirectory, withIntermediateDirectories: true)
      } catch {
        print("Error creating ~/.llamabarn directory: \(error)")
      }
    }

    return modelsDirectory
  }
}
