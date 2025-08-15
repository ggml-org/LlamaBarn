import SwiftUI

struct ServerStatusView: View {
  let llamaServer: LlamaServer
  @Binding var isHovered: Bool
  let onTap: () -> Void

  private var isServerActive: Bool {
    llamaServer.state == .running
  }

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "server.rack")
        .font(.system(size: 14))
        .frame(width: 18, height: 18)
        .padding(.trailing, 4)

      if isServerActive {
        Text("Running on ")
          .font(.system(size: 14))
          + Text("localhost:2276")
          .font(.system(size: 14))
          .foregroundColor(.blue)
      } else {
        Text("Server not running")
          .font(.system(size: 14))
      }

      Spacer()

      Image(systemName: "link")
        .font(.system(size: 14))
        .frame(width: 32, height: 16)
    }
    .foregroundColor(isServerActive ? .primary : .secondary)
    .padding(.vertical, 8)
    .padding(.horizontal, 8)
    .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
    .cornerRadius(6)
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
    .onHover { isHovered = isServerActive ? $0 : false }
    .onTapGesture(perform: onTap)
    .disabled(!isServerActive)
  }
}
