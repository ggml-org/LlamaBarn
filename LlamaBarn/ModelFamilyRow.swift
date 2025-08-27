import AppKit
import SwiftUI

struct ModelFamilyRow: View {
  let family: String
  let models: [ModelCatalogEntry]
  let icon: String
  @Environment(ModelManager.self) var modelManager
  @State private var isHovered = false

  // Check if any model in this family is compatible with system memory
  private var hasCompatibleModels: Bool {
    models.contains { ModelCatalog.isModelCompatible($0) }
  }

  var body: some View {
    Menu {
      ForEach(models.sorted { compareModelsBySize($0, $1) }, id: \.id) { model in
        ModelMenuItem(model: model)
      }
    } label: {
      HStack(alignment: .center, spacing: 4) {
        // Model brand logo positioned consistently for visual alignment
        Image(icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 18, height: 18)
          .padding(.trailing, 4)
          .opacity(0.9)

        // Family name
        VStack(alignment: .leading, spacing: 4) {
          Text(family)
            .foregroundColor(hasCompatibleModels ? .primary : .primary.opacity(0.3))

          Text("\(models.count) models")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(hasCompatibleModels ? .secondary : .primary.opacity(0.3))
        }

        Spacer()

        // Memory warning for incompatible families
        if !hasCompatibleModels {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 12))
            .foregroundColor(.orange)
        }

        // Menu indicator
        Image(systemName: "chevron.right")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .frame(width: 32, height: 32)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 8)
      .background(
        isHovered && hasCompatibleModels
          ? Color.primary.opacity(0.05) : Color.clear
      )
      .cornerRadius(6)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .onHover { hovering in
        isHovered = hovering
      }
    }
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
  }

  // Compare models by size (file size first, then parameters as tiebreaker)
  private func compareModelsBySize(_ lhs: ModelCatalogEntry, _ rhs: ModelCatalogEntry) -> Bool {
    if lhs.fileSizeMB != rhs.fileSizeMB {
      return lhs.fileSizeMB < rhs.fileSizeMB
    }
    return lhs.sizeInBillions < rhs.sizeInBillions
  }
}

struct ModelMenuItem: View {
  let model: ModelCatalogEntry
  @Environment(ModelManager.self) var modelManager

  // Check if this model is compatible with system memory
  private var isModelCompatible: Bool {
    ModelCatalog.isModelCompatible(model)
  }

  // Get the current status of this model
  private var modelStatus: ModelStatus {
    modelManager.getModelStatus(model)
  }

  var body: some View {
    Button(action: {
      handleAction()
    }) {
      HStack {
        // Show download status indicator
        switch modelStatus {
        case .downloaded:
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.green)
        case .downloading:
          Image(systemName: "arrow.down.circle")
            .font(.system(size: 10))
            .foregroundColor(.blue)
        case .available:
          Image(systemName: "arrow.down.circle")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }

        // Single line format that works better in menus
        Text("\(model.variant) (\(model.quantization)) - \(model.totalSize)")
          .foregroundColor(isModelCompatible ? .primary : .primary.opacity(0.5))

        // Show capability icons inline
        if model.supportsVision {
          Image(systemName: "eyeglasses")
            .font(.system(size: 8))
            .help("Vision")
        }

        if model.supportsAudio {
          Image(systemName: "waveform")
            .font(.system(size: 8))
            .help("Audio")
        }

        Spacer()

        // Memory warning for incompatible models
        if !isModelCompatible {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 10))
            .foregroundColor(.orange)
        }
      }
    }
    .disabled(modelStatus == .downloaded || (!isModelCompatible && modelStatus == .available))
  }

  private func handleAction() {
    switch modelStatus {
    case .available:
      if isModelCompatible {
        modelManager.downloadModel(model)
      }
    case .downloading:
      modelManager.cancelModelDownload(model)
    case .downloaded:
      // Downloaded models are disabled, so this shouldn't be called
      break
    }
  }
}
