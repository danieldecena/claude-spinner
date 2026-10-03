//
//  BarTintTests.swift
//  claude spinnerTests
//
//  The cover's tint is only worth having while the bar's text stays readable on
//  it, so the tests pair a cover that is used with one that must not be.
//

import AppKit
import XCTest
@testable import claude_spinner

final class BarTintTests: XCTestCase {
    /// An image of exact sRGB bytes, from a CGContext. Not `lockFocus`, which draws
    /// in the screen's colour space and shifts pure red before the average is taken,
    /// and not a hand-built NSBitmapImageRep, which came out with no valid colour space.
    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, size: Int = 40) -> NSImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: size, height: size))
    }

    /// The Core Image path itself, on an image whose answer is known.
    func testAreaAverageOfASolidImageIsThatColour() throws {
        let red = try XCTUnwrap(BarTint.average(of: solid(255, 0, 0)))
        XCTAssertEqual(red.r, 1, accuracy: 0.03)
        XCTAssertEqual(red.g, 0, accuracy: 0.03)
        let grey = try XCTUnwrap(BarTint.average(of: solid(128, 128, 128)))
        XCTAssertEqual(grey.r, 0.5, accuracy: 0.05, "a mid grey is not read as black or white")
    }

    /// Half black, half white averages to the middle: it is a mean, not the first
    /// pixel or the dominant one.
    func testAreaAverageIsAMeanOfThePixels() throws {
        let size = 40
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 20, height: size))
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 20, y: 0, width: 20, height: size))
        let image = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: size, height: size))
        let mean = try XCTUnwrap(BarTint.average(of: image))
        XCTAssertEqual(mean.r, 0.5, accuracy: 0.08)
    }

    private let darkPane: BarTint.RGB = (0, 0, 0)
    private let white: BarTint.RGB = (1, 1, 1)
    private let darkLabel: BarTint.RGB = (0.596, 0.596, 0.616)

    /// A dark cover keeps the text readable on the dark bar, so it is used. A bright
    /// yellow one lifts the glass until the quieter label ink drops under 4.5:1, so
    /// the bar goes back to plain glass.
    func testADarkCoverIsUsedAndABrightOneFallsBack() {
        let navy: BarTint.RGB = (0.08, 0.10, 0.30)
        XCTAssertNotNil(BarTint.usable(average: navy, pane: darkPane, ink: white, label: darkLabel))
        let yellow: BarTint.RGB = (1.0, 0.9, 0.1)
        XCTAssertNil(BarTint.usable(average: yellow, pane: darkPane, ink: white, label: darkLabel),
                     "the cover that would push the text under 4.5:1 is not used")
    }

    /// The decision is the contrast itself, not a hue test: the same yellow IS usable
    /// at a strength low enough to keep the ground dark.
    func testTheFallbackFollowsTheContrastNotTheColour() {
        let yellow: BarTint.RGB = (1.0, 0.9, 0.1)
        XCTAssertNotNil(BarTint.usable(average: yellow, pane: darkPane, ink: white, label: darkLabel, strength: 0.05))
        XCTAssertNil(BarTint.usable(average: yellow, pane: darkPane, ink: white, label: darkLabel, strength: 0.30))
    }

    func testTheCrossfadeIsTheMeasuredShelfEaseOut() {
        XCTAssertEqual(BarTint.fadeDuration, 0.73, accuracy: 0.001)
    }
}
