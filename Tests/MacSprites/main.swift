import Foundation
import ImageIO
import CoreGraphics
import Metal

let repo = URL(fileURLWithPath: CommandLine.arguments[1])
let atlasURL = repo.appendingPathComponent("Resources/Sprites/piaopiao.png")
guard let source = CGImageSourceCreateWithURL(atlasURL as CFURL, nil),
      let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("PiaoPiao atlas is missing or unreadable")
}
precondition(CGImageSourceGetCount(source) == 1, "Atlas must be a single image")
precondition(atlas.width == 512 && atlas.height == 256, "Expected 64 px cells")
precondition(spriteSets.count == 17, "Every production state must be covered")
let coordinates = spriteSets.values.flatMap { $0 }.map { $0.1 * 8 + $0.0 }
precondition(Set(coordinates).count == 32, "All 32 cells must be mapped exactly once")

func bytes(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &data, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return data
}

var frames: [Int: [UInt8]] = [:]
for row in 0..<4 {
    for col in 0..<8 {
        let frame = atlas.cropping(to: CGRect(x: col * 64, y: row * 64, width: 64, height: 64))!
        let data = bytes(frame)
        let opaque = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 127 }.count
        precondition(opaque > 200 && opaque < 3600, "Cell \(col),\(row) must contain a transparent pet")
        for y in 0..<64 {
            for x in 0..<64 where x == 0 || y == 0 || x == 63 || y == 63 {
                precondition(data[(y * 64 + x) * 4 + 3] < 16,
                             "Pet touches cell edge: \(col),\(row) at \(x),\(y)")
            }
        }
        frames[row * 8 + col] = data
    }
}
for (animation, cells) in spriteSets {
    for (index, cell) in cells.enumerated() {
        let uv = spriteUV(animation, frame: index)
        precondition(uv.x == Float(cell.0) / 8 && uv.y == Float(cell.1) / 4)
        if index > 0 {
            let previous = cells[index - 1]
            precondition(frames[cell.1 * 8 + cell.0] != frames[previous.1 * 8 + previous.0],
                         "Duplicate frames in \(animation)")
        }
    }
}
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let path = repo.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/icon_\(size).png")
    let source = CGImageSourceCreateWithURL(path as CFURL, nil)!
    let icon = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    precondition(icon.width == size && icon.height == size)
    precondition(bytes(icon)[3] == 0, "Icon canvas corner must be transparent")
}
print("PASS: 32 transparent sprite cells, 17 animation mappings, distinct motion frames, 7 icon sizes")

// The optional gait sheet must be safe to sample at its cell borders and contain
// four authored phases in every direction; a missing/blank cell is visible in motion.
let walkURL = repo.appendingPathComponent("Resources/Sprites/piaopiao-walk.png")
guard let walkSource = CGImageSourceCreateWithURL(walkURL as CFURL, nil),
      let walkAtlas = CGImageSourceCreateImageAtIndex(walkSource, 0, nil) else {
    fatalError("PiaoPiao walking atlas is missing or unreadable")
}
precondition(walkAtlas.width == 256 && walkAtlas.height == 512)
for row in 0..<8 {
    var phases: [[UInt8]] = []
    for col in 0..<4 {
        let cell = walkAtlas.cropping(to: CGRect(x: col * 64, y: row * 64, width: 64, height: 64))!
        let data = bytes(cell)
        let opaque = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 127 }.count
        precondition(opaque > 200 && opaque < 3600, "Blank or filled walking cell \(row),\(col)")
        for y in 0..<64 {
            for x in 0..<64 where x == 0 || y == 0 || x == 63 || y == 63 {
                precondition(data[(y * 64 + x) * 4 + 3] < 16,
                             "Walking sprite touches cell edge: \(row),\(col)")
            }
        }
        precondition(!phases.contains(data), "Repeated walking phase: \(row),\(col)")
        phases.append(data)
    }
}
print("PASS: 8 directions × 4 distinct walking phases with transparent cell margins")

let manager = SkinManager()
var missingDeviceFailed = false
manager.loadSkinFromURL(id: "missing-device", url: atlasURL) { missingDeviceFailed = !$0 }
precondition(missingDeviceFailed, "A missing GPU must complete with failure")
if let device = MTLCreateSystemDefaultDevice() {
    manager.setDevice(device)
    for (id, url, expected) in [
        ("piaopiao", atlasURL, true),
        ("invalid", repo.appendingPathComponent("Info.plist"), false)
    ] {
        let completed = DispatchSemaphore(value: 0)
        var actual: Bool?
        manager.loadSkinFromURL(id: id, url: url) { result in actual = result; completed.signal() }
        precondition(completed.wait(timeout: .now() + 5) == .success, "Skin loader must always finish")
        precondition(actual == expected, "Decode result must reach the caller")
    }
    precondition(manager.texture(id: "piaopiao")?.width == 512)
    precondition(manager.texture(id: "piaopiao")?.height == 256)
    precondition(manager.texture(id: "invalid") == nil)
    let previewID = try manager.loadPreviewSkin(from: atlasURL)
    precondition(manager.walkingTexture(id: previewID)?.width == 256)
    precondition(manager.walkingTexture(id: previewID)?.height == 512)
    precondition(manager.walkingTexture(id: "classic") == nil,
                 "PiaoPiao's walking sheet must not leak into other companions")
    print("PASS: Metal PNG loading and invalid-image failure callbacks")
} else {
    print("SKIP: Metal texture upload requires a GPU; file/animation checks passed")
}
