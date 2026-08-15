#!/usr/bin/env swift
//
// Draws the repository's social preview: the card that appears when the link is shared
// anywhere other than GitHub itself.
//
//     swift Tools/GenerateSocialPreview.swift
//
// GitHub's default is a grey rectangle with the repository name on it, which sells
// nothing. This one is assembled out of the application's own parts and nothing else:
// a crop of a committed screenshot, the committed icon, and the background colour read
// out of that same screenshot rather than chosen to look right. Like the icon
// generator beside it, the image is code, so it can be re-rendered when it needs to
// change and its provenance is inspectable.
//
// The image is committed too. It is not installed from here: GitHub takes it in the
// repository settings, by hand.
//
// 1280 x 640 is the size GitHub asks for. Some surfaces crop the edges, so nothing
// that carries meaning goes within 60 px of one - and the script measures what it drew
// and prints the four margins at the end, rather than leaving that as a promise.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Canvas

let canvasWidth = 1280
let canvasHeight = 640

/// GitHub's crop. Checked at the end against the bounding box of everything drawn.
let safeMargin: CGFloat = 60
/// Where things are actually put, comfortably inside that.
let inset: CGFloat = 80

// MARK: - Colours

/// Read out of docs/images/overview-dark.png, not picked: the window background at
/// (2850, 1850), which is empty space below the last card. Sampling it rather than
/// choosing it keeps the card the same surface the application is drawn on.
let canvasColour = CGColor(red: 0x28 / 255, green: 0x28 / 255, blue: 0x28 / 255, alpha: 1)

/// The dark appearance, and not the light one, for two reasons that are not taste. The
/// light appearance on this version of macOS is very nearly flat white - the window
/// background, the cards and the gaps between them all sampled #FFFFFF - so a light
/// card would be a white rectangle with a white rectangle on it. And the icon is
/// graphite, which sits on dark without a seam.
///
/// These two are choices rather than measurements, and are written as such: neutral
/// white at two weights, no hue, nothing borrowed from a palette.
let titleColour = NSColor(white: 1, alpha: 0.95)
let taglineColour = NSColor(white: 1, alpha: 0.55)
/// The hairline every card in the application carries: Color.primary at low opacity,
/// which in the dark appearance is white.
let hairlineColour = CGColor(gray: 1, alpha: 0.09)

// MARK: - Content

let title = "MacMonitor"
/// Straight from the README's second paragraph. It is the whole argument of the
/// project in one line, and it is a claim the application keeps.
let tagline = "Where a value could not be measured honestly, it is not shown."

let screenshotPath = "docs/images/overview-dark.png"
let iconPath = "MacMonitor/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png"
let outputPath = "docs/social-preview.png"

/// The region of the screenshot to show: the four ring gauges with their labels and
/// their readings, in the source image's own pixels, origin top left.
///
/// The gauges rather than the whole window. A 2920 x 1898 window scaled down to fit
/// beside a title lands at about a quarter size, where every number in it becomes a
/// smudge; this crop is drawn at very nearly 1:1, so the readings stay readable at the
/// size a link preview is actually looked at.
///
/// The width is what makes the strip match the space it goes in without distortion.
/// The height is the gauge block plus a little card above and below it.
let crop = CGRect(x: 1164, y: 305, width: 1062, height: 275)

// MARK: - Helpers

func loadImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
    guard let image = NSImage(contentsOf: url) else { return nil }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    // The rounded design, because it is what the application uses for every figure it
    // shows. The system font, because there is no typeface to import and no wordmark
    // to invent.
    guard let descriptor = base.fontDescriptor.withDesign(.rounded),
          let rounded = NSFont(descriptor: descriptor, size: size) else { return base }
    return rounded
}

/// Everything is placed with y measured from the TOP of the card, which is how the
/// layout is easier to reason about; this converts to the bottom-left origin
/// CoreGraphics draws in.
func fromTop(_ y: CGFloat) -> CGFloat { CGFloat(canvasHeight) - y }

/// The bounding box, in top-left coordinates, of everything drawn. The margin check at
/// the end is made against this and not against the numbers above, so a mistake in the
/// layout shows up rather than being asserted away.
var drawn: CGRect?

func record(_ rect: CGRect) {
    drawn = drawn.map { $0.union(rect) } ?? rect
}

// MARK: - Drawing

guard let context = CGContext(data: nil,
                              width: canvasWidth, height: canvasHeight,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("could not create the context\n".data(using: .utf8)!)
    exit(1)
}

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high
context.setFillColor(canvasColour)
context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics

// The icon. Its PNG carries the 10 % padding every macOS icon has, so the shape people
// see is 80 % of the box it is drawn in, and the title is centred on the shape rather
// than on the box.
let iconBox: CGFloat = 104
let iconTop: CGFloat = 74
if let icon = loadImage(iconPath) {
    let rect = CGRect(x: inset, y: fromTop(iconTop + iconBox), width: iconBox, height: iconBox)
    context.draw(icon, in: rect)
    record(CGRect(x: inset + iconBox * 0.10, y: iconTop + iconBox * 0.10,
                  width: iconBox * 0.80, height: iconBox * 0.80))
} else {
    FileHandle.standardError.write("could not read \(iconPath)\n".data(using: .utf8)!)
    exit(1)
}

let shapeTop = iconTop + iconBox * 0.10
let shapeHeight = iconBox * 0.80

let titleText = NSAttributedString(string: title,
                                   attributes: [.font: font(54, .semibold), .foregroundColor: titleColour])
let titleSize = titleText.size()
let titleLeft = inset + iconBox + 22
let titleTop = shapeTop + (shapeHeight - titleSize.height) / 2
titleText.draw(in: CGRect(x: titleLeft, y: fromTop(titleTop + titleSize.height),
                          width: ceil(titleSize.width), height: ceil(titleSize.height)))
record(CGRect(x: titleLeft, y: titleTop, width: ceil(titleSize.width), height: ceil(titleSize.height)))

let taglineText = NSAttributedString(string: tagline,
                                     attributes: [.font: font(23, .regular), .foregroundColor: taglineColour])
let taglineSize = taglineText.size()
let taglineTop: CGFloat = 202
taglineText.draw(in: CGRect(x: inset, y: fromTop(taglineTop + taglineSize.height),
                            width: ceil(taglineSize.width), height: ceil(taglineSize.height)))
record(CGRect(x: inset, y: taglineTop, width: ceil(taglineSize.width), height: ceil(taglineSize.height)))

NSGraphicsContext.restoreGraphicsState()

// The strip: a crop of the screenshot, clipped to the same corner radius the cards in
// the application use, with the same hairline round it. It is drawn at 1.05 times its
// own pixels, so it is very nearly the size it is on screen.
let stripTop: CGFloat = 278
let stripHeight: CGFloat = 290
let stripRect = CGRect(x: inset, y: fromTop(stripTop + stripHeight),
                       width: CGFloat(canvasWidth) - inset * 2, height: stripHeight)
let radius: CGFloat = 12

guard let screenshot = loadImage(screenshotPath) else {
    FileHandle.standardError.write("could not read \(screenshotPath)\n".data(using: .utf8)!)
    exit(1)
}
guard let fragment = screenshot.cropping(to: crop) else {
    FileHandle.standardError.write("the crop falls outside the screenshot\n".data(using: .utf8)!)
    exit(1)
}

// The crop and the strip have to be the same shape or the gauges come out oval.
let cropAspect = crop.width / crop.height
let stripAspect = stripRect.width / stripRect.height
guard abs(cropAspect - stripAspect) < 0.01 else {
    FileHandle.standardError.write(String(format: "crop is %.3f:1 and the strip is %.3f:1\n",
                                          cropAspect, stripAspect).data(using: .utf8)!)
    exit(1)
}

context.saveGState()
let shape = CGPath(roundedRect: stripRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
context.addPath(shape)
context.clip()
context.draw(fragment, in: stripRect)
context.restoreGState()

context.addPath(shape)
context.setStrokeColor(hairlineColour)
context.setLineWidth(1)
context.strokePath()
record(CGRect(x: stripRect.minX, y: stripTop, width: stripRect.width, height: stripHeight))

// MARK: - Output

guard let image = context.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: canvasWidth, height: canvasHeight)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(outputPath)
try! png.write(to: output)

print("wrote \(outputPath) (\(image.width) x \(image.height) px)")

guard let box = drawn else { exit(1) }
let margins = (left: box.minX,
               top: box.minY,
               right: CGFloat(canvasWidth) - box.maxX,
               bottom: CGFloat(canvasHeight) - box.maxY)
print(String(format: "content   x %.0f..%.0f   y %.0f..%.0f", box.minX, box.maxX, box.minY, box.maxY))
print(String(format: "margins   left %.0f   top %.0f   right %.0f   bottom %.0f   (%.0f required)",
             margins.left, margins.top, margins.right, margins.bottom, safeMargin))

let smallest = min(margins.left, margins.top, margins.right, margins.bottom)
if smallest < safeMargin {
    FileHandle.standardError.write(String(format: "the smallest margin is %.0f px, inside GitHub's crop\n",
                                          smallest).data(using: .utf8)!)
    exit(1)
}
print("every margin clears the crop")
