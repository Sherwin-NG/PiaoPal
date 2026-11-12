import Foundation
import Combine

struct CustomPetRecord: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var createdAt: String
    var atlasFile: String
    var walkAtlasFile: String?
    var cellSize: Int
    var provider: String
    var model: String
    var includesWalkAtlas: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case createdAt = "created_at"
        case atlasFile = "atlas_file"
        case walkAtlasFile = "walk_atlas_file"
        case cellSize = "cell_size"
        case provider
        case model
        case includesWalkAtlas = "includes_walk_atlas"
    }
}

struct CustomPetManifest: Codable, Equatable {
    var schemaVersion: Int
    var pets: [CustomPetRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case pets
    }
}

enum CustomPetStoreError: Error, Equatable {
    case invalidID
    case reservedID
    case invalidName
    case missingAtlas
    case writeFailed
}

struct CustomPetStore {
    var directory: URL
    var fileManager: FileManager = .default

    static let manifestName = "custom-pets.json"
    static let reservedIDs = Set(SkinManager.skinIDs + ["ai-preview"])

    static func makeID() -> String {
        "custom-\(UUID().uuidString.lowercased())"
    }

    static func isValidID(_ id: String) -> Bool {
        guard id.hasPrefix("custom-"), !reservedIDs.contains(id) else { return false }
        let rest = id.dropFirst("custom-".count)
        guard (8...80).contains(rest.count) else { return false }
        return rest.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-"
        }
    }

    static func normalizedName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...24).contains(name.count), !name.contains(where: \.isNewline) else { return nil }
        return name
    }

    func records() -> [CustomPetRecord] {
        var byID: [String: CustomPetRecord] = [:]
        if let manifest = decodeManifest() {
            for pet in manifest.pets where Self.isValidID(pet.id) {
                byID[pet.id] = pet
            }
        }
        for url in orphanAtlasURLs() {
            let id = url.deletingPathExtension().lastPathComponent
            guard Self.isValidID(id), byID[id] == nil else { continue }
            let walk = directory.appendingPathComponent("\(id)-walk.png")
            let hasWalk = fileManager.fileExists(atPath: walk.path)
            byID[id] = CustomPetRecord(
                id: id,
                displayName: id,
                createdAt: "",
                atlasFile: url.lastPathComponent,
                walkAtlasFile: hasWalk ? walk.lastPathComponent : nil,
                cellSize: SpriteAtlasAssembler.cellSize,
                provider: "unknown",
                model: "",
                includesWalkAtlas: hasWalk
            )
        }
        return byID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
    }

    func displayName(for id: String) -> String? {
        records().first { $0.id == id }?.displayName
    }

    func save(
        id: String,
        displayName: String,
        mainPNG: Data,
        walkPNG: Data?,
        provider: String,
        model: String
    ) throws {
        guard Self.isValidID(id) else {
            throw Self.reservedIDs.contains(id) ? CustomPetStoreError.reservedID : CustomPetStoreError.invalidID
        }
        guard let displayName = Self.normalizedName(displayName) else { throw CustomPetStoreError.invalidName }
        guard !mainPNG.isEmpty else { throw CustomPetStoreError.missingAtlas }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let atlasFile = "\(id).png"
        do {
            try mainPNG.write(to: directory.appendingPathComponent(atlasFile), options: .atomic)
            let walkFile: String?
            if let walkPNG {
                walkFile = "\(id)-walk.png"
                try walkPNG.write(to: directory.appendingPathComponent(walkFile!), options: .atomic)
            } else {
                walkFile = nil
                let staleWalk = directory.appendingPathComponent("\(id)-walk.png")
                if fileManager.fileExists(atPath: staleWalk.path) {
                    try fileManager.removeItem(at: staleWalk)
                }
            }
            let record = CustomPetRecord(
                id: id,
                displayName: displayName,
                createdAt: Self.timestamp(),
                atlasFile: atlasFile,
                walkAtlasFile: walkFile,
                cellSize: SpriteAtlasAssembler.cellSize,
                provider: provider,
                model: model,
                includesWalkAtlas: walkFile != nil
            )
            try writeManifest(updating: record)
        } catch let error as CustomPetStoreError {
            throw error
        } catch {
            throw CustomPetStoreError.writeFailed
        }
    }

    func rename(id: String, displayName: String) throws {
        guard Self.isValidID(id) else { throw CustomPetStoreError.invalidID }
        guard let displayName = Self.normalizedName(displayName) else { throw CustomPetStoreError.invalidName }
        guard var record = records().first(where: { $0.id == id }) else { throw CustomPetStoreError.missingAtlas }
        record.displayName = displayName
        do { try writeManifest(updating: record) } catch { throw CustomPetStoreError.writeFailed }
    }

    func delete(id: String) throws {
        guard Self.isValidID(id) else { throw CustomPetStoreError.invalidID }
        let atlas = directory.appendingPathComponent("\(id).png")
        let walk = directory.appendingPathComponent("\(id)-walk.png")
        if fileManager.fileExists(atPath: atlas.path) { try? fileManager.removeItem(at: atlas) }
        if fileManager.fileExists(atPath: walk.path) { try? fileManager.removeItem(at: walk) }
        let pets = records().filter { $0.id != id }
        do {
            try write(CustomPetManifest(schemaVersion: 1, pets: pets.sorted { $0.id < $1.id }))
        } catch {
            throw CustomPetStoreError.writeFailed
        }
    }

    private func orphanAtlasURLs() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls.filter { url in
            let base = url.deletingPathExtension().lastPathComponent
            return url.pathExtension.lowercased() == "png"
                && base.hasPrefix("custom-")
                && !base.hasSuffix("-walk")
        }
    }

    private func decodeManifest() -> CustomPetManifest? {
        let url = directory.appendingPathComponent(Self.manifestName)
        guard fileManager.fileExists(atPath: url.path) else {
            return CustomPetManifest(schemaVersion: 1, pets: [])
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CustomPetManifest.self, from: data)
    }

    private func writeManifest(updating record: CustomPetRecord) throws {
        var pets = records().filter { $0.id != record.id }
        pets.append(record)
        try write(CustomPetManifest(schemaVersion: 1, pets: pets.sorted { $0.id < $1.id }))
    }

    private func write(_ manifest: CustomPetManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(Self.manifestName), options: .atomic)
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}

@MainActor
final class CustomPetLibrary: ObservableObject {
    static let shared = CustomPetLibrary()
    @Published private(set) var records: [CustomPetRecord] = []

    private var store: CustomPetStore {
        CustomPetStore(directory: SkinManager.customSpritesDir)
    }

    private init() { reload() }

    func reload() {
        records = store.records()
    }

    func displayName(for id: String) -> String? {
        records.first { $0.id == id }?.displayName
    }
}
