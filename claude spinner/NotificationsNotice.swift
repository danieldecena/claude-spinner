import SwiftUI
import AppKit

/// "Notifications are off" and the one control that can fix it.
///
/// Extracted for the same reason `SetupBanner` was: it lived only inside
/// `MenuContentView`, so under `surface = window` -- where the app has no status
/// item and never opens the panel -- the app had no readout of the one state
/// that makes every banner a no-op. Denied authorization is invisible from the
/// API side (`add()` reports no error either way), so a surface that cannot say
/// it cannot be trusted to be silent for the right reason.
struct NotificationsNotice: View {
    @ObservedObject private var asks = AskInbox.shared

    var body: some View {
        // nil is "not read yet", which is not the same as allowed -- neither
        // draws, but only `false` is a finding.
        if asks.notificationsAllowed == false {
            HStack(spacing: 6) {
                Text("Notifications are off — questions can't reach you.")
                    .font(.claudeMono(11)).foregroundStyle(Color.usageTint(95))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Open Settings") {
                    if let url = URL(string:
                        "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.claudeMono(11))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
    }
}
