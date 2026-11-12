import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Top-left, premultiplied RGBA. Row 0 is the top of the image, matching CGImage cropping.
struct RGBAImage: Equatable {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[offset(x, y) + 3] }
}

enum RGBAImageCodec {
    /// Reads pixels in CGImage top-left order. The vertical flip matches the usual
    /// bitmap-context recipe so buffer row 0 is the top row `CGImage.cropping` uses.
    static func pixelsTopLeft(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return pixels }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    static func cgImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage? {
        guard pixels.count == width * height * 4,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func cgImage(data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) >= 1 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func pngData(width: Int, height: Int, pixels: [UInt8]) -> Data? {
        guard let image = cgImage(width: width, height: height, pixels: pixels) else { return nil }
        return pngData(image)
    }

    /// Nearest-neighbor scale into a new top-left image. Used when packing cells.
    static func scaleNearest(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, image.width > 0, image.height > 0 else { return nil }
        let source = pixelsTopLeft(image)
        let sourceWidth = image.width
        let sourceHeight = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let sourceY = min(sourceHeight - 1, y * sourceHeight / height)
            for x in 0..<width {
                let sourceX = min(sourceWidth - 1, x * sourceWidth / width)
                let from = (sourceY * sourceWidth + sourceX) * 4
                let to = (y * width + x) * 4
                pixels[to] = source[from]
                pixels[to + 1] = source[from + 1]
                pixels[to + 2] = source[from + 2]
                pixels[to + 3] = source[from + 3]
            }
        }
        return cgImage(width: width, height: height, pixels: pixels)
    }
}

struct InkBox: Equatable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var width: Int { maxX - minX }
    var height: Int { maxY - minY }
    /// Exclusive-edge center, same convention as `crop-manifest.json`.
    var centerX: Double { (Double(minX) + Double(maxX)) / 2 }
    var bottom: Double { Double(maxY) }

    var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}

enum InkMeasurement {
    static func box(of image: CGImage, alphaThreshold: UInt8 = 16) -> InkBox? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let pixels = RGBAImageCodec.pixelsTopLeft(image)
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * width + x) * 4 + 3]
                guard alpha > alphaThreshold else { continue }
                found = true
                if x < minX { minX = x }
                if y < minY { minY = y }
                if x + 1 > maxX { maxX = x + 1 }
                if y + 1 > maxY { maxY = y + 1 }
            }
        }
        guard found else { return nil }
        return InkBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}

enum PhotoPrepIssue: Error, Equatable {
    case tooFew(selected: Int, minimum: Int)
    case tooMany(selected: Int, maximum: Int)
    case unreadable(String)
    case unsupported(String)
    case tooLarge(String)
    case tooSmall(file: String, shortest: Int, minimum: Int)
    case extremeAspect(String)
    case tooBlurry(String)
    case mostlyEmpty(String)
}

struct PreparedPhoto: Equatable, Identifiable {
    var id: Int
    var filename: String
    var pngData: Data
    var width: Int
    var height: Int
}

enum PhotoPreprocessor {
    static let minimumEdge = 256
    static let maximumLongEdge = 1024
    static let minimumCount = 3
    static let maximumCount = 5
    static let maximumBytes = 25 * 1024 * 1024
    static let maximumAspect = 3.0
    static let minimumBlurScore = 8.0
    static let minimumLuminanceStdDev = 6.0

    static func prepare(_ files: [(name: String, data: Data)]) -> (photos: [PreparedPhoto], issues: [PhotoPrepIssue]) {
        var issues: [PhotoPrepIssue] = []
        if files.count < minimumCount {
            issues.append(.tooFew(selected: files.count, minimum: minimumCount))
        }
        if files.count > maximumCount {
            issues.append(.tooMany(selected: files.count, maximum: maximumCount))
        }

        var photos: [PreparedPhoto] = []
        for file in files.prefix(maximumCount) {
            switch prepareOne(name: file.name, data: file.data) {
            case .success(let photo):
                var indexed = photo
                indexed.id = photos.count
                photos.append(indexed)
            case .failure(let issue):
                issues.append(issue)
            }
        }
        return (photos, issues)
    }

    static func isReady(_ result: (photos: [PreparedPhoto], issues: [PhotoPrepIssue])) -> Bool {
        result.issues.isEmpty && (minimumCount...maximumCount).contains(result.photos.count)
    }

    private static func prepareOne(name: String, data: Data) -> Result<PreparedPhoto, PhotoPrepIssue> {
        if data.count > maximumBytes { return .failure(.tooLarge(name)) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return .failure(.unreadable(name))
        }
        guard let type = CGImageSourceGetType(source) as String? else {
            return .failure(.unreadable(name))
        }
        guard isAllowedImageType(type) else { return .failure(.unsupported(name)) }
        guard let oriented = orientedImage(source) else { return .failure(.unreadable(name)) }

        let pixelSize = orientedPixelSize(source) ?? (oriented.width, oriented.height)
        let shortest = min(pixelSize.0, pixelSize.1)
        let longest = max(pixelSize.0, pixelSize.1)
        if shortest < minimumEdge {
            return .failure(.tooSmall(file: name, shortest: shortest, minimum: minimumEdge))
        }
        if Double(longest) / Double(max(shortest, 1)) > maximumAspect {
            return .failure(.extremeAspect(name))
        }

        let sample = resized(oriented, longEdge: 64, interpolation: .medium) ?? oriented
        let samplePixels = RGBAImageCodec.pixelsTopLeft(sample)
        if blurScore(samplePixels, width: sample.width, height: sample.height) < minimumBlurScore {
            return .failure(.tooBlurry(name))
        }
        if luminanceStdDev(samplePixels, width: sample.width, height: sample.height) < minimumLuminanceStdDev {
            return .failure(.mostlyEmpty(name))
        }

        let uploadSource = longest > maximumLongEdge
            ? (resized(oriented, longEdge: maximumLongEdge, interpolation: .high) ?? oriented)
            : oriented
        guard let png = RGBAImageCodec.pngData(uploadSource) else { return .failure(.unreadable(name)) }
        return .success(PreparedPhoto(
            id: 0,
            filename: name,
            pngData: png,
            width: uploadSource.width,
            height: uploadSource.height
        ))
    }

    static func isAllowedImageType(_ type: String) -> Bool {
        let value = type.lowercased()
        let allowed = [
            "public.jpeg", "public.png", "public.heic", "public.heif", "public.gif",
            "public.tiff", "public.webp", "org.webmproject.webp", "public.jpeg-2000"
        ]
        return allowed.contains(value) || value.contains("jpeg") || value.contains("png")
            || value.contains("heic") || value.contains("webp") || value.contains("tiff")
            || value.contains("gif")
    }

    private static func orientedImage(_ source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 8192,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func orientedPixelSize(_ source: CGImageSource) -> (Int, Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = intValue(properties[kCGImagePropertyPixelWidth]),
              let height = intValue(properties[kCGImagePropertyPixelHeight]) else { return nil }
        let orientation = intValue(properties[kCGImagePropertyOrientation]) ?? 1
        if [5, 6, 7, 8].contains(orientation) { return (height, width) }
        return (width, height)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    static func resized(_ image: CGImage, longEdge: Int, interpolation: CGInterpolationQuality) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > 0, longEdge > 0 else { return nil }
        let scale = Double(longEdge) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = interpolation
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func blurScore(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width > 2, height > 2 else { return 0 }
        var values: [Double] = []
        values.reserveCapacity((width - 2) * (height - 2))
        func gray(_ x: Int, _ y: Int) -> Double {
            let index = (y * width + x) * 4
            return (Double(pixels[index]) + Double(pixels[index + 1]) + Double(pixels[index + 2])) / 3
        }
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = gray(x, y)
                let laplacian = 4 * center - gray(x - 1, y) - gray(x + 1, y) - gray(x, y - 1) - gray(x, y + 1)
                values.append(laplacian)
            }
        }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance
    }

    static func luminanceStdDev(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        let count = width * height
        guard count > 0 else { return 0 }
        var sum = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            sum += (Double(pixels[index]) + Double(pixels[index + 1]) + Double(pixels[index + 2])) / 3
        }
        let mean = sum / Double(count)
        var variance = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let gray = (Double(pixels[index]) + Double(pixels[index + 1]) + Double(pixels[index + 2])) / 3
            variance += (gray - mean) * (gray - mean)
        }
        return (variance / Double(count)).squareRoot()
    }
}
