// Deterministic asset compilation only. Artwork is generated with image_gen, then
// resized here; no drawing, background removal, or synthesized animation frames.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func read(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "PiaoPal.Artwork", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot read \(path)"])
    }
    return image
}

func resized(_ source: CGImage, width: Int, height: Int,
             interpolation: CGInterpolationQuality) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = interpolation
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func write(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
        UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot create \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot save \(path)")
}

let args = CommandLine.arguments
guard args.count == 4, ["icon", "atlas", "pack"].contains(args[1]) else {
    print("Usage: swift main.swift icon|atlas|pack SOURCE.png-or-manifest.json DESTINATION_DIRECTORY")
    exit(1)
}
let destination = URL(fileURLWithPath: args[3])
switch args[1] {
case "icon":
    let source = try read(args[2])
    precondition(source.width == source.height, "App icon must be square")
    for size in [16, 32, 64, 128, 256, 512, 1024] {
        try write(resized(source, width: size, height: size, interpolation: .high),
                  to: destination.appendingPathComponent("icon_\(size).png").path)
    }
case "atlas":
    let source = try read(args[2])
    precondition(source.width == source.height * 2, "Atlas must be an 8 × 4 square-cell grid")
    try write(resized(source, width: 512, height: 256, interpolation: .none),
              to: destination.appendingPathComponent("piaopiao.png").path)
case "pack":
    let manifestURL = URL(fileURLWithPath: args[2])
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    let frames = manifest["frames"] as! [[String: Any]]
    precondition(frames.count == 32)
    let context = CGContext(data: nil, width: 512, height: 256,
                            bitsPerComponent: 8, bytesPerRow: 512 * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .none
    var sources: [String: CGImage] = [:]
    for frame in frames {
        let name = frame["source"] as! String
        let path = name.hasPrefix("/") ? name : manifestURL.deletingLastPathComponent().appendingPathComponent(name).path
        if sources[path] == nil { sources[path] = try read(path) }
        let crop = frame["crop_xyxy"] as! [Double]
        let scale = frame["output_scale"] as! Double
        let col = frame["col"] as! Int, row = frame["row"] as! Int
        let center = frame["ink_center_x"] as! Double, bottom = frame["ink_bottom_y"] as! Double
        let anchor = frame["output_anchor"] as! [Double]
        let cropped = sources[path]!.cropping(to: CGRect(x: crop[0], y: crop[1],
            width: crop[2] - crop[0], height: crop[3] - crop[1]))!
        let width = ((crop[2] - crop[0]) * scale).rounded()
        let height = ((crop[3] - crop[1]) * scale).rounded()
        let x = (Double(col * 64) + anchor[0] + (crop[0] - center) * scale).rounded()
        let top = (Double(row * 64) + anchor[1] + (crop[1] - bottom) * scale).rounded()
        precondition(x >= Double(col * 64) && x + width <= Double((col + 1) * 64))
        precondition(top >= Double(row * 64) && top + height <= Double((row + 1) * 64))
        context.draw(cropped, in: CGRect(x: x, y: 256 - top - height, width: width, height: height))
    }
    try write(context.makeImage()!, to: destination.appendingPathComponent("piaopiao.png").path)
default: break
}
print("Compiled \(args[1]) assets into \(destination.path)")
