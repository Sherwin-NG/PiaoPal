// Review the actual production atlas and animation map together, with no new artwork.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let atlasURL = root.appendingPathComponent("Resources/Sprites/piaopiao.png")
let source = CGImageSourceCreateWithURL(atlasURL as CFURL, nil)!
let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let animations: [Anim] = [.idle, .alert, .tired, .sleeping, .scratchSelf,
                         .N, .NE, .E, .SE, .S, .SW, .W, .NW,
                         .scratchWallN, .scratchWallS, .scratchWallE, .scratchWallW]
let width = 720, height = 680
let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("piaopiao-motion-review.gif") as CFURL,
    UTType.gif.identifier as CFString, 12, nil)!
CGImageDestinationSetProperties(destination,
    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for tick in 0..<12 {
    let context = CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for (index, animation) in animations.enumerated() {
        let tileX = (index % 5) * 144, tileTop = (index / 5) * 170
        let frames = spriteSets[animation]!
        let frameIndex = animation == .sleeping ? tick / 4 : tick
        let (col, row) = frames[frameIndex % frames.count]
        let sprite = atlas.cropping(to: CGRect(x: col * 64, y: row * 64, width: 64, height: 64))!
        context.draw(sprite, in: CGRect(x: tileX + 8, y: height - tileTop - 138, width: 128, height: 128))
        let label = NSAttributedString(string: animation.rawValue, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.darkGray
        ])
        label.draw(at: NSPoint(x: tileX + (144 - Int(label.size().width)) / 2,
                               y: height - tileTop - 162))
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = context.makeImage()!
    CGImageDestinationAddImage(destination, image,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.15]] as CFDictionary)
    if tick == 0 {
        let png = CGImageDestinationCreateWithURL(output.appendingPathComponent("piaopiao-state-review.png") as CFURL,
            UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(png, image, nil)
        precondition(CGImageDestinationFinalize(png))
    }
}
precondition(CGImageDestinationFinalize(destination))
print("Animation review saved to \(output.path)")
