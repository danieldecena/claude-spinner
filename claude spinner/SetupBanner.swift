import SwiftUI

/// The "hooks aren't installed" prompt and its one-click install.
///
/// Extracted so both surfaces show it. It lived only inside `MenuContentView`,
/// which meant that under `surface = window` -- where the app has no status
/// item at all -- the only control that installs the hooks was unreachable.
/// The answer hooks sat in the repo, wired into `SetupInstaller`, never once
/// run, and permission prompts arrived with nothing to press.
struct SetupBanner: View {
    @ObservedObject var feed: FeedWatcher
    @ObservedObject var install: InstallState
    /// The panel draws its own heading and sits in a narrow column; the window
    /// has room for the sentence beside the button.
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Setup needed", systemImage: NoticeKind.warning.symbol)
                .font(.claudeMono(compact ? 13 : 11)).fontWeight(.semibold)
                .foregroundStyle(NoticeKind.warning.tint)
            Text(explanation)
                .font(.claudeMono(compact ? 11 : 10)).foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = install.message {
                Notice(message, size: compact ? 11 : 10)
            }
            Button(install.installing ? "Installing…" : "Install hooks") { run() }
                .font(.claudeMono(11))
                .disabled(install.installing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two different faults share this banner, and saying the wrong one sends
    /// you looking in the wrong place: with no feed at all the panel is empty,
    /// whereas with `emit.sh` alone the rows appear and only the answering is
    /// missing -- which reads as the buttons being broken rather than absent.
    private var explanation: String {
        feed.sessions.isEmpty
            ? "The feed hooks aren't installed, so no sessions can show."
            : "The answer hooks aren't installed, so permission prompts and questions arrive with nothing to press."
    }

    private func run() {
        install.installing = true
        install.message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SetupInstaller.install()
            DispatchQueue.main.async {
                install.installing = false
                switch result {
                case .success:
                    feed.refreshSetupState()
                    // Claude Code reads hooks once, at session start. Saying
                    // "installed" without this reads as "working now", and the
                    // session in front of you would still have no buttons.
                    install.message = .init(kind: .info, text: "Installed. Sessions already running keep their old hooks until you restart them.")
                case .failure(let error):
                    install.message = .init(kind: .error, text: "Couldn't install: \(error.localizedDescription)")
                }
            }
        }
    }
}
