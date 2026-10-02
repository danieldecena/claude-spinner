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
    /// Given a picture of the page once it has drawn, for a caller that wants
    /// the picture and not the page.
    var onSnapshot: ((NSImage) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = ArtifactWeb.makeWebView()
        view.pageZoom = zoom
        context.coordinator.onSnapshot = onSnapshot
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onSnapshot = onSnapshot
        if view.pageZoom != zoom { view.pageZoom = zoom }
        if view.url == nil { view.load(URLRequest(url: url)) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSnapshot: ((NSImage) -> Void)?
        /// The load finishing is not the page drawing: claude.ai fetches the
        /// artifact and fills its frame afterwards.
        static let settle: Duration = .seconds(5)

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard onSnapshot != nil else { return }
            Task {
                try? await Task.sleep(for: Self.settle)
                // A sign-in redirect finishes more than once; the first picture
                // takes the view off screen, and a second would be of nothing.
                guard webView.window != nil,
                      let image = try? await webView.takeSnapshot(configuration: nil) else { return }
                onSnapshot?(image)
            }
        }
    }
}

/// Pictures of artifact pages for the dashboard cards. A live page behind each
/// card cost about 90 MB apiece (measured 2026-10-02), for a quarter-size
/// picture nobody can click into.
@MainActor
final class ArtifactThumbnails: ObservableObject {
    static let shared = ArtifactThumbnails()

    /// Per appearance: the page draws itself light or dark, and a light picture
    /// on a dark panel reads as a fault.
    @Published private(set) var images: [String: [ColorScheme: NSImage]] = [:]

    func keep(_ image: NSImage, of url: URL, in scheme: ColorScheme) {
        images[url.absoluteString, default: [:]][scheme] = image
    }

    /// The page is about to be worked in, so the picture is about to be old.
    func forget(_ url: URL) {
        images[url.absoluteString] = nil
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
                            // No full-size content: the page has a title of its own in
                            // its top-left corner, and the traffic lights sat on it.
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
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
    @ObservedObject private var thumbnails = ArtifactThumbnails.shared
    @Environment(\.colorScheme) private var colorScheme

    private var host: String { URL(string: artifact.url)?.host() ?? "artifact" }
    private static let thumbnailHeight: CGFloat = 72
    private static let thumbnailScale: CGFloat = 0.25

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
                    ArtifactIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Expand") {
                        expand(url)
                    }
                    ArtifactIconButton(symbol: "macwindow.on.rectangle", help: "Pop out to a floating window") {
                        thumbnails.forget(url)
                        popouts.show(title: artifact.title, url: url)
                    }
                    ArtifactIconButton(symbol: "safari", help: "Open in browser") { NSWorkspace.shared.open(url) }
                }
            }

            if let url = URL(string: artifact.url) {
                if popouts.open.contains(url.absoluteString) {
                    Label("Open in its own window", systemImage: "macwindow.on.rectangle")
                        .font(.ui(11)).foregroundStyle(Color.label)
                        .frame(maxWidth: .infinity, minHeight: Self.thumbnailHeight)
                } else {
                    // A thumbnail, not a workspace: the page is laid out in a
                    // window four times the box and the picture drawn at a
                    // quarter, so it shows the page's shape. Page zoom did not
                    // do this: the artifact's own frame kept its type size, and
                    // the box held a toolbar, two scrollbars and one line of
                    // text. Clicks go to Expand so scrolling the dashboard never
                    // lands inside it. The page is only there until it has
                    // drawn: its picture replaces it and the web view goes.
                    Group {
                        if let image = thumbnails.images[url.absoluteString]?[colorScheme] {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: Self.thumbnailHeight, alignment: .topLeading)
                                .clipped()
                        } else {
                            GeometryReader { geo in
                                ArtifactWebView(url: url) { thumbnails.keep($0, of: url, in: colorScheme) }
                                    .frame(width: geo.size.width / Self.thumbnailScale,
                                           height: Self.thumbnailHeight / Self.thumbnailScale)
                                    .scaleEffect(Self.thumbnailScale, anchor: .topLeading)
                            }
                        }
                    }
                        .frame(height: Self.thumbnailHeight)
                        .allowsHitTesting(false)
                        // A picture: without this the whole page, every heading
                        // and control in it, was read out from inside the card
                        // with nothing in it that could be operated.
                        .accessibilityHidden(true)
                        .mask {
                            LinearGradient(stops: [.init(color: .black, location: 0.85),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.label.opacity(0.15))
                                .contentShape(Rectangle())
                                .onTapGesture { expand(url) }
                                .accessibilityHidden(true)
                        }
                        .help("Expand")
                }
            }
        }
        .detailCard()
    }

    private func expand(_ url: URL) {
        thumbnails.forget(url)
        onExpand()
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
