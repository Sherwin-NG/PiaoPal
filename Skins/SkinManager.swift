import Foundation
import Metal
import MetalKit
import AppKit

final class SkinManager {
    private var textures: [String: MTLTexture] = [:]
    private var walkingTextures: [String: MTLTexture] = [:]
    private let lock = NSLock()
    private var device: MTLDevice?
    /// Tests point this at a temporary directory. The app leaves it nil.
    static var customSpritesDirectoryOverride: URL?

    static let defaultSkinID = "piaopiao"
    static let skinIDs = [defaultSkinID, "classic", "dog", "tora", "maia", "vaporwave"]
    private static var previewAtlasURL: URL?

    // MARK: – Custom sprites directory (Application Support)

    static var customSpritesDir: URL {
        if let customSpritesDirectoryOverride { return customSpritesDirectoryOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PiaoPal/Sprites")
    }

    /// One sprite sheet per id. A generated PNG atlas wins over an older GIF.
    /// Walk sheets (`*-walk.png`) are not selectable pets.
    static func customSpriteURLs(in directory: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        var byID: [String: URL] = [:]
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ext == "gif" || ext == "png" else { continue }
            let base = url.deletingPathExtension().lastPathComponent
            if base.hasSuffix("-walk") { continue }
            if let existing = byID[base] {
                if ext == "png" && existing.pathExtension.lowercased() != "png" {
                    byID[base] = url
                }
            } else {
                byID[base] = url
            }
        }
        return byID.values.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Returns the URL for a skin's GIF — custom (App Support) takes priority over bundle.
    static func gifURL(for id: String) -> URL? {
        // Assigned once during preview initialization, before settings/card views are created.
        if id == "ai-preview", let previewAtlasURL { return previewAtlasURL }
        // Keep the established API for callers; ImageIO also decodes the lossless PNG atlas.
        if id == defaultSkinID {
            return Bundle.main.url(forResource: "piaopiao", withExtension: "png", subdirectory: "Sprites")
        }
        let png = customSpritesDir.appendingPathComponent("\(id).png")
        if FileManager.default.fileExists(atPath: png.path) { return png }
        let custom = customSpritesDir.appendingPathComponent("\(id).gif")
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        return Bundle.main.url(forResource: id, withExtension: "gif", subdirectory: "Sprites")
    }

    static func walkAtlasURL(for id: String) -> URL? {
        if id == defaultSkinID {
            return Bundle.main.url(forResource: "piaopiao-walk", withExtension: "png", subdirectory: "Sprites")
        }
        let custom = customSpritesDir.appendingPathComponent("\(id)-walk.png")
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        return nil
    }

    var availableIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        let bundled = Self.skinIDs.filter { textures[$0] != nil }
        return bundled + textures.keys.filter { !Self.skinIDs.contains($0) }.sorted()
    }

    func setDevice(_ dev: MTLDevice) { device = dev }

    func texture(id: String) -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return textures[id]
    }

    /// Optional four-phase gait sheet. It is not another selectable companion.
    func walkingTexture(id: String) -> MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return walkingTextures[id]
    }

    /// Drops a generated pet from the GPU cache. Bundled skins stay loaded.
    func unloadSkin(id: String) {
        guard !Self.skinIDs.contains(id), id != "ai-preview" else { return }
        lock.lock()
        textures[id] = nil
        walkingTextures[id] = nil
        lock.unlock()
    }

    /// Explicit developer preview: decode synchronously so failures are visible at launch.
    /// This never copies the image into the user's installed skin directory.
    func loadPreviewSkin(from url: URL) throws -> String {
        guard let dev = device,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width % 8 == 0, image.height % 4 == 0,
              image.width / 8 == image.height / 4,
              (32...256).contains(image.width / 8),
              let texture = gifToTexture(url: url, device: dev) else {
            throw NSError(domain: "PiaoPal.Preview", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "Preview requires a single-frame 8 × 4 atlas with square 32–256 px cells: \(url.path)"
            ])
        }
        let id = "ai-preview"
        lock.lock()
        textures[id] = texture
        lock.unlock()
        Self.previewAtlasURL = url
        if url.deletingPathExtension().lastPathComponent == "piaopiao" {
            loadWalkingTexture(
                from: url.deletingLastPathComponent().appendingPathComponent("piaopiao-walk.png"),
                id: "ai-preview"
            )
        }
        return id
    }

    /// Load the default before starting the render loop, so the first frame is already PiaoPiao.
    func loadDefaultSkin() throws {
        guard loadSkinImmediately(id: Self.defaultSkinID) else {
            throw NSError(domain: "PiaoPal.Assets", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "PiaoPiao's bundled sprite atlas could not be loaded."
            ])
        }
        if let url = Self.walkAtlasURL(for: Self.defaultSkinID) {
            loadWalkingTexture(from: url, id: Self.defaultSkinID)
        }
    }

    /// Restore a saved selection before asynchronous loading; missing custom skins fall back.
    @discardableResult
    func loadSkinImmediately(id: String) -> Bool {
        guard let dev = device, let url = Self.gifURL(for: id),
              let texture = gifToTexture(url: url, device: dev) else { return false }
        lock.lock()
        textures[id] = texture
        lock.unlock()
        loadWalkingTextureIfPresent(id: id)
        return true
    }

    /// Load the other bundled skins. Completion always runs on main after every load finishes.
    func loadAll(completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for id in SkinManager.skinIDs {
            if texture(id: id) != nil { continue }
            guard let url = SkinManager.gifURL(for: id) else { continue }
            group.enter()
            loadSkinFromURL(id: id, url: url) { _ in
                group.leave()
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    /// Load generated PNG atlases and older custom GIFs. Walk sheets are not pets.
    func loadCustomSprites(completion: @escaping () -> Void = {}) {
        let dir = SkinManager.customSpritesDir
        let spriteURLs = Self.customSpriteURLs(in: dir)
        if spriteURLs.isEmpty { DispatchQueue.main.async(execute: completion); return }
        let group = DispatchGroup()
        for url in spriteURLs {
            let id = url.deletingPathExtension().lastPathComponent
            guard !SkinManager.skinIDs.contains(id) else { continue }
            group.enter()
            loadSkinFromURL(id: id, url: url) { _ in group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    /// Download a skin GIF from `url`, save to App Support, then load it.
    func downloadSprite(id: String, from url: URL, completion: @escaping (Bool) -> Void) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self, let data, error == nil else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let dir = SkinManager.customSpritesDir
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = dir.appendingPathComponent("\(id).gif")
                try data.write(to: dest)
                self.loadSkinFromURL(id: id, url: dest) { loaded in
                    DispatchQueue.main.async { completion(loaded) }
                }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }

    // MARK: – Internal loader

    func loadSkinFromURL(id: String, url: URL, completion: @escaping (Bool) -> Void) {
        guard let dev = device else { completion(false); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { completion(false); return }
            guard let tex = self.gifToTexture(url: url, device: dev) else {
                Log.skin.error("Failed to decode GIF for skin: \(id)")
                completion(false)
                return
            }
            self.lock.lock()
            self.textures[id] = tex
            self.lock.unlock()
            self.loadWalkingTextureIfPresent(id: id)
            Log.skin.info("Skin loaded: \(id)")
            completion(true)
        }
    }

    // MARK: – Private

    private func loadWalkingTextureIfPresent(id: String) {
        guard let url = Self.walkAtlasURL(for: id) else { return }
        loadWalkingTexture(from: url, id: id)
    }

    private func loadWalkingTexture(from url: URL, id: String) {
        guard let dev = device, let texture = gifToTexture(url: url, device: dev),
              texture.width == 256, texture.height == 512 else { return }
        lock.lock(); defer { lock.unlock() }
        walkingTextures[id] = texture
    }

    private func gifToTexture(url: URL, device: MTLDevice) -> MTLTexture? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let w = cgImage.width
        let h = cgImage.height

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        tex.replace(
            region: MTLRegionMake2D(0, 0, w, h),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: w * 4
        )
        return tex
    }
}
