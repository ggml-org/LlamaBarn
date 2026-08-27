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

  /// Withdraws a Tailscale bind whose address this Mac no longer holds.
  ///
  /// The stored address goes stale when the tailnet changes -- switching
  /// between a work and a personal account is enough. It's tempting to just
  /// re-point at the new address, since the user asked for "Tailscale" rather
  /// than for a number. But a different tailnet is a different set of people:
  /// following the switch would move the server from your own devices onto,
  /// say, your employer's network without asking. That's the same consent that
  /// changing wifi breaks, so it gets the same answer -- turn it off, say so,
  /// and let re-enabling be a decision.
  ///
  /// The server has already fallen back to loopback by itself
  /// (`effectiveBindAddress`); this is what stops the setting from going on
  /// claiming otherwise.
  private func withdrawStaleTailscaleBind() {
    guard case .tailscale = UserSettings.networkAccess,
      let stored = UserSettings.networkBindAddress,
      !TailscaleInterface.isCurrentAddress(stored)
    else { return }

    logger.notice("stored Tailscale address is no longer held -- turning network access off")
    UserSettings.setNetworkAccess(.off)
    NotificationCenter.default.post(
      name: .LBShowMenuHint, object: nil,
      userInfo: ["message": "Network access turned off — Tailscale changed"])
  }

  /// Turns exposure off if the current network isn't the one it was granted on.
  private func check() {
    withdrawStaleTailscaleBind()

    // Only `.localNetwork` is scoped to a place. A Tailscale (or other
    // hand-set) bind follows an interface, not a network: it's reachable over
    // that overlay wherever you are and invisible on the local wifi, so
    // changing networks neither widens it nor makes it mean something else.
    guard UserSettings.networkAccess == .localNetwork else { return }

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
    UserSettings.setNetworkAccess(.off)
    NotificationCenter.default.post(
      name: .LBShowMenuHint, object: nil,
      userInfo: ["message": "Network access turned off — new network"])
  }
}
