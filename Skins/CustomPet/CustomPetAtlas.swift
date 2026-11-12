import Foundation
import CoreGraphics
import ImageIO

enum SpriteAtlasKind: Equatable {
    case main
    case walk
}

struct AtlasPlacement: Equatable {
    var purpose: String
    var column: Int
    var row: Int
    var atlas: SpriteAtlasKind
    var consistencyGroup: String?
}

enum GeneratedImageIssue: String, Equatable {
    case opaqueBackground = "opaque_background"
    case empty
    case clipped
    case duplicate
    case height
    case cellEdge = "cell_edge"
    case cellOccupancy = "cell_occupancy"
    case atlasSize = "atlas_size"
    case unreadable
}

enum CustomPetLayout {
    /// Stable order. `spriteSets` is a dictionary and must not be enumerated for layout.
    static let animationOrder: [Anim] = [
        .idle, .alert, .tired, .sleeping, .scratchSelf,
        .scratchWallN, .scratchWallS, .scratchWallE, .scratchWallW,
        .N, .NE, .E, .SE, .S, .SW, .W, .NW
    ]

    static func placements(includeWalkAtlas: Bool) -> [AtlasPlacement] {
        var placements: [AtlasPlacement] = []
        let walkDirections = Set(PetAnimationTiming.walkingDirections)
        for animation in animationOrder {
            guard let frames = spriteSets[animation] else { continue }
            let walks = walkDirections.contains(animation)
            for (index, cell) in frames.enumerated() {
                let purpose: String
                let group: String?
                if includeWalkAtlas && walks {
                    let phase = index == 0 ? 0 : 2
                    purpose = "gait_\(animation.rawValue)_\(phase)"
                    group = "gait_\(animation.rawValue)"
                } else {
                    purpose = "\(animation.rawValue)_\(index)"
                    group = frames.count > 1 ? animation.rawValue : nil
                }
                placements.append(AtlasPlacement(
                    purpose: purpose,
                    column: cell.0,
                    row: cell.1,
                    atlas: .main,
                    consistencyGroup: group
                ))
            }
        }
        if includeWalkAtlas {
            for (row, animation) in PetAnimationTiming.walkingDirections.enumerated() {
                for phase in 0..<4 {
                    placements.append(AtlasPlacement(
                        purpose: "gait_\(animation.rawValue)_\(phase)",
                        column: phase,
                        row: row,
                        atlas: .walk,
                        consistencyGroup: "gait_\(animation.rawValue)"
                    ))
                }
            }
        }
        return placements
    }

    /// Provider calls, including the character reference sheet.
    static func purposes(includeWalkAtlas: Bool) -> [String] {
        var purposes = ["reference"]
        var seen: Set<String> = []
        for placement in placements(includeWalkAtlas: includeWalkAtlas) where seen.insert(placement.purpose).inserted {
            purposes.append(placement.purpose)
        }
        return purposes
    }

    static func consistencyGroups(includeWalkAtlas: Bool) -> [String: [String]] {
        var groups: [String: [String]] = [:]
        var seen: Set<String> = []
        for placement in placements(includeWalkAtlas: includeWalkAtlas) {
            guard let group = placement.consistencyGroup, seen.insert(placement.purpose).inserted else { continue }
            groups[group, default: []].append(placement.purpose)
        }
        return groups.filter { $0.value.count >= 2 }
    }
}

enum AtlasPackError: Error, Equatable {
    case missing(String)
    case unreadable(String)
    case overflow(String)
    case encodeFailed
}

enum SpriteAtlasAssembler {
    static let cellSize = 64
    static let anchorX = 32.0
    static let anchorY = 60.0
    /// Largest ink extent that still leaves a transparent margin inside a 64 px cell,
    /// including a pixel of slack for integer rounding around the (32, 60) anchor.
    static let maxInkExtent = 50.0

    static func pack(framePNGs: [String: Data], includeWalkAtlas: Bool) throws -> (mainPNG: Data, walkPNG: Data?) {
        let placements = CustomPetLayout.placements(includeWalkAtlas: includeWalkAtlas)
        var images: [String: CGImage] = [:]
        for placement in placements {
            if images[placement.purpose] != nil { continue }
            guard let data = framePNGs[placement.purpose] else { throw AtlasPackError.missing(placement.purpose) }
            guard let image = RGBAImageCodec.cgImage(data: data) else { throw AtlasPackError.unreadable(placement.purpose) }
            images[placement.purpose] = image
        }
        let sharedScale = try sharedScale(images)
        let main = try draw(
            width: 512,
            height: 256,
            placements: placements.filter { $0.atlas == .main },
            images: images,
            scale: sharedScale
        )
        guard let mainPNG = RGBAImageCodec.pngData(main) else { throw AtlasPackError.encodeFailed }
        guard includeWalkAtlas else { return (mainPNG, nil) }
        let walk = try draw(
            width: 256,
            height: 512,
            placements: placements.filter { $0.atlas == .walk },
            images: images,
            scale: sharedScale
        )
        guard let walkPNG = RGBAImageCodec.pngData(walk) else { throw AtlasPackError.encodeFailed }
        return (mainPNG, walkPNG)
    }

    static func sharedScale(_ images: [String: CGImage]) throws -> Double {
        var scale = Double.greatestFiniteMagnitude
        for (purpose, image) in images {
            guard let ink = InkMeasurement.box(of: image), ink.width > 0, ink.height > 0 else {
                throw AtlasPackError.unreadable(purpose)
            }
            scale = min(scale, maxInkExtent / Double(ink.width), maxInkExtent / Double(ink.height))
        }
        guard scale.isFinite, scale > 0 else { throw AtlasPackError.encodeFailed }
        return scale
    }

    private static func draw(
        width: Int,
        height: Int,
        placements: [AtlasPlacement],
        images: [String: CGImage],
        scale: Double
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw AtlasPackError.encodeFailed }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        for placement in placements {
            guard let image = images[placement.purpose],
                  let ink = InkMeasurement.box(of: image) else {
                throw AtlasPackError.missing(placement.purpose)
            }
            guard let cropped = image.cropping(to: ink.cgRect),
                  let placed = place(cropped, ink: ink, placement: placement, scale: scale) else {
                throw AtlasPackError.overflow(placement.purpose)
            }
            let destination = CGRect(
                x: placed.x,
                y: CGFloat(height) - placed.top - placed.height,
                width: placed.width,
                height: placed.height
            )
            let minX = Int(destination.minX.rounded())
            let minY = Int(destination.minY.rounded())
            let maxX = minX + Int(placed.width.rounded())
            let maxY = minY + Int(placed.height.rounded())
            let cellMinX = placement.column * cellSize
            let cellMinY = height - (placement.row + 1) * cellSize
            guard minX >= cellMinX, maxX <= cellMinX + cellSize,
                  minY >= cellMinY, maxY <= cellMinY + cellSize else {
                throw AtlasPackError.overflow(placement.purpose)
            }
            context.draw(placed.image, in: destination)
        }
        guard let image = context.makeImage() else { throw AtlasPackError.encodeFailed }
        return image
    }

    private struct PlacedSprite {
        var image: CGImage
        var x: CGFloat
        var top: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private static func place(
        _ cropped: CGImage,
        ink: InkBox,
        placement: AtlasPlacement,
        scale: Double
    ) -> PlacedSprite? {
        let width = max(1, Int((Double(ink.width) * scale).rounded()))
        let height = max(1, Int((Double(ink.height) * scale).rounded()))
        guard let scaled = RGBAImageCodec.scaleNearest(cropped, width: width, height: height) else { return nil }
        let left = (Double(placement.column * cellSize) + anchorX + (Double(ink.minX) - ink.centerX) * scale).rounded()
        let top = (Double(placement.row * cellSize) + anchorY + (Double(ink.minY) - ink.bottom) * scale).rounded()
        return PlacedSprite(image: scaled, x: left, top: top, width: CGFloat(width), height: CGFloat(height))
    }
}

enum SpriteValidator {
    static func inspectGenerated(_ image: CGImage) -> [GeneratedImageIssue] {
        let width = image.width
        let height = image.height
        guard width > 8, height > 8 else { return [.empty] }
        let pixels = RGBAImageCodec.pixelsTopLeft(image)
        let count = width * height
        var opaque = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 127 {
            opaque += 1
        }
        if opaque < 80 || Double(opaque) / Double(count) < 0.002 { return [.empty] }

        let corners = [
            pixels[3],
            pixels[(width - 1) * 4 + 3],
            pixels[((height - 1) * width) * 4 + 3],
            pixels[((height - 1) * width + width - 1) * 4 + 3]
        ]
        var borderOpaque = 0
        var borderCount = 0
        let border = max(1, min(width, height) / 50)
        for y in 0..<height {
            for x in 0..<width where x < border || y < border || x >= width - border || y >= height - border {
                borderCount += 1
                if pixels[(y * width + x) * 4 + 3] > 200 { borderOpaque += 1 }
            }
        }
        let borderRatio = borderCount == 0 ? 0 : Double(borderOpaque) / Double(borderCount)
        if corners.allSatisfy({ $0 > 250 }) && Double(opaque) / Double(count) > 0.7 {
            return [.opaqueBackground]
        }
        if borderRatio > 0.85 { return [.opaqueBackground] }

        guard let ink = InkMeasurement.box(of: image) else { return [.empty] }
        if ink.minX <= 1 || ink.minY <= 1 || ink.maxX >= width - 1 || ink.maxY >= height - 1 {
            return [.clipped]
        }
        return []
    }

    /// Rejects identical pairs and, for gait groups, near-copies. Sleeping frames may differ only slightly.
    static func consistencyIssues(
        group: String,
        frames: [(purpose: String, image: CGImage)]
    ) -> (purpose: String, issue: GeneratedImageIssue)? {
        guard frames.count >= 2 else { return nil }
        let ordered = frames.sorted { $0.purpose < $1.purpose }
        for index in 1..<ordered.count {
            let previous = ordered[index - 1]
            let current = ordered[index]
            let ratio = differenceRatio(previous.image, current.image)
            if group.hasPrefix("gait_") {
                if ratio < 0.02 { return (current.purpose, .duplicate) }
            } else if ratio == 0 && imagesLookIdentical(previous.image, current.image) {
                return (current.purpose, .duplicate)
            }
        }
        let heights = ordered.compactMap { frame -> (String, Int)? in
            guard let ink = InkMeasurement.box(of: frame.image), ink.height > 0 else { return nil }
            return (frame.purpose, ink.height)
        }
        guard heights.count == ordered.count else { return (ordered[0].purpose, .empty) }
        let sortedHeights = heights.map(\.1).sorted()
        let median = sortedHeights[sortedHeights.count / 2]
        guard median > 0 else { return (ordered[0].purpose, .empty) }
        var worst: (String, Double)?
        for (purpose, height) in heights {
            let ratio = Double(height) / Double(median)
            let distance = abs(ratio - 1)
            if ratio < 0.85 || ratio > 1.15, distance > (worst?.1 ?? 0) {
                worst = (purpose, distance)
            }
        }
        if let worst { return (worst.0, .height) }
        return nil
    }

    static func inspectAtlas(_ image: CGImage, kind: SpriteAtlasKind, includeWalkAtlas: Bool) -> [(purpose: String, issue: GeneratedImageIssue)] {
        let expectedWidth = kind == .main ? 512 : 256
        let expectedHeight = kind == .main ? 256 : 512
        guard image.width == expectedWidth, image.height == expectedHeight else {
            return [("atlas", .atlasSize)]
        }
        let placements = CustomPetLayout.placements(includeWalkAtlas: includeWalkAtlas)
            .filter { $0.atlas == kind }
        var failures: [(String, GeneratedImageIssue)] = []
        var seenCells: [String: [UInt8]] = [:]
        for placement in placements {
            let rect = CGRect(
                x: placement.column * SpriteAtlasAssembler.cellSize,
                y: placement.row * SpriteAtlasAssembler.cellSize,
                width: SpriteAtlasAssembler.cellSize,
                height: SpriteAtlasAssembler.cellSize
            )
            guard let cell = image.cropping(to: rect) else {
                failures.append((placement.purpose, .unreadable))
                continue
            }
            let pixels = RGBAImageCodec.pixelsTopLeft(cell)
            let opaque = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 127 }.count
            if opaque < 80 || opaque > 3600 {
                failures.append((placement.purpose, .cellOccupancy))
            }
            let size = SpriteAtlasAssembler.cellSize
            var touchesEdge = false
            for y in 0..<size {
                for x in 0..<size where x == 0 || y == 0 || x == size - 1 || y == size - 1 {
                    if pixels[(y * size + x) * 4 + 3] >= 16 { touchesEdge = true }
                }
            }
            if touchesEdge { failures.append((placement.purpose, .cellEdge)) }
            let key = placement.consistencyGroup ?? placement.purpose
            if let previous = seenCells[key], previous == pixels, placement.consistencyGroup != nil {
                failures.append((placement.purpose, .duplicate))
            }
            seenCells[key] = pixels
        }
        return failures
    }

    static func imagesLookIdentical(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return false }
        return RGBAImageCodec.pixelsTopLeft(lhs) == RGBAImageCodec.pixelsTopLeft(rhs)
    }

    static func differenceRatio(_ lhs: CGImage, _ rhs: CGImage) -> Double {
        guard let left = RGBAImageCodec.scaleNearest(lhs, width: 32, height: 32),
              let right = RGBAImageCodec.scaleNearest(rhs, width: 32, height: 32) else { return 0 }
        let a = RGBAImageCodec.pixelsTopLeft(left)
        let b = RGBAImageCodec.pixelsTopLeft(right)
        var different = 0
        for index in stride(from: 0, to: a.count, by: 4) {
            let delta = abs(Int(a[index]) - Int(b[index]))
                + abs(Int(a[index + 1]) - Int(b[index + 1]))
                + abs(Int(a[index + 2]) - Int(b[index + 2]))
                + abs(Int(a[index + 3]) - Int(b[index + 3]))
            if delta > 24 { different += 1 }
        }
        return Double(different) / Double(32 * 32)
    }
}
