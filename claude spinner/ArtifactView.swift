import AppKit
import Combine
import SwiftUI
import WebKit

/// A published claude.ai artifact, live, inside the app.
///
/// Artifacts are private to the signed-in account (the URL answers 403 without a
/// session), so every web view here shares the default, persistent data store:
/// sign in once in any of them and the cookie survives relaunches and pop-outs.
enum ArtifactWeb {
    /// Safari's user agent. claude.ai's sign-in treats the bare WKWebView agent
    /// as an embedded browser and may refuse it.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/27.0 Safari/605.1.15"

    static func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = userAgent
        view.allowsBackForwardNavigationGestures = true
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
}

struct ArtifactWebView: NSViewRepresentable {
    let url: URL
    /// Below 1 the page lays out wider than the view and shrinks to fit, which
    /// is what makes a small card read as a preview of the whole page.
    var zoom: CGFloat = 1

    func makeNSView(context: Context) -> WKWebView {
        let view = ArtifactWeb.makeWebView()
        view.pageZoom = zoom
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.pageZoom != zoom { view.pageZoom = zoom }
        if view.url == nil { view.load(URLRequest(url: url)) }
    }
}

/// Floating mini windows, one per artifact URL.
@MainActor
final class ArtifactPopouts: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ArtifactPopouts()

    /// URLs with a window open, so the inline copy can step aside instead of
    /// running a second live page beside it.
    @Published private(set) var open: Set<String> = []
    private var windows: [String: NSWindow] = [:]

    func show(title: String, url: URL) {
        let key = url.absoluteString
        if let window = windows[key] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let web = ArtifactWeb.makeWebView()
        web.load(URLRequest(url: url))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 680),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = title
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = web
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        // Per artifact, so each mini window comes back where it was left.
        if !panel.setFrameAutosaveName("Artifact " + key) || panel.frame.origin == .zero {
            panel.center()
        }
        windows[key] = panel
        open.insert(key)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let key = windows.first(where: { $0.value === window })?.key else { return }
        windows[key] = nil
        open.remove(key)
    }
}

/// An artifact as a dashboard card: a small live preview by default, which
/// expands in place to a full-width working page, or pops out to its own window.
struct ArtifactCard: View {
    let artifact: ProjectArtifact
    @ObservedObject private var popouts = ArtifactPopouts.shared
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                CardTitle(artifact.title).lineLimit(1)
                Spacer(minLength: 4)
                if let url = URL(string: artifact.url) {
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        Label(expanded ? "Collapse" : "Expand",
                              systemImage: expanded ? "arrow.down.right.and.arrow.up.left"
                                                    : "arrow.up.left.and.arrow.down.right")
                    }
                    Button { popouts.show(title: artifact.title, url: url) } label: {
                        Label("Pop out", systemImage: "macwindow.on.rectangle")
                    }
                    .help("Open in a floating mini window")
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("Browser", systemImage: "safari")
                    }
                    .help(artifact.url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.ui(11))

            if let url = URL(string: artifact.url) {
                if popouts.open.contains(url.absoluteString) {
                    Text("Open in its own window.")
                        .font(.ui(11)).foregroundStyle(Color.label)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else if expanded {
                    ArtifactWebView(url: url)
                        .frame(minHeight: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    // A look, not a workspace: the page is shrunk and clicks go to
                    // Expand, so scrolling the dashboard never lands inside it.
                    ArtifactWebView(url: url, zoom: 0.5)
                        .frame(height: 200)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.clear).contentShape(Rectangle())
                                .onTapGesture { withAnimation(.snappy) { expanded = true } }
                        }
                        .help("Expand")
                }
            }
        }
        .detailCard()
        .tileSpan(expanded ? 3 : 1)
    }
}
