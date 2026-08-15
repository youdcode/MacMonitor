#!/usr/bin/env swift
//
// Draws the application icon and writes every size the asset catalogue needs.
//
//     swift Tools/GenerateAppIcon.swift
//
// The icon lives in this file rather than as committed artwork. A public repository
// should not carry binaries whose provenance nobody can check, and an icon that is
// code can be re-rendered at any size when Apple changes what it asks for. The PNGs
// it produces are committed too, so a fresh clone builds without running anything.
//
// Requires nothing beyond the toolchain the project already needs: AppKit and
// CoreGraphics ship with macOS.
//
// Reusable for another application: change the three values under "Design" and run it.
// Nothing else here is specific to this project.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Design

/// The artwork is deliberately sober. This is a system tool, not a product: no brand
/// palette, no colour identity. Graphite and white read the way Activity Monitor,
/// Terminal and Console read, and they leave colour free to mean something in the
/// interface itself, where it carries state.
let backgroundTop = CGColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 1)
let backgroundBottom = CGColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1)
let lineColour = CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)

/// A fixed sparkline. Not random: the icon must be byte-identical on every run, or it
/// is not reproducible and there is no point generating it.
///
/// Six points, not twelve. The first draft used twelve and it collapsed into a blur at
/// 32 pixels, where each segment was under two pixels wide - which is the size the
/// icon is actually seen at most of the time, in the Dock and the menu bar.
let trace: [Double] = [0.22, 0.52, 0.34, 0.74, 0.46, 0.92]

// MARK: - Drawing

func drawIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let context = CGContext(data: nil,
                                  width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // macOS icons sit inside their canvas with padding, unlike iOS where the system
    // masks a full-bleed image. Apple's grid puts the shape at about 80% of the width.
    let inset = s * 0.10
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    // Rounded rather than a true continuous squircle: the difference is invisible at
    // icon sizes and a superellipse would add code with nothing to show for it.
    let radius = rect.width * 0.225
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(shape)
    context.clip()
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [backgroundTop, backgroundBottom] as CFArray,
                                 locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: rect.maxY),
                                   end: CGPoint(x: 0, y: rect.minY),
                                   options: [])
    }
    context.restoreGState()

    // A hairline edge, so the shape stays defined against a dark desktop.
    context.saveGState()
    context.addPath(shape)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    context.setLineWidth(max(s * 0.004, 0.5))
    context.strokePath()
    context.restoreGState()

    // The sparkline, which is what the application actually draws all day.
    let plot = rect.insetBy(dx: rect.width * 0.19, dy: rect.height * 0.30)
    let step = plot.width / CGFloat(trace.count - 1)
    let path = CGMutablePath()
    for (i, value) in trace.enumerated() {
        let point = CGPoint(x: plot.minX + CGFloat(i) * step,
                            y: plot.minY + CGFloat(value) * plot.height)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }

    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(lineColour)
    context.setLineWidth(max(s * 0.050, 1))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    // A baseline under it, dimmed, so the trace reads as a measurement rather than a
    // decorative squiggle.
    context.saveGState()
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
    context.setLineWidth(max(s * 0.022, 0.5))
    context.setLineCap(.round)
    context.move(to: CGPoint(x: plot.minX, y: plot.minY - plot.height * 0.22))
    context.addLine(to: CGPoint(x: plot.maxX, y: plot.minY - plot.height * 0.22))
    context.strokePath()
    context.restoreGState()

    return context.makeImage()
}

// MARK: - Output

/// The ten images a macOS app icon set is made of: 16, 32, 128, 256 and 512 points,
/// each at 1x and 2x.
let variants: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("MacMonitor/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

var entries: [String] = []
for variant in variants {
    let pixels = variant.size * variant.scale
    guard let image = drawIcon(size: pixels) else {
        FileHandle.standardError.write("failed to draw \(pixels)px\n".data(using: .utf8)!)
        exit(1)
    }
    let filename = "icon_\(variant.size)x\(variant.size)\(variant.scale == 2 ? "@2x" : "").png"
    let url = iconSet.appendingPathComponent(filename)
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: pixels, height: pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try! png.write(to: url)
    entries.append("""
        {
          "filename" : "\(filename)",
          "idiom" : "mac",
          "scale" : "\(variant.scale)x",
          "size" : "\(variant.size)x\(variant.size)"
        }
    """)
    print("wrote \(filename) (\(pixels)px)")
}

let manifest = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try! manifest.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
