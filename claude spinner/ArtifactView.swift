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

/// An artifact as a dashboard card: a thumbnail of the live page, which expands
/// to fill the whole detail pane (`onExpand`) or pops out to its own window.
/// Half the width and half the height of a grid tile, so a row of them sits
/// above the dashboard without pushing it down the page.
struct ArtifactCard: View {
    let artifact: ProjectArtifact
    let onExpand: () -> Void
    @ObservedObject private var popouts = ArtifactPopouts.shared

    private var host: String { URL(string: artifact.url)?.host() ?? "artifact" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.attention)
                    .frame(width: 22, height: 22)
                    .background(Color.attention.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(artifact.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(host).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            // The summary is on hover: two lines of it do not fit a card this
            // narrow, and half a sentence said less than none.
            .help(artifact.summary ?? artifact.title)
            // Own row: beside the title, three buttons left a one-column tile
            // about 40pt for the name, which drew as "C".
            if let url = URL(string: artifact.url) {
                HStack(spacing: 4) {
                    ArtifactIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Expand",
                                       action: onExpand)
                    ArtifactIconButton(symbol: "macwindow.on.rectangle", help: "Pop out to a floating window") {
                        popouts.show(title: artifact.title, url: url)
                    }
                    ArtifactIconButton(symbol: "safari", help: "Open in browser") { NSWorkspace.shared.open(url) }
                }
            }

            if let url = URL(string: artifact.url) {
                if popouts.open.contains(url.absoluteString) {
                    Label("Open in its own window", systemImage: "macwindow.on.rectangle")
                        .font(.ui(11)).foregroundStyle(Color.label)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    // A thumbnail, not a workspace: the page is scaled to its
                    // shape rather than its type, faded at the bottom to say
                    // there is more, and clicks go to Expand so scrolling the
                    // dashboard never lands inside it.
                    ArtifactWebView(url: url, zoom: 0.375)
                        .frame(height: 72)
                        .allowsHitTesting(false)
                        .mask {
                            LinearGradient(stops: [.init(color: .black, location: 0.7),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.label.opacity(0.15))
                                .contentShape(Rectangle())
                                .onTapGesture(perform: onExpand)
                        }
                        .help("Expand")
                }
            }
        }
        .detailCard()
    }
}

private struct ArtifactIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 26, height: 22)
        }
        .buttonStyle(.bordered)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One artifact filling the detail pane: the working page at full size, with a
/// way back to the project dashboard it was opened from.
struct ArtifactFullView: View {
    let artifact: ProjectArtifact
    let backTitle: String
    let onClose: () -> Void
    @ObservedObject private var popouts = ArtifactPopouts.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onClose) {
                    Label(backTitle, systemImage: "chevron.left").font(.ui(12))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Text(artifact.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let url = URL(string: artifact.url) {
                    ArtifactIconButton(symbol: "macwindow.on.rectangle", help: "Pop out to a floating window") {
                        popouts.show(title: artifact.title, url: url)
                        onClose()
                    }
                    ArtifactIconButton(symbol: "safari", help: "Open in browser") { NSWorkspace.shared.open(url) }
                }
            }
            if let url = URL(string: artifact.url) {
                ArtifactWebView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
