import AppKit
import Combine
import Foundation
import Observation
import os.log

/// Manages the low-level details of downloading model files using URLSession.
@Observable
class ModelDownloader: NSObject, URLSessionDownloadDelegate {
  static let shared = ModelDownloader()

  // Track multi-file downloads per model id
  struct ActiveDownload {
    var progress: Progress
    var tasks: [Int: URLSessionDownloadTask]  // key: taskIdentifier
    var bytesWritten: [Int: Int64]  // per-task completed bytes
    var expectedBytes: [Int: Int64]  // per-task expected bytes (if known)
    var totalExpectedBytes: Int64  // aggregate expected (dynamic)
  }

  var activeDownloads: [String: ActiveDownload] = [:]
  var downloadUpdateTrigger: Int = 0

  private var urlSession: URLSession!
  private let logger = Logger(subsystem: "LlamaBarn", category: "ModelDownloader")

  private override init() {
    super.init()
    // Route delegate callbacks to the main queue to keep state access consistent
    urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
  }

  func getDownloadStatus(for model: ModelCatalogEntry) -> ModelStatus {
    if let download = activeDownloads[model.id] {
      return .downloading(download.progress)
    }
    return .available
  }

  /// Downloads all required files for a model
  func downloadModel(_ model: ModelCatalogEntry) throws {
    let filesToDownload = filesRequired(for: model)
    guard !filesToDownload.isEmpty else {
      return
    }

    guard ModelCatalog.isModelCompatible(model) else {
      let reason =
        ModelCatalog.incompatibilitySummary(model)
        ?? "isn't compatible with this Mac's memory."
      throw DownloadError.notCompatible(reason: reason)
    }

    // Before starting, ensure there's enough free disk space on the models volume.
    // Estimate remaining bytes needed as catalog total minus already-present files.
    let totalBytes = model.fileSize
    let existingBytes: Int64 = model.allLocalModelPaths.reduce(0) { sum, path in
      guard FileManager.default.fileExists(atPath: path),
        let attrs = try? FileManager.default.attributesOfItem(atPath: path),
        let size = (attrs[.size] as? NSNumber)?.int64Value
      else { return sum }
      return sum + size
    }
    let remainingBytes = max(totalBytes - existingBytes, 0)
    let modelsDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
    let available = DiskSpace.availableBytes(at: modelsDir)

    if available > 0 && remainingBytes > available {
      // Not enough space — throw an error.
      let needStr = DiskSpace.formatGB(remainingBytes)
      let haveStr = DiskSpace.formatGB(available)
      throw DownloadError.notEnoughDiskSpace(required: needStr, available: haveStr)
    }

    logger.info("Starting download for model: \(model.displayName)")

    // Create or reuse aggregate state for this model's downloads
    var aggregate =
      activeDownloads[model.id]
      ?? ActiveDownload(
        progress: Progress(totalUnitCount: 0),
        tasks: [:],
        bytesWritten: [:],
        expectedBytes: [:],
        totalExpectedBytes: 0
      )

    // Publish aggregate before starting tasks to avoid race with delegate callbacks
    activeDownloads[model.id] = aggregate

    for fileUrl in filesToDownload {
      let task = urlSession.downloadTask(with: fileUrl)
      task.taskDescription = model.id
      aggregate.tasks[task.taskIdentifier] = task
      aggregate.bytesWritten[task.taskIdentifier] = 0
      aggregate.expectedBytes[task.taskIdentifier] = 0
      activeDownloads[model.id] = aggregate
      task.resume()
    }
  }

  /// Cancels an ongoing download and removes it from tracking
  func cancelModelDownload(_ model: ModelCatalogEntry) {
    if let download = activeDownloads[model.id] {
      for (_, task) in download.tasks { task.cancel() }
      activeDownloads.removeValue(forKey: model.id)
    }
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  /// Determines which files need downloading for the given model
  private func filesRequired(for model: ModelCatalogEntry) -> [URL] {
    var files: [URL] = []

    // Main model file
    if !FileManager.default.fileExists(atPath: model.modelFilePath) {
      files.append(model.downloadUrl)
    }

    // Additional shards
    if let additional = model.additionalParts, !additional.isEmpty {
      let baseDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
      for url in additional {
        let path = baseDir.appendingPathComponent(url.lastPathComponent).path
        if !FileManager.default.fileExists(atPath: path) {
          files.append(url)
        }
      }
    }
    return files
  }

  // MARK: - URLSessionDownloadDelegate

  private func recalcProgress(for modelId: String) {
    guard var aggregate = activeDownloads[modelId] else { return }
    let totalBytes = aggregate.bytesWritten.values.reduce(0, +)
    let expected = aggregate.expectedBytes.values.reduce(0, +)
    if expected > 0 {
      aggregate.totalExpectedBytes = expected
    }
    // Ensure total never falls below completed to avoid Progress inconsistencies.
    let safeTotal = max(aggregate.totalExpectedBytes, totalBytes)
    aggregate.progress.totalUnitCount = safeTotal
    aggregate.progress.completedUnitCount = totalBytes
    activeDownloads[modelId] = aggregate
    downloadUpdateTrigger += 1
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let modelId = downloadTask.taskDescription,
      let model = ModelCatalog.entry(forId: modelId)
    else {
      return
    }

    if let httpResponse = downloadTask.response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      handleDownloadFailure(
        modelId: modelId,
        model: model,
        task: downloadTask,
        tempLocation: location,
        destinationURL: nil,
        reason: "HTTP \(httpResponse.statusCode)"
      )
      return
    }

    let fileManager = FileManager.default
    let baseDir = URL(fileURLWithPath: model.modelFilePath).deletingLastPathComponent()
    let filename =
      downloadTask.originalRequest?.url?.lastPathComponent
      ?? URL(fileURLWithPath: model.modelFilePath).lastPathComponent
    let destinationURL = baseDir.appendingPathComponent(filename)

    do {
      if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
      }
      try fileManager.moveItem(at: location, to: destinationURL)

      let fileSize =
        (try? FileManager.default.attributesOfItem(
          atPath: destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
      let tenMB: Int64 = 10 * 1_000_000
      let minAcceptableBytes = min(model.fileSize / 2, tenMB)
      let minThreshold = max(Int64(1_000_000), minAcceptableBytes)
      if fileSize <= minThreshold {
        try? fileManager.removeItem(at: destinationURL)
        handleDownloadFailure(
          modelId: modelId,
          model: model,
          task: downloadTask,
          tempLocation: nil,
          destinationURL: destinationURL,
          reason: "file too small (\(fileSize) B)"
        )
        return
      }

      if var aggregate = self.activeDownloads[modelId] {
        aggregate.tasks.removeValue(forKey: downloadTask.taskIdentifier)
        aggregate.bytesWritten[downloadTask.taskIdentifier] = fileSize
        if (aggregate.expectedBytes[downloadTask.taskIdentifier] ?? 0) <= 0 {
          aggregate.expectedBytes[downloadTask.taskIdentifier] = fileSize
        }
        self.activeDownloads[modelId] = aggregate
        self.recalcProgress(for: modelId)

        if aggregate.tasks.isEmpty {
          self.logger.info("All downloads completed for model: \(model.displayName)")
          self.activeDownloads.removeValue(forKey: modelId)
          // Notify ModelManager that a model has finished downloading.
          NotificationCenter.default.post(
            name: .LBModelDownloadFinished,
            object: self,
            userInfo: ["model": model]
          )
        }
      } else {
        // This case should not be hit if the download is tracked properly,
        // but if it is, ensure we notify for a refresh.
        NotificationCenter.default.post(
          name: .LBModelDownloadFinished, object: self, userInfo: ["model": model])
      }
    } catch {
      logger.error("Error moving downloaded file: \(error.localizedDescription)")
      if var aggregate = self.activeDownloads[modelId] {
        aggregate.tasks.removeValue(forKey: downloadTask.taskIdentifier)
        self.activeDownloads[modelId] = aggregate
        self.recalcProgress(for: modelId)
        if aggregate.tasks.isEmpty { self.activeDownloads.removeValue(forKey: modelId) }
      }
    }
  }

  private func handleDownloadFailure(
    modelId: String,
    model: ModelCatalogEntry,
    task: URLSessionDownloadTask,
    tempLocation: URL?,
    destinationURL: URL?,
    reason: String
  ) {
    let fileManager = FileManager.default
    if let tempLocation {
      try? fileManager.removeItem(at: tempLocation)
    }
    if let destinationURL, fileManager.fileExists(atPath: destinationURL.path) {
      try? fileManager.removeItem(at: destinationURL)
    }

    logger.error("Model download failed (\(reason)) for model: \(model.displayName)")

    if var aggregate = self.activeDownloads[modelId] {
      for (id, otherTask) in aggregate.tasks where id != task.taskIdentifier {
        otherTask.cancel()
      }
      aggregate.tasks.removeAll()
      aggregate.bytesWritten.removeAll()
      aggregate.expectedBytes.removeAll()
      self.activeDownloads.removeValue(forKey: modelId)
    }

    downloadUpdateTrigger += 1
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let modelId = downloadTask.taskDescription,
      var download = self.activeDownloads[modelId]
    else {
      return
    }
    download.bytesWritten[downloadTask.taskIdentifier] = totalBytesWritten
    let total = download.bytesWritten.values.reduce(0, +)
    if totalBytesExpectedToWrite > 0 {
      download.expectedBytes[downloadTask.taskIdentifier] = totalBytesExpectedToWrite
    }
    let expectedTotal = download.expectedBytes.values.reduce(0, +)
    if expectedTotal > 0 {
      download.totalExpectedBytes = expectedTotal
    }
    let safeTotal = max(download.totalExpectedBytes, total)
    download.progress.totalUnitCount = safeTotal
    download.progress.completedUnitCount = total
    self.activeDownloads[modelId] = download
    self.downloadUpdateTrigger += 1
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let modelId = task.taskDescription else {
      return
    }

    if let error = error {
      logger.error("Model download failed: \(error.localizedDescription)")
      if var aggregate = self.activeDownloads[modelId] {
        aggregate.tasks.removeValue(forKey: task.taskIdentifier)
        self.activeDownloads[modelId] = aggregate
        self.recalcProgress(for: modelId)
        if aggregate.tasks.isEmpty {
          self.activeDownloads.removeValue(forKey: modelId)
        }
      }
    }
  }
}
