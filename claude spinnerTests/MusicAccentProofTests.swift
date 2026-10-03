//
//  MusicAccentProofTests.swift
//  claude spinnerTests
//
//  Slice 1 of claude-spinner-music: decide Music red against real pixels. The
//  tokens are read back out of the running colour definitions, never copied, so
//  the measurements cannot drift from what the app draws.
//

import AppKit
import SwiftUI
import XCTest
@testable import claude_spinner

@MainActor
final class MusicAccentProofTests: XCTestCase {
    typealias RGB = (r: Double, g: Double, b: Double)

    /// A Color's sRGB triple under one appearance.
    private func resolve(_ color: Color, dark: Bool) -> RGB {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var out: RGB = (0, 0, 0)
        appearance.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            out = (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
        }
        return out
    }

    private func luminance(_ c: RGB) -> Double {
        func ch(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
    }

    private func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// CIE76 distance in Lab (D65). Crude beside CIEDE2000, but enough to rank
    /// "far apart" against "near"; the render is the judgement, this is the number.
    private func deltaE(_ a: RGB, _ b: RGB) -> Double {
        func lab(_ c: RGB) -> (Double, Double, Double) {
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            let (r, g, bl) = (lin(c.r), lin(c.g), lin(c.b))
            let x = (0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * bl
            let z = (0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883
            func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
            return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
        }
        let (p, q) = (lab(a), lab(b))
        return sqrt(pow(p.0 - q.0, 2) + pow(p.1 - q.1, 2) + pow(p.2 - q.2, 2))
    }

    /// The numbers STATUS logs for the decision. Printed so a run is the record;
    /// asserted only where the app already owes a floor (text 4.5:1, marks 3:1).
    func testAccentMeasurements() {
        var report = ""
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let pane = resolve(.pane, dark: dark), card = resolve(.card, dark: dark)
            let accent = resolve(Color.Kit.musicAccent, dark: dark)
            let ink = resolve(Color.Kit.musicAccentInk, dark: dark)
            let clay = resolve(.claude, dark: dark), blue = resolve(.attention, dark: dark)
            let alarm = resolve(.usageRed, dark: dark)
            let white: RGB = (1, 1, 1)
            report += """
            [\(mode)] accent-ink text on pane \(f(contrast(ink, pane))), on card \(f(contrast(ink, card)))
            [\(mode)] raw accent mark on pane \(f(contrast(accent, pane))), on card \(f(contrast(accent, card)))
            [\(mode)] white label on accent fill \(f(contrast(white, accent)))
            [\(mode)] distance accent-clay \(f(deltaE(accent, clay))), accent-blue \(f(deltaE(accent, blue))), clay-blue \(f(deltaE(clay, blue))), accent-usageRed \(f(deltaE(accent, alarm)))

            """
            // The decision (claude-spinner-music slice 1): red is a MARK colour. It
            // owes 3:1 and has it on both grounds, in both appearances.
            XCTAssertGreaterThanOrEqual(contrast(accent, pane), 3.0, "accent mark on pane, \(mode)")
            XCTAssertGreaterThanOrEqual(contrast(accent, card), 3.0, "accent mark on card, \(mode)")
            // As text it only clears 4.5:1 on the card surface. On the light pane it
            // measures 4.13, so a red link there fails; this pins the gap so a red
            // text token cannot be adopted without noticing.
            XCTAssertGreaterThanOrEqual(contrast(ink, card), 4.5, "accent text on card, \(mode)")
            if !dark { XCTAssertLessThan(contrast(ink, pane), 4.5, "known gap: accent text on the light pane") }
            // And a white label on a red fill (3.9 light, 3.8 dark) is large-text only.
            XCTAssertLessThan(contrast(white, accent), 4.5, "known gap: white 11pt label on the red fill, \(mode)")
            XCTAssertGreaterThanOrEqual(contrast(white, accent), 3.0, "white on red passes as large text, \(mode)")
            // Red stays clear of the status pair it must not blur.
            XCTAssertGreaterThan(deltaE(accent, clay), 30, "accent vs clay, \(mode)")
            XCTAssertGreaterThan(deltaE(accent, blue), 30, "accent vs blue, \(mode)")
        }
        print("MUSIC-ACCENT-MEASUREMENTS\n\(report)")
        try? report.write(toFile: NSTemporaryDirectory() + "accent-proof-measurements.txt",
                          atomically: true, encoding: .utf8)
    }

    private func f(_ v: Double) -> String { String(format: "%.2f", v) }

    /// A stand-in for the two surfaces the accent would touch: a see-through
    /// sidebar with a needs-you row, a working row and a selected row, and a page
    /// excerpt whose three chips put red, clay and blue side by side.
    private struct Sheet: View {
        var body: some View {
            HStack(spacing: 0) {
                sidebar.frame(width: 250).background(Color.pane)
                page.frame(width: 470).background(Color.card)
            }
            .frame(width: 720, height: 360)
        }

        private func symbolRow(_ symbol: String, _ title: String, selected: Bool = false) -> some View {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Color.Kit.musicAccent).frame(width: 18)
                Text(title).font(.ui(13)).fontWeight(selected ? .semibold : .regular)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(selected ? Color.Kit.musicSidebarSelect : .clear, in: RoundedRectangle(cornerRadius: 6))
        }

        private var sidebar: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sessions").font(.ui(11)).fontWeight(.semibold).foregroundStyle(Color.label)
                symbolRow("house", "Home", selected: true)
                symbolRow("paintpalette", "App Kit")
                Text("Pinned").font(.ui(11)).fontWeight(.semibold).foregroundStyle(Color.label).padding(.top, 8)
                symbolRow("pin", "Job Search")
                symbolRow("pin", "Plans")
                Text("Needs you").font(.ui(11)).fontWeight(.semibold).foregroundStyle(Color.label).padding(.top, 8)
                HStack(spacing: 8) {
                    Circle().fill(Color.attention).frame(width: 8, height: 8).frame(width: 18)
                    Text("AskUserQuestion with color").font(.ui(13)).lineLimit(1)
                }.padding(.horizontal, 8).padding(.vertical, 5)
                HStack(spacing: 8) {
                    Text("✻").foregroundStyle(Color.claude).frame(width: 18)
                    Text("formprobe").font(.ui(13))
                    Spacer()
                    Text("working").font(.ui(10)).foregroundStyle(Color.claude)
                }.padding(.horizontal, 8).padding(.vertical, 5)
                Spacer()
            }
            .padding(14)
        }

        private func chip(_ text: String, ink: Color, fill: Color? = nil, label: Color? = nil) -> some View {
            Text(text).font(.ui(11)).fontWeight(.semibold)
                .foregroundStyle(label ?? ink)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(fill ?? ink.opacity(0.14), in: Capsule())
        }

        private var page: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("Job Search").font(.system(size: 28, weight: .bold))
                HStack(spacing: 10) {
                    chip("needs you", ink: .attention)
                    chip("working", ink: .claude)
                    chip("Resume", ink: .white, fill: Color.Kit.musicAccent, label: .white)
                    chip("Open", ink: Color.Kit.musicAccentInk)
                }
                HStack(spacing: 4) {
                    Text("Tasks").font(.ui(15)).fontWeight(.bold)
                    Text("›").font(.ui(15)).fontWeight(.bold).foregroundStyle(Color.Kit.musicAccentInk)
                }
                Text("9 open · 95 done").font(.ui(11)).foregroundStyle(Color.label)
                HStack(spacing: 4) {
                    Text("+4 more").font(.ui(11)).foregroundStyle(Color.Kit.musicAccentInk)
                    Text("·").foregroundStyle(Color.label)
                    Text("+4 more").font(.ui(11)).foregroundStyle(Color.attention)
                    Text("(blue, today)").font(.ui(10)).foregroundStyle(Color.label)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Renders the sheet in both appearances to PNGs and checks each one is real:
    /// at 2x, and not a flat colour, so an empty render cannot pass as "judged".
    func testAccentProofRenders() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("accent-proof")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for dark in [false, true] {
            let host = NSHostingView(rootView: Sheet())
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 360)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.layoutSubtreeIfNeeded()
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 720,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            let url = dir.appendingPathComponent(dark ? "dark.png" : "light.png")
            try png.write(to: url)
            XCTAssertEqual(rep.pixelsWide, 1440)

            // Known-good beside known-bad: the accent chip's pixels must be in the
            // render, and the pane's left edge must be the pane colour.
            let accent = resolve(Color.Kit.musicAccent, dark: dark)
            var accentPixels = 0
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if abs(Double(c.redComponent) - accent.r) < 0.03, abs(Double(c.greenComponent) - accent.g) < 0.03,
                       abs(Double(c.blueComponent) - accent.b) < 0.03 { accentPixels += 1 }
                }
            }
            XCTAssertGreaterThan(accentPixels, 200, "the red CTA chip is in the \(dark ? "dark" : "light") render")
            let pane = resolve(.pane, dark: dark)
            let corner = try XCTUnwrap(rep.colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB))
            XCTAssertEqual(Double(corner.redComponent), pane.r, accuracy: 0.02, "the sidebar ground renders as the pane")
        }
        print("MUSIC-ACCENT-RENDERS \(dir.path)")
    }

    /// The page title is SF bold and the card titles are sentence case: no serif
    /// face is left in the target. Reads the source, so it first checks the read
    /// found the file, or an empty read would pass for "no serif".
    func testNoSerifTitleRemainsOnThePinnedPage() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("claude spinner")
        let detail = try String(contentsOf: dir.appendingPathComponent("PinnedProjectDetail.swift"), encoding: .utf8)
        XCTAssertTrue(detail.contains("struct SectionTitle"), "precondition: the read found the page source")
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) where name.hasSuffix(".swift") {
            let source = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(source.contains("design: .serif"), "\(name) still sets a serif face")
        }
    }
}
