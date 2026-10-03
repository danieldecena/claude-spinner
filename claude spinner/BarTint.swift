//
//  BarTint.swift
//
//  The floating bar's glass picks up the playing cover's colour, as Music's player
//  does (claude-spinner-playback slice 4). The average comes from Core Image's
//  `CIAreaAverage`; whether it is used at all is a contrast question, decided
//  here in pure functions so a cover that would make the bar's text hard to read
//  falls back to untinted glass instead.
//

import AppKit
import CoreImage
import SwiftUI

nonisolated enum BarTint {
    typealias RGB = (r: Double, g: Double, b: Double)

    /// How strongly the cover colours the glass. The text is on this, so it is
    /// kept low: enough to read as the cover's colour, not enough to repaint it.
    static let strength = 0.30

    /// The fade between covers: no artwork-specific motion was captured, so this is
    /// `music-motion-shelf`, the one measured Music ease-out (about 0.73 s). None
    /// under Reduce Motion, which the view decides.
    static let fadeDuration = 0.73

    /// The mean colour of an image, through `CIAreaAverage`, or nil for an image
    /// with no pixels.
    static func average(of image: NSImage) -> RGB? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: input,
                                                 kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(
            output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    private static func luminance(_ c: RGB) -> Double {
        func ch(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The tint to use, or nil for plain glass. The glass is the pane's colour with
    /// the cover mixed in at `strength`; the bar's text (primary and the quieter
    /// label ink) must keep 4.5:1 on that, or the cover is not used.
    static func usable(average: RGB, pane: RGB, ink: RGB, label: RGB, strength: Double = strength) -> RGB? {
        let ground = (r: pane.r * (1 - strength) + average.r * strength,
                      g: pane.g * (1 - strength) + average.g * strength,
                      b: pane.b * (1 - strength) + average.b * strength)
        guard contrast(ink, ground) >= 4.5, contrast(label, ground) >= 4.5 else { return nil }
        return average
    }
}
