import Foundation
import Network
import OSLog

/// Withdraws network access when the Mac joins a different network.
///
/// `exposeToNetwork` is one global switch, but the decision behind it is
/// local: "people on *this* network may reach my server". A laptop carries
/// that switch onto every network it later joins -- café, hotel, coworking --
/// where the answer would have been no. Since the server has no authentication,
/// the setting silently means something different in each place.
///
/// So exposure is scoped to the network it was granted on: switching networks
/// turns it back off and says so, rather than quietly following the laptop.
/// Re-enabling on the new network is one click, and this time it's a decision.
@MainActor
final class NetworkExposureGuard {
  private let logger = Logger(subsystem: Logging.subsystem, category: "NetworkExposureGuard")
  private let monitor = NWPathMonitor()

  func start() {
    monitor.pathUpdateHandler = { [weak self] _ in
      // The ARP entry for a new gateway usually isn't populated the instant the
      // path changes, so let the link settle before fingerprinting it. A missed
      // check costs nothing -- the next path update, or the next launch, catches it.
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        MainActor.assumeIsolated { self?.check() }
      }
    }
    monitor.start(queue: DispatchQueue.global(qos: .utility))

    // Also check at launch: the laptop may have moved while the app wasn't
    // running, which no path update will ever tell us about.
    check()
  }

  /// Turns exposure off if the current network isn't the one it was granted on.
  private func check() {
    guard UserSettings.exposeToNetwork else { return }

    // A hand-set bind address (e.g. a Tailscale IP) is deliberately pinned to
    // an interface rather than to a physical network, and is reachable only
    // over that overlay -- moving between wifi networks doesn't widen it, so
    // there's nothing to withdraw.
    guard UserSettings.networkBindAddress == "0.0.0.0" else { return }

    guard let granted = UserSettings.exposeToNetworkFingerprint else {
      // Enabled before this existed, or with no default route at the time.
      // Adopt the current network rather than revoking a setting the user
      // never saw us scope.
      UserSettings.exposeToNetworkFingerprint = NetworkIdentity.currentFingerprint()
      return
    }

    // No identifiable network (wifi off, no gateway) isn't a new network --
    // it's no network. Leave the setting alone; nothing can reach the server
    // anyway.
    guard let current = NetworkIdentity.currentFingerprint() else { return }
    guard current != granted else { return }

    logger.notice("joined a different network -- turning network access off")
    UserSettings.exposeToNetwork = false
    NotificationCenter.default.post(
      name: .LBShowMenuHint, object: nil,
      userInfo: ["message": "Network access turned off — new network"])
  }
}
