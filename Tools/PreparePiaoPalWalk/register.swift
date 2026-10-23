// Source registration/packaging only: crop, one shared scale and translation.
// No pixel cleanup, painting, deformation or frame synthesis.
// swiftc register-sources.swift -o register-sources
// register-sources input.json strip.png manifest.json
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
struct Spec: Decodable {
    let direction: String
    let sources: [String]
    let scale: Double
    let registrationRect: [Int] // x, y, width, height in the phase-0 image
    let referenceBodyX: Double
    let outputAnchor: [Double]
    let searchRadius: Int?
}
struct Raster {
    let image: CGImage
    let width: Int
    let height: Int
    let bytes: [UInt8]
    init(_ url: URL) {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        width = image.width; height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }
    func pixel(_ x: Int, _ y: Int, _ channel: Int) -> Int { Int(bytes[(y * width + x) * 4 + channel]) }
    func bounds(alpha: Int) -> [Int] {
        var box = [width, height, 0, 0]
        for y in 0..<height { for x in 0..<width where pixel(x, y, 3) > alpha {
            box[0] = min(box[0], x); box[1] = min(box[1], y)
            box[2] = max(box[2], x + 1); box[3] = max(box[3], y + 1)
        }}
        return box
    }
}
func fail(_ message: String) -> Never { fputs("RegisterSources: \(message)\n", stderr); exit(1) }
let args = CommandLine.arguments
guard args.count == 4 else { fail("Expected input.json strip.png manifest.json") }
let inputURL = URL(fileURLWithPath: args[1]).standardizedFileURL
let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: inputURL))
guard spec.sources.count == 4, spec.registrationRect.count == 4,
      spec.outputAnchor.count == 2, spec.scale > 0, spec.scale < 1 else { fail("Malformed input") }
let urls = spec.sources.map { name in
    name.hasPrefix("/") ? URL(fileURLWithPath: name) : inputURL.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
}
let images = urls.map(Raster.init)
let base = images[0]
let rect = spec.registrationRect
let radius = spec.searchRadius ?? 48
var shifts: [(dx: Int, dy: Int, score: Double)] = []
for (phase, candidate) in images.enumerated() {
    func score(dx: Int, dy: Int, step: Int) -> Double {
        var total = 0.0, count = 0
        for y in Swift.stride(from: rect[1], to: rect[1] + rect[3], by: step) {
            for x in Swift.stride(from: rect[0], to: rect[0] + rect[2], by: step) {
                let xx = x + dx, yy = y + dy
                if x < 0 || y < 0 || x >= base.width || y >= base.height || xx < 0 || yy < 0 || xx >= candidate.width || yy >= candidate.height { continue }
                for channel in 0..<4 { total += Double(abs(base.pixel(x, y, channel) - candidate.pixel(xx, yy, channel))) }
                count += 4
            }
        }
        return count > 0 ? total / Double(count) : .infinity
    }
    var best = (dx: 0, dy: 0, score: phase == 0 ? 0 : Double.infinity)
    if phase > 0 {
        for dy in Swift.stride(from: -radius, through: radius, by: 4) {
            for dx in Swift.stride(from: -radius, through: radius, by: 4) {
                let error = score(dx: dx, dy: dy, step: 5)
                if error < best.score { best = (dx, dy, error) }
            }
        }
        let coarse = best
        best.score = .infinity
        for dy in (coarse.dy - 4)...(coarse.dy + 4) {
            for dx in (coarse.dx - 4)...(coarse.dx + 4) {
                let error = score(dx: dx, dy: dy, step: 2)
                if error < best.score { best = (dx, dy, error) }
            }
        }
    }
    shifts.append(best)
}
let visible = images.map { $0.bounds(alpha: 32) }
// One common baseline after upper-body registration, never per-frame fitting.
let baseline = zip(visible, shifts).map { Double($0.0[3] - $0.1.dy) }.max()!
let context = CGContext(data: nil, width: 256, height: 64, bitsPerComponent: 8, bytesPerRow: 256 * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .none
var frames: [[String: Any]] = []
for (phase, raster) in images.enumerated() {
    // Alpha is used to choose a padded crop only. Do not modify any RGBA inside it.
    // Generated sources can contain alpha-1 dust far outside the actual character.
    let raw = visible[phase]
    let left = max(0, raw[0] - 4), top = max(0, raw[1] - 4)
    let right = min(raster.width, raw[2] + 4), bottom = min(raster.height, raw[3] + 4)
    let crop = [left, top, right - left, bottom - top]
    let anchor = [spec.referenceBodyX + Double(shifts[phase].dx), baseline + Double(shifts[phase].dy)]
    let outputX = (spec.outputAnchor[0] + (Double(left) - anchor[0]) * spec.scale).rounded()
    let outputTop = (spec.outputAnchor[1] + (Double(top) - anchor[1]) * spec.scale).rounded()
    let drawWidth = (Double(crop[2]) * spec.scale).rounded()
    let drawHeight = (Double(crop[3]) * spec.scale).rounded()
    guard outputX >= 1, outputTop >= 1, outputX + drawWidth <= 63, outputTop + drawHeight <= 63 else {
        fail("\(spec.direction) phase \(phase) exceeds cell safe margins: \([outputX, outputTop, drawWidth, drawHeight])")
    }
    let cropped = raster.image.cropping(to: CGRect(x: left, y: top, width: crop[2], height: crop[3]))!
    context.draw(cropped, in: CGRect(x: Double(phase * 64) + outputX, y: 64 - outputTop - drawHeight,
        width: drawWidth, height: drawHeight))
    frames.append(["phase": phase, "direction": spec.direction, "source": urls[phase].path,
        "sourceDimensions": [raster.width, raster.height], "crop": crop, "visibleBBox": visible[phase],
        "sourceAnchor": anchor, "outputAnchor": spec.outputAnchor, "scale": spec.scale,
        "headBodyRegistrationShift": [shifts[phase].dx, shifts[phase].dy],
        "registrationError": shifts[phase].score,
        "outputRect": [outputX, outputTop, drawWidth, drawHeight]])
}
let outputURL = URL(fileURLWithPath: args[2]).standardizedFileURL
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fail("Cannot save strip") }
let report: [String: Any] = ["schemaVersion": 1, "direction": spec.direction, "width": 256, "height": 64,
    "cellSize": 64, "columns": 4, "scale": spec.scale, "registrationRect": rect,
    "referenceBodyX": spec.referenceBodyX, "sharedGroundY": baseline,
    "method": "Premultiplied RGBA translation registration in head/upper-body window; shared scale and baseline; alpha>32 selects a padded crop only and all RGBA within crop is retained; nearest-neighbor resampling; no redraw or synthesis",
    "frames": frames]
let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: args[3]))
print(String(data: json, encoding: .utf8)!)
