//
//  MusicStrip.swift
//
//  The music part of the floating bar (claude-spinner-playback slice 3): cover,
//  title, "artist -- album", transport controls and a progress line you can drag
//  to seek. It is its own row under the reply row, so the session keeps the main
//  line and neither name has to give up width for the other, and it draws nothing
//  at all while Music is not open.
//

import SwiftUI

struct MusicStrip: View {
    @ObservedObject private var music = NowPlaying.shared

    var body: some View {
        switch music.status {
        case .notRunning, .idle:
            EmptyView()
        case .denied:
            Notice(kind: .warning, text: "Spinner can\u{2019}t read Music. Allow it under Privacy & Security, Automation.",
                   size: 10) {
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        case .unreadable:
            Notice(kind: .warning, text: "Music isn\u{2019}t answering, so what it is playing is not shown.", size: 10)
        case .track(let track):
            row(track)
        }
    }

    /// Opaque, like the reply field: Music's own player can be as transparent as it
    /// likes because it never carries text over arbitrary content; this one does.
    private func row(_ track: NowPlayingTrack) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                art
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.ui(11)).fontWeight(.semibold).lineLimit(1)
                    Text(track.subtitle).font(.ui(10)).foregroundStyle(Color.label).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    ForEach([MusicControl.previous, .playPause, .next]) { kind in control(kind, track: track) }
                }
            }
            SeekLine(progress: track.progress, position: track.position, duration: track.duration) { fraction in
                music.seek(toFraction: fraction)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private var art: some View {
        if let image = music.artwork {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.secondary.opacity(0.2))
                .frame(width: 28, height: 28)
                .overlay { Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(Color.label) }
                .accessibilityHidden(true)
        }
    }

    private func control(_ control: MusicControl, track: NowPlayingTrack) -> some View {
        let reason = music.unavailableReason(control)
        let symbol = control == .playPause ? (track.isPlaying ? "pause.fill" : "play.fill") : control.symbol
        return Button { music.perform(control) } label: {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .opacity(reason == nil ? 1 : 0.4)
        .help(reason ?? (control == .playPause ? (track.isPlaying ? "Pause" : "Play") : control.title))
        .accessibilityLabel(control == .playPause ? (track.isPlaying ? "Pause" : "Play") : control.title)
    }
}

/// A thin progress line that is also the seek control: drag or click along it and
/// Music jumps on release. Adjustable for VoiceOver in ten-second steps.
private struct SeekLine: View {
    let progress: Double?
    let position: Double
    let duration: Double
    let seek: (Double) -> Void

    @State private var dragging: Double?

    private var shown: Double { dragging ?? progress ?? 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule().fill(Color.primary.opacity(0.75)).frame(width: max(0, geo.size.width * shown))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragging = fraction($0.location.x, in: geo.size.width) }
                .onEnded { value in
                    seek(fraction(value.location.x, in: geo.size.width))
                    dragging = nil
                })
        }
        .frame(height: 4)
        .padding(.vertical, 4)
        .disabled(progress == nil)
        // Keyboard: focusable, and the arrows seek ten seconds, as VoiceOver's
        // adjustable action does.
        .focusable(progress != nil)
        .onKeyPress(.leftArrow) { nudge(-1) }
        .onKeyPress(.rightArrow) { nudge(1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Track position")
        .accessibilityValue(progress == nil ? "unknown" : "\(Int(position)) of \(Int(duration)) seconds")
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = 10.0 / duration
            switch direction {
            case .increment: seek(min(1, (progress ?? 0) + step))
            case .decrement: seek(max(0, (progress ?? 0) - step))
            @unknown default: break
            }
        }
    }

    private func nudge(_ direction: Double) -> KeyPress.Result {
        guard duration > 0 else { return .ignored }
        seek(min(1, max(0, (progress ?? 0) + direction * 10 / duration)))
        return .handled
    }

    private func fraction(_ x: CGFloat, in width: CGFloat) -> Double {
        width > 0 ? min(1, max(0, Double(x / width))) : 0
    }
}
