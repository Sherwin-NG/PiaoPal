import Foundation
import ImageIO
import CoreGraphics
import Metal

func containsBytes(_ data: Data, _ pattern: Data) -> Bool {
    guard !pattern.isEmpty, pattern.count <= data.count else { return pattern.isEmpty }
    let bytes = Array(data)
    let needle = Array(pattern)
    for start in 0...(bytes.count - needle.count) where bytes[start..<(start + needle.count)].elementsEqual(needle) {
        return true
    }
    return false
}

func expect(_ condition: Bool, _ message: String = "expectation failed") {
    if !condition { fatalError(message) }
}

func awaitResult<T>(_ body: @escaping () async -> T) -> T {
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        box.value = await body()
        semaphore.signal()
    }
    semaphore.wait()
    return box.value!
}

final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

func fill(_ pixels: inout [UInt8], width: Int, x0: Int, y0: Int, x1: Int, y1: Int, color: (UInt8, UInt8, UInt8, UInt8)) {
    for y in y0..<y1 {
        for x in x0..<x1 where x >= 0 && y >= 0 && x < width {
            let index = (y * width + x) * 4
            guard index + 3 < pixels.count else { continue }
            pixels[index] = color.0
            pixels[index + 1] = color.1
            pixels[index + 2] = color.2
            pixels[index + 3] = color.3
        }
    }
}

func png(width: Int, height: Int, _ paint: (inout [UInt8]) -> Void) -> Data {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    paint(&pixels)
    guard let data = RGBAImageCodec.pngData(width: width, height: height, pixels: pixels) else {
        fatalError("Could not encode PNG")
    }
    return data
}

func petFrame(phase: Int) -> Data {
    png(width: 180, height: 180) { pixels in
        fill(&pixels, width: 180, x0: 40, y0: 30, x1: 140, y1: 140, color: (40, 40, 40, 255))
        let origins = [(50, 40), (90, 40), (50, 80), (90, 80)]
        let origin = origins[phase % 4]
        fill(&pixels, width: 180, x0: origin.0, y0: origin.1, x1: origin.0 + 36, y1: origin.1 + 50, color: (220, 30, 30, 255))
    }
}

func solidPNG(size: Int, alpha: UInt8) -> Data {
    png(width: size, height: size) { pixels in
        fill(&pixels, width: size, x0: 0, y0: 0, x1: size, y1: size, color: (240, 240, 240, alpha))
    }
}

func photoPNG(width: Int, height: Int, solid: Bool) -> Data {
    png(width: width, height: height) { pixels in
        let background: (UInt8, UInt8, UInt8, UInt8) = solid ? (180, 180, 180, 255) : (230, 230, 230, 255)
        fill(&pixels, width: width, x0: 0, y0: 0, x1: width, y1: height, color: background)
        if !solid {
            fill(&pixels, width: width, x0: width / 5, y0: height / 6, x1: width * 4 / 5, y1: height * 5 / 6, color: (20, 20, 20, 255))
        }
    }
}

// Pixel order matches CGImage top-left cropping.
do {
    let source = png(width: 4, height: 4) { pixels in
        pixels[0] = 255
        pixels[3] = 255
        let green = (2 * 4 + 1) * 4
        pixels[green + 1] = 255
        pixels[green + 3] = 255
    }
    let image = RGBAImageCodec.cgImage(data: source)!
    let read = RGBAImageCodec.pixelsTopLeft(image)
    expect(read[0] == 255 && read[3] == 255, "top-left pixel was not preserved r=\(read[0]) a=\(read[3]) g=\(read[1]) b=\(read[2])")
    let green = (2 * 4 + 1) * 4
    expect(read[green + 1] == 255, "pixel (1,2) was not preserved g=\(read[green + 1]) a=\(read[green + 3])")
    let cropped = image.cropping(to: CGRect(x: 1, y: 2, width: 1, height: 1))!
    let croppedPixels = RGBAImageCodec.pixelsTopLeft(cropped)
    expect(croppedPixels[1] == 255, "CGImage crop and pixel reader disagree")
}
print("PASS: top-left pixel order")

// Photos.
do {
    let good = (name: "a.png", data: photoPNG(width: 400, height: 400, solid: false))
    let ready = PhotoPreprocessor.prepare([good, good, good])
    expect(PhotoPreprocessor.isReady(ready), "three clear photos should be accepted")
    expect(ready.photos.count == 3, "expected 3 prepared photos")
    expect(ready.photos[0].width <= PhotoPreprocessor.maximumLongEdge, "upload image should be bounded")

    let few = PhotoPreprocessor.prepare([good, good])
    expect(few.issues.contains { if case .tooFew = $0 { return true }; return false }, "two photos are too few")

    let many = PhotoPreprocessor.prepare(Array(repeating: good, count: 6))
    expect(many.issues.contains { if case .tooMany = $0 { return true }; return false }, "six photos are too many")

    let small = PhotoPreprocessor.prepare([
        good, good, (name: "small.png", data: photoPNG(width: 100, height: 120, solid: false))
    ])
    expect(small.issues.contains { if case .tooSmall = $0 { return true }; return false }, "short edge must be rejected")

    let wide = PhotoPreprocessor.prepare([
        good, good, (name: "wide.png", data: photoPNG(width: 1200, height: 300, solid: false))
    ])
    expect(wide.issues.contains { if case .extremeAspect = $0 { return true }; return false }, "extreme aspect must be rejected")

    let blur = PhotoPreprocessor.prepare([
        good, good, (name: "flat.png", data: photoPNG(width: 400, height: 400, solid: true))
    ])
    expect(blur.issues.contains { if case .tooBlurry = $0 { return true }; return false }, "a flat image must be rejected")

    let junk = PhotoPreprocessor.prepare([
        good, good, (name: "notes.txt", data: Data("not an image".utf8))
    ])
    expect(junk.issues.contains { if case .unreadable = $0 { return true }; return false }, "garbage must be unreadable")

    let huge = PhotoPreprocessor.prepare([
        good, good, (name: "big.bin", data: Data(count: PhotoPreprocessor.maximumBytes + 1))
    ])
    expect(huge.issues.contains { if case .tooLarge = $0 { return true }; return false }, "oversized files must be rejected")

    let taggedImage = RGBAImageCodec.cgImage(data: photoPNG(width: 2000, height: 1500, solid: false))!
    let taggedStorage = NSMutableData()
    let destination = CGImageDestinationCreateWithData(taggedStorage, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, taggedImage, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "SECRET_GPS_TAG"]
    ] as CFDictionary)
    expect(CGImageDestinationFinalize(destination), "could not write a tagged PNG")
    let tagged = taggedStorage as Data
    let stripped = PhotoPreprocessor.prepare([(name: "tagged.png", data: tagged), good, good])
    expect(PhotoPreprocessor.isReady(stripped), "a photo with a text chunk must still be accepted")
    if containsBytes(tagged, Data("SECRET_GPS_TAG".utf8)) {
        expect(!containsBytes(stripped.photos[0].pngData, Data("SECRET_GPS_TAG".utf8)), "re-encoded photo must drop the tag")
    }
    let uploaded = RGBAImageCodec.cgImage(data: stripped.photos[0].pngData)!
    expect(max(uploaded.width, uploaded.height) == PhotoPreprocessor.maximumLongEdge, "long edge should be \(uploaded.width)x\(uploaded.height)")
}
print("PASS: photo checks, metadata strip, and size limit")

// Layout matches the production sprite grid.
do {
    expect(Set(CustomPetLayout.animationOrder) == Set(spriteSets.keys), "every animation needs a slot")
    let main = CustomPetLayout.placements(includeWalkAtlas: false)
    expect(main.count == 32, "main atlas has 32 cells")
    expect(Set(main.map { $0.column * 8 + $0.row }).count == 32, "main cells must be unique")
    for (animation, frames) in spriteSets {
        for (index, cell) in frames.enumerated() {
            let purpose = "\(animation.rawValue)_\(index)"
            expect(main.contains { $0.purpose == purpose && $0.column == cell.0 && $0.row == cell.1 }, "missing \(purpose)")
        }
    }
    expect(CustomPetLayout.purposes(includeWalkAtlas: false).count == 33, "reference plus 32 frames")
    expect(CustomPetLayout.purposes(includeWalkAtlas: true).count == 49, "reference plus poses plus four-frame gait")
    let walk = CustomPetLayout.placements(includeWalkAtlas: true).filter { $0.atlas == .walk }
    expect(walk.count == 32, "walk atlas has 32 cells")
    expect(walk.contains { $0.purpose == "gait_N_0" && $0.row == 0 && $0.column == 0 }, "N is the first walk row")
    expect(PetAnimationTiming.walkingDirections[2] == .E)
    expect(walk.contains { $0.purpose == "gait_E_3" && $0.row == 2 && $0.column == 3 }, "E is the third walk row")
    let east = spriteSets[.E]![0]
    let copied = CustomPetLayout.placements(includeWalkAtlas: true).filter {
        $0.atlas == .main && $0.column == east.0 && $0.row == east.1
    }
    expect(copied.first?.purpose == "gait_E_0", "main atlas borrows gait phases")
    expect(CustomPetCost.requestCount(includeWalkAtlas: true) == 49)
    expect(CustomPetCost.estimatedUSD(includeWalkAtlas: true, quality: "medium") == 49 * 0.042)
}
print("PASS: sprite layout and cost hint")

// Prompts cover every frame and keep directions distinct.
do {
    for purpose in CustomPetLayout.purposes(includeWalkAtlas: true) {
        let prompt = CustomPetPrompts.text(purpose: purpose, attempt: 1, previousFailure: nil)
        expect(prompt.contains("alpha 0"), "\(purpose) must require transparency")
        expect(!prompt.isEmpty, "empty prompt")
    }
    let east = CustomPetPrompts.poseLine("gait_E_0")
    let west = CustomPetPrompts.poseLine("gait_W_0")
    expect(east != west, "east and west prompts must differ")
    let retry = CustomPetPrompts.text(purpose: "idle_0", attempt: 2, previousFailure: "clipped")
    expect(retry.contains("clipped"), "retry prompt must mention the failure")
}
print("PASS: prompts")

// Provider request building never puts the key in the body.
do {
    expect(CustomPetProviderSettings.allowedBaseURL("https://api.openai.com/v1") != nil)
    expect(CustomPetProviderSettings.allowedBaseURL("https://api.openai.com/v1/") != nil)
    expect(CustomPetProviderSettings.allowedBaseURL("http://127.0.0.1:8080/v1") != nil)
    expect(CustomPetProviderSettings.allowedBaseURL("http://localhost/v1") != nil)
    expect(CustomPetProviderSettings.allowedBaseURL("http://evil.example/v1") == nil)
    expect(CustomPetProviderSettings.allowedBaseURL("ftp://api.openai.com") == nil)
    var settings = CustomPetProviderSettings.default
    expect(settings.validated() != nil)
    settings.model = "gpt image"
    expect(settings.validated() == nil)
    settings = CustomPetProviderSettings.default
    settings.quality = "ultra"
    expect(settings.validated() == nil)

    let key = "sk-secret-value"
    let request = OpenAIImageRequest.make(
        baseURL: URL(string: "https://api.openai.com/v1/")!,
        apiKey: key,
        model: "gpt-image-1",
        prompt: "one sprite",
        images: [petFrame(phase: 0), petFrame(phase: 1)],
        quality: "medium",
        size: "1024x1024"
    )
    expect(request.url?.absoluteString == "https://api.openai.com/v1/images/edits", "endpoint should drop the trailing slash")
    expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
    let body = request.httpBody ?? Data()
    expect(!containsBytes(body, Data(key.utf8)), "API key must not be copied into the body")
    let text = String(decoding: body, as: UTF8.self)
    expect(text.contains("name=\"model\""), "missing model field")
    expect(text.contains("gpt-image-1"), "missing model value")
    expect(text.contains("name=\"background\""), "missing background field")
    expect(text.contains("transparent"), "background must be transparent")
    expect(text.contains("name=\"output_format\""), "missing output format")
    expect(text.contains("ref0.png") && text.contains("ref1.png"), "both reference images should be attached")

    let encoded = Data("hello".utf8).base64EncodedString()
    let ok = try OpenAIImageRequest.parse(
        status: 200,
        body: Data("{\"data\":[{\"b64_json\":\"\(encoded)\"}]}".utf8),
        redact: key
    )
    expect(ok == Data("hello".utf8), "base64 image was not decoded")

    do {
        _ = try OpenAIImageRequest.parse(
            status: 400,
            body: Data("{\"error\":{\"message\":\"blocked sk-secret-value\",\"code\":\"moderation_blocked\"}}".utf8),
            redact: key
        )
        fatalError("moderation response must throw")
    } catch let error as PetImageProviderError {
        guard case .transport(let retryable, let status, let moderated, let message) = error else {
            fatalError("unexpected provider error")
        }
        expect(!retryable && status == 400 && moderated, "moderation must not be retried")
        expect(!message.contains(key) && message.contains("••••"), "provider errors must redact the key")
    }

    do {
        _ = try OpenAIImageRequest.parse(
            status: 429,
            body: Data("{\"error\":{\"message\":\"rate limit\",\"code\":\"rate_limit_exceeded\"}}".utf8),
            redact: key
        )
        fatalError("rate limit must throw")
    } catch let error as PetImageProviderError {
        guard case .transport(let retryable, _, let moderated, _) = error else { fatalError("unexpected error") }
        expect(retryable && !moderated, "429 should be retryable")
    }
} catch {
    fatalError("provider response test failed: \(error)")
}
print("PASS: provider settings, request body, and response parsing")

final class ScriptedImageProvider: PetImageGenerating {
    var calls: [String] = []
    var failuresRemaining: [String: Int] = [:]
    var moderated: Set<String> = []

    func generateImage(_ request: PetImageRequest) async throws -> Data {
        calls.append(request.purpose)
        if moderated.contains(request.purpose) {
            throw PetImageProviderError.transport(retryable: false, status: 400, moderated: true, message: "moderation")
        }
        if let remaining = failuresRemaining[request.purpose], remaining > 0 {
            failuresRemaining[request.purpose] = remaining - 1
            return solidPNG(size: 180, alpha: 255)
        }
        let phase = Int(request.purpose.split(separator: "_").last ?? "0") ?? 0
        return petFrame(phase: phase)
    }
}

func runPipeline(_ provider: ScriptedImageProvider, includeWalk: Bool, existing: [String: Data] = [:]) -> CustomPetPipelineResult {
    let photos = (0..<3).map { index in
        PreparedPhoto(id: index, filename: "pet-\(index).png", pngData: photoPNG(width: 400, height: 400, solid: false), width: 400, height: 400)
    }
    let pipeline = CustomPetPipeline(provider: provider, photos: photos)
    return awaitResult {
        await pipeline.run(includeWalkAtlas: includeWalk, existing: existing)
    }
}

do {
    let provider = ScriptedImageProvider()
    let result = runPipeline(provider, includeWalk: true)
    expect(result.mainPNG != nil && result.walkPNG != nil && result.failures.isEmpty, "a valid provider should produce both atlases: \(result.failures)")
    expect(provider.calls.count == 49, "expected one call per frame, got \(provider.calls.count)")
    let main = RGBAImageCodec.cgImage(data: result.mainPNG!)!
    let walk = RGBAImageCodec.cgImage(data: result.walkPNG!)!
    expect(SpriteValidator.inspectAtlas(main, kind: .main, includeWalkAtlas: true).isEmpty, "main atlas failed validation")
    expect(SpriteValidator.inspectAtlas(walk, kind: .walk, includeWalkAtlas: true).isEmpty, "walk atlas failed validation")
    expect(main.width == 512 && main.height == 256)
    expect(walk.width == 256 && walk.height == 512)
}
print("PASS: pipeline packs a validated atlas")

do {
    let provider = ScriptedImageProvider()
    provider.failuresRemaining["gait_E_1"] = 1
    let result = runPipeline(provider, includeWalk: true)
    expect(result.mainPNG != nil, "one rejected frame should be retried")
    expect(result.attempts["gait_E_1"] == 2, "the bad frame should be generated twice")
    expect(provider.calls.filter { $0 == "gait_E_1" }.count == 2)
}
print("PASS: failed frames are retried without discarding the run")

do {
    let provider = ScriptedImageProvider()
    provider.moderated = ["reference"]
    let result = runPipeline(provider, includeWalk: true)
    expect(result.mainPNG == nil, "moderation must not save a pet")
    expect(result.failures["reference"] == "moderation")
    expect(provider.calls == ["reference"], "moderation must stop the run")
}
print("PASS: moderation stops without further requests")

// Anchor: the colored feet of the idle sprite sit at the bottom of cell (3, 3).
do {
    func marked(redFeet: Bool) -> Data {
        png(width: 80, height: 80) { pixels in
            fill(&pixels, width: 80, x0: 20, y0: 16, x1: 52, y1: 56, color: (0, 0, 255, 255))
            if redFeet {
                fill(&pixels, width: 80, x0: 20, y0: 55, x1: 52, y1: 56, color: (255, 0, 0, 255))
            }
        }
    }
    var frames: [String: Data] = [:]
    for purpose in CustomPetLayout.purposes(includeWalkAtlas: false) where purpose != "reference" {
        frames[purpose] = marked(redFeet: purpose == "idle_0")
    }
    let packed = try SpriteAtlasAssembler.pack(framePNGs: frames, includeWalkAtlas: false)
    let atlas = RGBAImageCodec.cgImage(data: packed.mainPNG)!
    expect(atlas.width == 512 && atlas.height == 256, "main atlas size")
    let idle = atlas.cropping(to: CGRect(x: 3 * 64, y: 3 * 64, width: 64, height: 64))!
    let pixels = RGBAImageCodec.pixelsTopLeft(idle)
    var redMinY = 64
    var sawRed = false
    for y in 0..<64 {
        for x in 0..<64 {
            let index = (y * 64 + x) * 4
            let red = pixels[index] > 200 && pixels[index + 2] < 40 && pixels[index + 3] > 200
            if red {
                sawRed = true
                redMinY = min(redMinY, y)
            }
            if x == 0 || y == 0 || x == 63 || y == 63 {
                expect(pixels[index + 3] < 16, "idle cell touches its border at \(x),\(y)")
            }
        }
    }
    expect(sawRed && redMinY >= 50, "feet should sit near the bottom anchor, redMinY=\(redMinY)")
} catch {
    fatalError("anchor pack failed: \(error)")
}
print("PASS: idle sprite is anchored to the bottom of its cell")

do {
    let opaque = RGBAImageCodec.cgImage(data: solidPNG(size: 128, alpha: 255))!
    expect(SpriteValidator.inspectGenerated(opaque) == [.opaqueBackground], "opaque backgrounds must be rejected")
    let empty = RGBAImageCodec.cgImage(data: solidPNG(size: 128, alpha: 0))!
    expect(SpriteValidator.inspectGenerated(empty) == [.empty], "empty images must be rejected")
    let clipped = RGBAImageCodec.cgImage(data: png(width: 80, height: 80) { pixels in
        fill(&pixels, width: 80, x0: 0, y0: 10, x1: 40, y1: 70, color: (10, 10, 10, 255))
    })!
    expect(SpriteValidator.inspectGenerated(clipped) == [.clipped], "a sprite touching the edge must be rejected")

    let tall = RGBAImageCodec.cgImage(data: petFrame(phase: 0))!
    let short = RGBAImageCodec.cgImage(data: png(width: 180, height: 180) { pixels in
        fill(&pixels, width: 180, x0: 40, y0: 80, x1: 140, y1: 120, color: (20, 20, 20, 255))
    })!
    let issue = SpriteValidator.consistencyIssues(group: "gait_E", frames: [("gait_E_0", tall), ("gait_E_1", short)])
    expect(issue?.issue == .height, "gait frames with different heights must be rejected")
    let same = SpriteValidator.consistencyIssues(group: "sleeping", frames: [
        ("sleeping_0", tall), ("sleeping_1", tall)
    ])
    expect(same?.issue == .duplicate, "identical sleeping frames must be rejected")
}
print("PASS: generated-frame validation")

// Manifest, storage, rename, delete, and orphan recovery.
do {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("piaopal-custom-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CustomPetStore(directory: directory)
    expect(store.records().isEmpty, "a new directory has no pets")
    expect(!CustomPetStore.isValidID("piaopiao"))
    expect(!CustomPetStore.isValidID("custom-abc"))
    expect(!CustomPetStore.isValidID("custom-bad/name"))
    expect(CustomPetStore.isValidID("custom-orphan12"))

    do {
        try store.save(id: "piaopiao", displayName: "Nope", mainPNG: petFrame(phase: 0), walkPNG: nil, provider: "openai", model: "gpt-image-1")
        fatalError("bundled ids must be rejected")
    } catch let error as CustomPetStoreError {
        expect(error == .reservedID, "expected reserved id error")
    }
    do {
        try store.save(id: "custom-1234abcd", displayName: " \n ", mainPNG: petFrame(phase: 0), walkPNG: nil, provider: "openai", model: "gpt-image-1")
        fatalError("blank names must be rejected")
    } catch let error as CustomPetStoreError {
        expect(error == .invalidName, "expected invalid name")
    }

    let id = "custom-1234abcd"
    try store.save(
        id: id, displayName: " 咪咪 ", mainPNG: petFrame(phase: 0), walkPNG: petFrame(phase: 1),
        provider: "openai", model: "gpt-image-1"
    )
    var records = store.records()
    expect(records.count == 1 && records[0].displayName == "咪咪", "name should be trimmed")
    expect(records[0].includesWalkAtlas && records[0].atlasFile == "\(id).png")
    expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id)-walk.png").path))

    let manifestURL = directory.appendingPathComponent(CustomPetStore.manifestName)
    let manifest = try JSONDecoder().decode(CustomPetManifest.self, from: Data(contentsOf: manifestURL))
    expect(manifest.schemaVersion == 1 && manifest.pets[0].id == id, "manifest schema")
    let raw = String(decoding: try Data(contentsOf: manifestURL), as: UTF8.self)
    expect(raw.contains("\"display_name\""), "manifest uses snake_case")
    expect(raw.contains("\"walk_atlas_file\""), "walk file is recorded")

    try store.rename(id: id, displayName: "小黑")
    expect(store.displayName(for: id) == "小黑")

    let orphanID = "custom-orphan12"
    try Data([0x89]).write(to: directory.appendingPathComponent("\(orphanID).png"))
    try Data([0x89]).write(to: directory.appendingPathComponent("\(orphanID)-walk.png"))
    try Data("{".utf8).write(to: manifestURL)
    records = store.records()
    expect(records.contains { $0.id == orphanID && $0.includesWalkAtlas }, "a corrupt manifest still lists atlas files")
    expect(!records.contains { $0.id.hasSuffix("-walk") }, "walk sheets are not pets")

    try store.delete(id: id)
    expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id).png").path))
    expect(store.displayName(for: id) == nil)
    let restored = try JSONDecoder().decode(CustomPetManifest.self, from: Data(contentsOf: manifestURL))
    expect(restored.pets.contains { $0.id == orphanID }, "deleting one pet should keep the orphan and repair the manifest")
    expect(!restored.pets.contains { $0.id == id })

    let memory = MemoryAPIKeyStore()
    try memory.save("sk-test", account: "openai")
    expect(try memory.load(account: "openai") == "sk-test")
    try memory.delete(account: "openai")
    expect(try memory.load(account: "openai") == nil)
} catch {
    fatalError("store test failed: \(error)")
}
print("PASS: manifest, storage, rename, delete, and orphan recovery")

// Custom sprite directory resolution, without touching the real Application Support folder.
do {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("piaopal-sprites-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        SkinManager.customSpritesDirectoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
    }
    SkinManager.customSpritesDirectoryOverride = directory
    let id = "custom-1234abcd"
    try Data("png".utf8).write(to: directory.appendingPathComponent("\(id).png"))
    try Data("gif".utf8).write(to: directory.appendingPathComponent("\(id).gif"))
    try Data("walk".utf8).write(to: directory.appendingPathComponent("\(id)-walk.png"))
    try Data("legacy".utf8).write(to: directory.appendingPathComponent("classic.gif"))
    expect(SkinManager.gifURL(for: id)?.lastPathComponent == "\(id).png", "PNG atlas wins over GIF")
    expect(SkinManager.walkAtlasURL(for: id)?.lastPathComponent == "\(id)-walk.png")
    expect(SkinManager.gifURL(for: "classic")?.path.hasPrefix(directory.path) == true, "custom GIF should win over the bundle")
    let listed = SkinManager.customSpriteURLs(in: directory).map(\.lastPathComponent)
    expect(listed.contains("\(id).png") && !listed.contains("\(id).gif"), "loader should prefer the PNG")
    expect(!listed.contains("\(id)-walk.png"), "walk sheet must not be listed as a pet")
    expect(listed.contains("classic.gif"))

    if let device = MTLCreateSystemDefaultDevice() {
        var frames: [String: Data] = [:]
        for purpose in CustomPetLayout.purposes(includeWalkAtlas: true) where purpose != "reference" {
            frames[purpose] = petFrame(phase: Int(purpose.split(separator: "_").last ?? "0") ?? 0)
        }
        let packed = try SpriteAtlasAssembler.pack(framePNGs: frames, includeWalkAtlas: true)
        let metalID = "custom-metalpet"
        try CustomPetStore(directory: directory).save(
            id: metalID, displayName: "Metal", mainPNG: packed.mainPNG, walkPNG: packed.walkPNG,
            provider: "openai", model: "gpt-image-1"
        )
        let manager = SkinManager()
        manager.setDevice(device)
        expect(manager.loadSkinImmediately(id: metalID), "custom atlas should upload")
        expect(manager.texture(id: metalID)?.width == 512)
        expect(manager.texture(id: metalID)?.height == 256)
        expect(manager.walkingTexture(id: metalID)?.width == 256)
        expect(manager.walkingTexture(id: metalID)?.height == 512)
        expect(manager.walkingTexture(id: "classic") == nil)
        manager.unloadSkin(id: metalID)
        expect(manager.texture(id: metalID) == nil)
        expect(manager.walkingTexture(id: metalID) == nil)
        print("PASS: custom atlas uploads to Metal and can be unloaded")
    } else {
        print("SKIP: Metal texture upload requires a GPU; directory resolution passed")
    }
} catch {
    fatalError("sprite directory test failed: \(error)")
}

print("PASS: custom pet atlas, validation, manifest, and storage")
