// Deterministic image packaging only: crop, shared per-direction scale, translation,
// and horizontal mirroring. Preserves source alpha and never draws new artwork.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Manifest: Decodable {
    let width: Int
    let height: Int
    let cellSize: Int
    let frames: [Frame]
}
struct Frame: Decodable {
    let direction: String
    let phase: Int
    let row: Int
    let source: String
    let crop: [Double]
    let sourceAnchor: [Double]
    let outputAnchor: [Double]
    let scale: Double
    let mirror: Bool
}
func require(_ condition: Bool, _ message: String) {
    if !condition { fputs("PreparePiaoPalWalk: \(message)\n", stderr); exit(1) }
}
let args = CommandLine.arguments
require(args.count == 3, "Usage: prepare-piaopal-walk <manifest.json> <output.png>")
let manifestURL = URL(fileURLWithPath: args[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: args[2]).standardizedFileURL
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
require(manifest.width == 256 && manifest.height == 512 && manifest.cellSize == 64,
        "Expected a 4-column, 8-row atlas with 64px cells")
require(manifest.frames.count == 32, "Expected exactly 32 walk frames")
require(Set(manifest.frames.map { "\($0.row):\($0.phase)" }).count == 32,
        "Duplicate destination cell")
let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
var scales: [String: Double] = [:]
var sources: [String: CGImage] = [:]
let context = CGContext(data: nil, width: manifest.width, height: manifest.height,
                        bitsPerComponent: 8, bytesPerRow: manifest.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .none
for frame in manifest.frames {
    require((0..<8).contains(frame.row) && (0..<4).contains(frame.phase), "Invalid cell")
    require(frame.direction == directions[frame.row], "Unexpected direction row")
    require(frame.crop.count == 4 && frame.sourceAnchor.count == 2 && frame.outputAnchor.count == 2,
            "Malformed crop or anchor")
    require(frame.scale > 0 && frame.scale < 1, "Unexpected source scale")
    if let scale = scales[frame.direction] {
        require(abs(scale - frame.scale) < 0.000001, "Scale must be shared by all phases of a direction")
    }
    scales[frame.direction] = frame.scale
    if sources[frame.source] == nil {
        let url = manifestURL.deletingLastPathComponent().appendingPathComponent(frame.source)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            fatalError("Cannot read \(url.path)")
        }
        sources[frame.source] = image
    }
    let image = sources[frame.source]!
    let crop = CGRect(x: frame.crop[0], y: frame.crop[1], width: frame.crop[2], height: frame.crop[3])
    require(crop.minX >= 0 && crop.minY >= 0 && crop.maxX <= CGFloat(image.width) && crop.maxY <= CGFloat(image.height),
            "Crop exceeds source image")
    guard let cropped = image.cropping(to: crop) else { fatalError("Cannot crop image") }
    let width = (crop.width * frame.scale).rounded()
    let height = (crop.height * frame.scale).rounded()
    let x = (frame.outputAnchor[0] + (crop.minX - frame.sourceAnchor[0]) * frame.scale).rounded()
    let top = (frame.outputAnchor[1] + (crop.minY - frame.sourceAnchor[1]) * frame.scale).rounded()
    require(x >= 1 && top >= 1 && x + width <= 63 && top + height <= 63,
            "Frame \(frame.direction) \(frame.phase) exceeds safe cell margin")
    context.saveGState()
    context.translateBy(x: CGFloat(frame.phase * 64), y: CGFloat(manifest.height - (frame.row + 1) * 64))
    if frame.mirror {
        context.translateBy(x: 64, y: 0)
        context.scaleBy(x: -1, y: 1)
    }
    context.draw(cropped, in: CGRect(x: x, y: 64 - top - height, width: width, height: height))
    context.restoreGState()
}
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Cannot create output")
}
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
require(CGImageDestinationFinalize(destination), "Cannot save output")
print("Packed 32 preserved-alpha frames into \(outputURL.path)")
