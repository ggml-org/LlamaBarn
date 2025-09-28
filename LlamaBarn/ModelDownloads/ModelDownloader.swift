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
    struct TaskState {
      let task: URLSessionDownloadTask
      var bytesWritten: Int64
      var expectedBytes: Int64
    }

    var progress: Progress
    var tasks: [Int: TaskState]
    var completedBytes: Int64 = 0
    var completedExpectedBytes: Int64 = 0

    mutating func addTask(_ task: URLSessionDownloadTask) {
      tasks[task.taskIdentifier] = TaskState(
        task: task,
        bytesWritten: 0,
        expectedBytes: 0
      )
    }

    mutating func updateTask(
      identifier: Int,
      bytesWritten: Int64,
      expectedBytes: Int64?
    ) {
      guard var state = tasks[identifier] else { return }
      state.bytesWritten = bytesWritten
      if let expectedBytes, expectedBytes > 0 {
        state.expectedBytes = expectedBytes
      }
      tasks[identifier] = state
    }

    mutating func removeTask(with identifier: Int) -> TaskState? {
      return tasks.removeValue(forKey: identifier)
    }

    mutating func cancelAllTasks() {
      tasks.values.forEach { $0.task.cancel() }
      tasks.removeAll()
      completedBytes = 0
      completedExpectedBytes = 0
    }

    mutating func refreshProgress() {
      let activeWritten = tasks.values.reduce(Int64(0)) { $0 + $1.bytesWritten }
      let activeExpected = tasks.values.reduce(Int64(0)) {
        let value = $1.expectedBytes
        return $0 + (value > 0 ? value : 0)
      }
      let totalCompleted = completedBytes + activeWritten
      let totalExpected = max(completedExpectedBytes + activeExpected, totalCompleted)
      progress.totalUnitCount = totalExpected
      progress.completedUnitCount = totalCompleted
    }

    var isEmpty: Bool { tasks.isEmpty }
  }

  var activeDownloads: [String: ActiveDownload] = [:]

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
      ?? ActiveDownload(progress: Progress(totalUnitCount: 0), tasks: [:])

    // Publish aggregate before starting tasks to avoid race with delegate callbacks
    activeDownloads[model.id] = aggregate

    for fileUrl in filesToDownload {
      let task = urlSession.downloadTask(with: fileUrl)
      task.taskDescription = model.id
      aggregate.addTask(task)
      activeDownloads[model.id] = aggregate
      task.resume()
    }
  }

  /// Cancels an ongoing download and removes it from tracking
  func cancelModelDownload(_ model: ModelCatalogEntry) {
    if let download = activeDownloads[model.id] {
      var mutable = download
      mutable.cancelAllTasks()
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
        if var state = aggregate.removeTask(with: downloadTask.taskIdentifier) {
          state.bytesWritten = fileSize
          if state.expectedBytes <= 0 {
            state.expectedBytes = fileSize
          }
          aggregate.completedBytes += state.bytesWritten
          let expectedContribution =
            state.expectedBytes > 0
            ? state.expectedBytes
            : state.bytesWritten
          aggregate.completedExpectedBytes += expectedContribution
        }
        aggregate.refreshProgress()

        if aggregate.isEmpty {
          self.logger.info("All downloads completed for model: \(model.displayName)")
          self.activeDownloads.removeValue(forKey: modelId)
          NotificationCenter.default.post(
            name: .LBModelDownloadFinished,
            object: self,
            userInfo: ["model": model]
          )
        } else {
          self.activeDownloads[modelId] = aggregate
          NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
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
        _ = aggregate.removeTask(with: downloadTask.taskIdentifier)
        aggregate.refreshProgress()
        if aggregate.isEmpty {
          self.activeDownloads.removeValue(forKey: modelId)
        } else {
          self.activeDownloads[modelId] = aggregate
        }
        NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
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
      aggregate.cancelAllTasks()
      self.activeDownloads.removeValue(forKey: modelId)
    }

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
    download.updateTask(
      identifier: downloadTask.taskIdentifier,
      bytesWritten: totalBytesWritten,
      expectedBytes: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
    )
    download.refreshProgress()
    self.activeDownloads[modelId] = download
    NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let modelId = task.taskDescription else {
      return
    }

    if let error = error {
      logger.error("Model download failed: \(error.localizedDescription)")
      if var aggregate = self.activeDownloads[modelId] {
        _ = aggregate.removeTask(with: task.taskIdentifier)
        aggregate.refreshProgress()
        if aggregate.isEmpty {
          self.activeDownloads.removeValue(forKey: modelId)
        } else {
          self.activeDownloads[modelId] = aggregate
          NotificationCenter.default.post(name: .LBModelDownloadsDidChange, object: self)
        }
      }
    }
  }
}
